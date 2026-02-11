%% ==========================================================================================================
%% PropEr-based property test suite for Syn's Registry functionality.
%%
%% PURPOSE: Test that syn's registry behaviour conforms to the DOCUMENTED/INTENDED
%% behaviour, NOT to model how syn actually works. We want to EXPOSE deviations
%% from the documented contract, especially in distributed scenarios.
%%
%% WHAT THIS TESTS THAT STANDARD TESTS CANNOT:
%% - Random interleaving of register/unregister/update from different nodes
%% - Metadata correctness after rapid sequences of updates across nodes
%% - Registry consistency across connected nodes after chaotic operations
%% - Process death during in-flight operations
%% - Node disconnect/reconnect with pending operations
%% - Count consistency under concurrent modifications
%%
%% KEY INVARIANTS (from ./doc):
%% 1. Connected scope nodes must agree on lookup results (global registry).
%% 2. Connected scope nodes must agree on registry_count (replicated data).
%% 3. Dead processes are automatically removed from registry on all nodes.
%% 4. After reconnection, registry converges (strong eventual consistency).
%% 5. All API functions return only their documented return values.
%% 6. local_registry_count(Scope) == registry_count(Scope, node()).
%% 7. registry_count(Scope, Node) is consistent across querying nodes.
%% ==========================================================================================================
-module(syn_registry_cluster_SUITE).

%% CT callbacks
-export([all/0, groups/0, init_per_suite/1, end_per_suite/1]).

%% Test cases
-export([syn_sequential/1]).

%% proper_statem callbacks
-export([
    initial_state/0,
    command/1,
    precondition/2,
    postcondition/3,
    next_state/3
]).

%% Command implementations
-export([
    start_node/1, stop_node/2, add_to_scope/2,
    spawn_process/2, kill_process/2,
    register_process/5, register_process_no_meta/4,
    unregister_process/3, update_registry/4,
    re_register_meta/4,
    lookup_everywhere/3,
    verify_count_consistency/2,
    verify_registry_count_per_node/3,
    verify_local_registry_count/2,
    verify_cleanup_after_kill/3,
    netsplit/3, heal_netsplit/3,
    verify_convergence/1,
    extract_peer_pid/1
]).

%% Includes
-include_lib("common_test/include/ct.hrl").
-include_lib("proper/include/proper.hrl").

%% -------------------------------------------------------------------
%% Model state
%% -------------------------------------------------------------------
-record(node_st, {
    peer_pid :: pid() | undefined,
    node :: node(),
    in_scope = false :: boolean(),
    connected = [] :: [node()]
}).

-record(state, {
    scope :: atom(),
    nodes = #{} :: #{node() => #node_st{}},
    %% The intended registry state per docs: Name -> {Pid, Meta}
    registry = #{} :: #{term() => {pid(), term()}},
    %% Processes: Pid -> Node
    processes = #{} :: #{pid() => node()},
    %% Whether pid is alive
    alive = #{} :: #{pid() => boolean()}
}).

%% -------------------------------------------------------------------
%% Macros
%% -------------------------------------------------------------------
-define(SCOPE, prop_test_scope).
-define(MAX_NODES, 4).
-define(MAX_NAMES, 8).
-define(SYNC_WAIT, 500).
-define(NUM_TESTS, 100).

%% ===================================================================
%% CT callbacks
%% ===================================================================
all() ->
    [{group, proper_tests}].

groups() ->
    [{proper_tests, [], [syn_sequential]}].

init_per_suite(Config) ->
    case net_kernel:nodename() of
        nonode@nohost ->
            _ = net_kernel:start([ct, shortnames]),
            ok;
        _ ->
            ok
    end,
    ok = syn:start(),
    Config.

end_per_suite(_Config) ->
    cleanup_all(),
    catch syn:stop(),
    ok.

%% ===================================================================
%% Test case
%% ===================================================================
syn_sequential(Config) ->
    ct:pal("=== Starting PropEr sequential test for syn registry ===~n"),
    ct:pal("Testing DOCUMENTED behaviour. Any failure means syn deviates from docs.~n"),
    Result = proper:quickcheck(
        ?FORALL(Cmds, proper_statem:commands(?MODULE),
            begin
                cleanup_all(),
                {History, State, Result0} = proper_statem:run_commands(?MODULE, Cmds),
                cleanup_all(),
                ?WHENFAIL(
                    begin
                        ct:pal("~n========== PROPERTY FAILURE ==========~n"),
                        ct:pal("This means syn's behaviour DEVIATES from documented contract!~n"),
                        ct:pal("Result: ~p~n", [Result0]),
                        ct:pal("Final model state:~n  Registry: ~p~n  Nodes: ~p~n",
                            [State#state.registry,
                             [{N, NS#node_st.in_scope} || {N, NS} <- maps:to_list(State#state.nodes)]]),
                        ct:pal("History (~p steps):~n", [length(History)]),
                        lists:foreach(fun({S, R}) ->
                            ct:pal("  State registry: ~p~n  Result: ~p~n~n",
                                [S#state.registry, R])
                        end, History),
                        ct:pal("Commands:~n~p~n", [Cmds])
                    end,
                    Result0 =:= ok
                )
            end
        ),
        [{numtests, ?NUM_TESTS}, {start_size, 3}, {max_size, 20}, noshrink]
    ),
    case Result of
        true -> ok;
        Error -> ct:fail({proper_failed, Error})
    end,
    Config.

%% ===================================================================
%% proper_statem callbacks
%% ===================================================================
initial_state() ->
    #state{scope = ?SCOPE}.

%% -------------------------------------------------------------------
%% Command generation
%% -------------------------------------------------------------------
command(#state{nodes = Nodes} = S) when map_size(Nodes) =:= 0 ->
    {call, ?MODULE, start_node, [S]};
command(#state{} = S) ->
    #state{nodes = Nodes, registry = Reg, alive = Alive} = S,
    ScopeNodeNames = [Name || {Name, #node_st{in_scope = true}} <- maps:to_list(Nodes)],
    NonScopeNodeNames = [Name || {Name, #node_st{in_scope = false}} <- maps:to_list(Nodes)],
    AlivePids = [Pid || {Pid, true} <- maps:to_list(Alive)],
    HasScope = length(ScopeNodeNames) > 0,
    HasAlive = length(AlivePids) > 0,
    HasReg = maps:size(Reg) > 0,
    MultiNode = map_size(Nodes) > 1,

    Cmds =
        %% --- Cluster management (RARE - cluster is mostly stable) ---
        [{1, {call, ?MODULE, start_node, [S]}}]

        ++ case map_size(Nodes) > 1 of
            true -> [{1, {call, ?MODULE, stop_node, [S, elements(maps:keys(Nodes))]}}];
            false -> []
        end

        ++ case NonScopeNodeNames of
            [] -> [];
            _ -> [{15, {call, ?MODULE, add_to_scope, [S, elements(NonScopeNodeNames)]}}]
        end

        ++ case HasScope of
            false -> [{100, {call, ?MODULE, add_to_scope, [S, elements(maps:keys(Nodes))]}}];
            true -> []
        end

        %% --- Process lifecycle ---
        ++ case HasScope of
            true -> [{40, {call, ?MODULE, spawn_process, [S, elements(ScopeNodeNames)]}}];
            false -> []
        end

        %% --- Registry operations (HIGH weight) ---
        ++ case HasScope andalso HasAlive of
            true ->
                [{60, {call, ?MODULE, register_process,
                    [S, gen_name(), elements(AlivePids), gen_meta(),
                     elements(ScopeNodeNames)]}},
                 {25, {call, ?MODULE, register_process_no_meta,
                    [S, gen_name(), elements(AlivePids),
                     elements(ScopeNodeNames)]}}];
            false -> []
        end

        ++ case HasReg andalso HasScope of
            true ->
                RegNames = maps:keys(Reg),
                [{50, {call, ?MODULE, unregister_process,
                    [S, elements(RegNames), elements(ScopeNodeNames)]}},
                 {50, {call, ?MODULE, update_registry,
                    [S, elements(RegNames), gen_meta(), elements(ScopeNodeNames)]}},
                 {40, {call, ?MODULE, re_register_meta,
                    [S, elements(RegNames), gen_meta(), elements(ScopeNodeNames)]}}];
            false -> []
        end

        %% === INVARIANT CHECKS ===
        %% The core value: after all the chaos, does the metadata match
        %% across connected nodes? Is the registry consistent?

        %% Lookup consistency: connected nodes must agree on BOTH pid AND meta
        ++ case HasReg andalso length(ScopeNodeNames) >= 2 of
            true ->
                [{60, {call, ?MODULE, lookup_everywhere,
                    [S, elements(maps:keys(Reg)), ScopeNodeNames]}}];
            false -> []
        end

        %% Count consistency across connected nodes
        ++ case length(ScopeNodeNames) >= 2 of
            true ->
                [{30, {call, ?MODULE, verify_count_consistency,
                    [S, ScopeNodeNames]}}];
            false -> []
        end

        %% registry_count(Scope, Node) consistency
        ++ case HasScope andalso length(ScopeNodeNames) >= 2 of
            true ->
                [{25, {call, ?MODULE, verify_registry_count_per_node,
                    [S, ScopeNodeNames, elements(ScopeNodeNames)]}},
                 {25, {call, ?MODULE, verify_local_registry_count,
                    [S, ScopeNodeNames]}}];
            false -> []
        end

        %% Kill registered process and verify cleanup
        ++ case HasAlive andalso HasReg andalso HasScope of
            true ->
                RegisteredPids = [P || {_N, {P, _M}} <- maps:to_list(Reg),
                                       maps:get(P, Alive, false)],
                case RegisteredPids of
                    [] -> [];
                    _ ->
                        [{30, {call, ?MODULE, kill_process,
                            [S, elements(RegisteredPids)]}}]
                end;
            false ->
                case HasAlive of
                    true -> [{10, {call, ?MODULE, kill_process, [S, elements(AlivePids)]}}];
                    false -> []
                end
        end

        ++ case HasReg andalso HasScope of
            true ->
                [{25, {call, ?MODULE, verify_cleanup_after_kill,
                    [S, ScopeNodeNames, maps:keys(Reg)]}}];
            false -> []
        end

        %% Net split / heal (RARE)
        %% A netsplit disconnects A from B one-directionally: A cannot see B
        %% but other nodes (e.g. C) can still see both. This creates the
        %% partial partition scenario that is hardest for distributed registries.
        ++ case MultiNode andalso HasScope of
            true ->
                AllNodes = maps:keys(Nodes),
                [{1, {call, ?MODULE, netsplit, [S, elements(AllNodes), elements(AllNodes)]}},
                 {1, {call, ?MODULE, heal_netsplit, [S, elements(AllNodes), elements(AllNodes)]}}];
            false -> []
        end

        %% Full convergence check
        ++ case length(ScopeNodeNames) >= 2 andalso HasReg of
            true ->
                [{20, {call, ?MODULE, verify_convergence, [S]}}];
            false -> []
        end,

    frequency(Cmds).

%% -------------------------------------------------------------------
%% Preconditions
%% -------------------------------------------------------------------
precondition(#state{nodes = Nodes}, {call, _, start_node, _}) ->
    map_size(Nodes) < ?MAX_NODES;
precondition(#state{nodes = Nodes}, {call, _, stop_node, [_, Node]}) ->
    map_size(Nodes) > 1 andalso maps:is_key(Node, Nodes);
precondition(#state{nodes = Nodes}, {call, _, add_to_scope, [_, Node]}) ->
    maps:is_key(Node, Nodes);
precondition(#state{nodes = Nodes}, {call, _, spawn_process, [_, Node]}) ->
    case maps:get(Node, Nodes, undefined) of
        #node_st{in_scope = true} -> true;
        _ -> false
    end;
precondition(#state{alive = Alive}, {call, _, register_process, [_, _, Pid, _, _]}) ->
    maps:get(Pid, Alive, false);
precondition(#state{alive = Alive}, {call, _, register_process_no_meta, [_, _, Pid, _]}) ->
    maps:get(Pid, Alive, false);
precondition(#state{registry = Reg, nodes = Nodes}, {call, _, unregister_process, [_, Name, Node]}) ->
    maps:is_key(Name, Reg) andalso maps:is_key(Node, Nodes);
precondition(#state{registry = Reg, nodes = Nodes}, {call, _, update_registry, [_, Name, _, Node]}) ->
    maps:is_key(Name, Reg) andalso maps:is_key(Node, Nodes);
precondition(#state{registry = Reg, nodes = Nodes}, {call, _, re_register_meta, [_, Name, _, Node]}) ->
    maps:is_key(Name, Reg) andalso maps:is_key(Node, Nodes);
precondition(#state{}, {call, _, lookup_everywhere, _}) ->
    true;
precondition(#state{}, {call, _, verify_count_consistency, _}) ->
    true;
precondition(#state{}, {call, _, verify_registry_count_per_node, _}) ->
    true;
precondition(#state{}, {call, _, verify_local_registry_count, _}) ->
    true;
precondition(#state{alive = Alive}, {call, _, kill_process, [_, Pid]}) ->
    maps:get(Pid, Alive, false);
precondition(#state{}, {call, _, verify_cleanup_after_kill, _}) ->
    true;
precondition(#state{nodes = Nodes}, {call, _, netsplit, [_, A, B]}) ->
    A =/= B andalso maps:is_key(A, Nodes) andalso maps:is_key(B, Nodes);
precondition(#state{nodes = Nodes}, {call, _, heal_netsplit, [_, A, B]}) ->
    A =/= B andalso maps:is_key(A, Nodes) andalso maps:is_key(B, Nodes);
precondition(#state{}, {call, _, verify_convergence, _}) ->
    true;
precondition(_, _) ->
    true.

%% -------------------------------------------------------------------
%% Postconditions - TEST DOCUMENTED BEHAVIOUR
%% -------------------------------------------------------------------

%% --- Infrastructure ---
postcondition(_S, {call, _, start_node, _}, {ok, _Node, _PeerPid}) -> true;
postcondition(_S, {call, _, start_node, _}, Other) ->
    ct:pal("start_node failed: ~p~n", [Other]), false;
postcondition(_S, {call, _, stop_node, _}, _) -> true;
postcondition(_S, {call, _, add_to_scope, _}, ok) -> true;
postcondition(_S, {call, _, add_to_scope, _}, Other) ->
    ct:pal("add_to_scope unexpected: ~p~n", [Other]), false;
postcondition(_S, {call, _, spawn_process, _}, Pid) when is_pid(Pid) -> true;
postcondition(_S, {call, _, spawn_process, _}, Other) ->
    ct:pal("spawn_process failed: ~p~n", [Other]), false;

%% --- Doc: register returns ok | {error, taken|not_alive|not_self} ---
postcondition(#state{}, {call, _, Cmd, _}, Result)
        when Cmd =:= register_process; Cmd =:= register_process_no_meta ->
    case Result of
        ok -> true;
        {error, taken} -> true;
        {error, not_alive} -> true;
        {error, not_self} -> true;
        {badrpc, _} -> true;
        Other ->
            ct:pal("DOCS VIOLATION: ~p returned undocumented value: ~p~n", [Cmd, Other]),
            false
    end;

%% --- Doc: unregister returns ok | {error, undefined|race_condition} ---
postcondition(_S, {call, _, unregister_process, [_, Name, _Node]}, Result) ->
    case Result of
        ok -> true;
        {error, undefined} -> true;
        {error, race_condition} -> true;
        {badrpc, _} -> true;
        Other ->
            ct:pal("DOCS VIOLATION: unregister returned undocumented value: ~p~n"
                   "  Name=~p~n", [Other, Name]),
            false
    end;

%% --- Doc: update_registry returns {ok, {Pid, NewMeta}} | {error, undefined} ---
postcondition(_S, {call, _, update_registry, [_, Name, _NewMeta, _Node]}, Result) ->
    case Result of
        {ok, {Pid, _Meta}} when is_pid(Pid) -> true;
        {error, undefined} -> true;
        {badrpc, _} -> true;
        Other ->
            ct:pal("DOCS VIOLATION: update_registry returned undocumented value: ~p~n"
                   "  Name=~p~n", [Other, Name]),
            false
    end;

%% --- Doc: re-registering same pid with new meta -> ok ---
postcondition(_S, {call, _, re_register_meta, _}, Result) ->
    case Result of
        ok -> true;
        {error, not_alive} -> true;
        {error, undefined} -> true;
        {badrpc, _} -> true;
        Other ->
            ct:pal("DOCS VIOLATION: re_register returned undocumented value: ~p~n", [Other]),
            false
    end;

%% --- CRITICAL: connected nodes must agree on BOTH pid AND metadata ---
%% This is the core test. After all the chaos of register/unregister/update
%% from random nodes, do connected nodes see the same {Pid, Meta} or undefined?
postcondition(#state{},
              {call, _, lookup_everywhere, [_, Name, _ScopeNodes]}, {LookupResults, ConnMap}) ->
    ValidResults = [{N, R} || {N, R} <- LookupResults, not is_badrpc(R)],
    case ValidResults of
        [] -> true;
        _ ->
            ResultMap = maps:from_list(ValidResults),
            lists:all(fun({Node, _NodeResult}) ->
                ConnectedNodes = maps:get(Node, ConnMap, [Node]),
                ConnectedResults = [maps:get(CN, ResultMap, skip)
                                    || CN <- ConnectedNodes,
                                       maps:is_key(CN, ResultMap)],
                ActualConnResults = [R || R <- ConnectedResults, R =/= skip],
                case ActualConnResults of
                    [] -> true;
                    _ ->
                        Unique = lists:usort(ActualConnResults),
                        case length(Unique) of
                            1 ->
                                [Agreed] = Unique,
                                case Agreed of
                                    {Pid, _Meta} when is_pid(Pid) -> true;
                                    undefined -> true;
                                    Other ->
                                        ct:pal("DOCS VIOLATION: lookup returned non-standard value: ~p~n"
                                               "  Name=~p~n", [Other, Name]),
                                        false
                                end;
                            _ ->
                                ct:pal("DOCS VIOLATION: Connected nodes disagree!~n"
                                       "  Name=~p~n"
                                       "  Results: ~p~n",
                                       [Name,
                                        [{CN, maps:get(CN, ResultMap, skip)}
                                         || CN <- ConnectedNodes,
                                            maps:is_key(CN, ResultMap)]]),
                                false
                        end
                end
            end, ValidResults)
    end;

%% --- Doc: registry_count consistent across connected scope nodes ---
postcondition(_S, {call, _, verify_count_consistency, [_, _ScopeNodes]}, {Counts, ConnMap}) ->
    check_count_consistency(Counts, ConnMap);

%% --- Doc: registry_count(Scope, Node) consistent across connected querying nodes ---
postcondition(_S, {call, _, verify_registry_count_per_node, [_, _ScopeNodes, _TargetNode]}, {Counts, ConnMap}) ->
    check_count_consistency(Counts, ConnMap);

%% --- Doc: local_registry_count(Scope) equiv registry_count(Scope, node()) ---
postcondition(_S, {call, _, verify_local_registry_count, [_, _ScopeNodes]}, Results) ->
    case Results of
        {error, _} -> true;
        Checks when is_list(Checks) ->
            lists:all(fun
                ({_Node, {badrpc, _}, _}) -> true;
                ({_Node, _, {badrpc, _}}) -> true;
                ({Node, LocalCount, PerNodeCount}) when is_integer(LocalCount),
                                                         is_integer(PerNodeCount) ->
                    case LocalCount =:= PerNodeCount of
                        true -> true;
                        false ->
                            ct:pal("DOCS VIOLATION: local_registry_count != registry_count(Scope, node())!~n"
                                   "  Node=~p local=~p per_node=~p~n",
                                   [Node, LocalCount, PerNodeCount]),
                            false
                    end
            end, Checks)
    end;

%% --- Doc: "processes are automatically monitored and removed if they die" ---
postcondition(_S, {call, _, kill_process, _}, _Result) ->
    true;

postcondition(#state{alive = Alive},
              {call, _, verify_cleanup_after_kill, [_, _ScopeNodes, _RegNames]}, Results) ->
    case Results of
        {error, _} -> true;
        Checks when is_list(Checks) ->
            lists:all(fun
                ({_Name, _Node, undefined}) ->
                    true;
                ({_Name, _Node, {badrpc, _}}) ->
                    true;
                ({_Name, _Node, {Pid, _Meta}}) when is_pid(Pid) ->
                    case maps:get(Pid, Alive, false) of
                        false ->
                            ct:pal("DOCS VIOLATION: Dead process still registered!~n"
                                   "  Pid=~p~n", [Pid]),
                            false;
                        true ->
                            true
                    end
            end, Checks)
    end;

%% --- Network operations ---
postcondition(_S, {call, _, netsplit, _}, _) -> true;
postcondition(_S, {call, _, heal_netsplit, _}, _) -> true;

%% --- Doc: After reconnection, registry converges ---
postcondition(_S, {call, _, verify_convergence, _}, Results) ->
    case Results of
        {error, _} -> true;
        ok -> true;
        {convergence_failure, Details} ->
            ct:pal("DOCS VIOLATION: Registry failed to converge!~n"
                   "  Details: ~p~n", [Details]),
            false
    end;

postcondition(_S, {call, _, Cmd, _}, Result) ->
    ct:pal("Unhandled postcondition: ~p -> ~p~n", [Cmd, Result]),
    false.

%% -------------------------------------------------------------------
%% Next state
%% -------------------------------------------------------------------
next_state(#state{nodes = Nodes} = S, Result, {call, _, start_node, _}) ->
    NodeName = {call, erlang, element, [2, Result]},
    NodeSt = #node_st{
        peer_pid = {call, ?MODULE, extract_peer_pid, [Result]},
        node = NodeName,
        in_scope = false,
        connected = maps:keys(Nodes)
    },
    Nodes2 = maps:map(fun(_K, V) ->
        V#node_st{connected = [NodeName | V#node_st.connected]}
    end, Nodes),
    S#state{nodes = Nodes2#{NodeName => NodeSt}};

next_state(#state{nodes = Nodes, registry = Reg, processes = Procs, alive = Alive} = S,
           _Result, {call, _, stop_node, [_, StoppedNode]}) ->
    Nodes2 = maps:remove(StoppedNode, Nodes),
    Nodes3 = maps:map(fun(_K, V) ->
        V#node_st{connected = lists:delete(StoppedNode, V#node_st.connected)}
    end, Nodes2),
    Reg2 = maps:filter(fun(_Name, {Pid, _Meta}) ->
        maps:get(Pid, Procs, undefined) =/= StoppedNode
    end, Reg),
    PidsOnNode = [P || {P, N} <- maps:to_list(Procs), N =:= StoppedNode],
    Procs2 = maps:without(PidsOnNode, Procs),
    Alive2 = maps:without(PidsOnNode, Alive),
    S#state{nodes = Nodes3, registry = Reg2, processes = Procs2, alive = Alive2};

next_state(#state{nodes = Nodes} = S, _Result, {call, _, add_to_scope, [_, TargetNode]}) ->
    case maps:get(TargetNode, Nodes, undefined) of
        undefined -> S;
        NodeSt ->
            S#state{nodes = Nodes#{TargetNode => NodeSt#node_st{in_scope = true}}}
    end;

next_state(#state{processes = Procs, alive = Alive} = S, Pid,
           {call, _, spawn_process, [_, OnNode]}) ->
    S#state{
        processes = Procs#{Pid => OnNode},
        alive = Alive#{Pid => true}
    };

next_state(#state{registry = Reg} = S, _Result,
           {call, _, register_process, [_, Name, Pid, Meta, _OnNode]}) ->
    S#state{registry = Reg#{Name => {Pid, Meta}}};

next_state(#state{registry = Reg} = S, _Result,
           {call, _, register_process_no_meta, [_, Name, Pid, _OnNode]}) ->
    S#state{registry = Reg#{Name => {Pid, undefined}}};

next_state(#state{registry = Reg} = S, _Result,
           {call, _, unregister_process, [_, Name, _OnNode]}) ->
    S#state{registry = maps:remove(Name, Reg)};

next_state(#state{registry = Reg} = S, _Result,
           {call, _, update_registry, [_, Name, NewMeta, _OnNode]}) ->
    case maps:get(Name, Reg, undefined) of
        undefined -> S;
        {Pid, _OldMeta} ->
            S#state{registry = Reg#{Name => {Pid, NewMeta}}}
    end;

next_state(#state{registry = Reg} = S, _Result,
           {call, _, re_register_meta, [_, Name, NewMeta, _OnNode]}) ->
    case maps:get(Name, Reg, undefined) of
        undefined -> S;
        {Pid, _OldMeta} ->
            S#state{registry = Reg#{Name => {Pid, NewMeta}}}
    end;

next_state(#state{registry = Reg, alive = Alive, processes = Procs} = S, _Result,
           {call, _, kill_process, [_, Pid]}) ->
    Reg2 = maps:filter(fun(_Name, {RPid, _Meta}) ->
        RPid =/= Pid
    end, Reg),
    S#state{registry = Reg2, alive = maps:remove(Pid, Alive),
            processes = maps:remove(Pid, Procs)};

next_state(#state{nodes = Nodes} = S, _Result,
           {call, _, netsplit, [_, NodeA, NodeB]}) ->
    %% erlang:disconnect_node is bidirectional at the distribution level,
    %% but with -connect_all false and dist_auto_connect never, other
    %% nodes won't auto-reconnect them. So A<->B link is broken, but
    %% C can still see both A and B independently.
    Nodes2 = case maps:get(NodeA, Nodes, undefined) of
        undefined -> Nodes;
        NsA -> Nodes#{NodeA => NsA#node_st{connected = lists:delete(NodeB, NsA#node_st.connected)}}
    end,
    Nodes3 = case maps:get(NodeB, Nodes2, undefined) of
        undefined -> Nodes2;
        NsB -> Nodes2#{NodeB => NsB#node_st{connected = lists:delete(NodeA, NsB#node_st.connected)}}
    end,
    S#state{nodes = Nodes3};

next_state(#state{nodes = Nodes} = S, _Result,
           {call, _, heal_netsplit, [_, NodeA, NodeB]}) ->
    Nodes2 = case maps:get(NodeA, Nodes, undefined) of
        undefined -> Nodes;
        NsA ->
            case lists:member(NodeB, NsA#node_st.connected) of
                true -> Nodes;
                false -> Nodes#{NodeA => NsA#node_st{connected = [NodeB | NsA#node_st.connected]}}
            end
    end,
    Nodes3 = case maps:get(NodeB, Nodes2, undefined) of
        undefined -> Nodes2;
        NsB ->
            case lists:member(NodeA, NsB#node_st.connected) of
                true -> Nodes2;
                false -> Nodes2#{NodeB => NsB#node_st{connected = [NodeA | NsB#node_st.connected]}}
            end
    end,
    S#state{nodes = Nodes3};

next_state(S, _Result, _Call) ->
    S.

%% ===================================================================
%% Command implementations
%% ===================================================================

extract_peer_pid({ok, _Node, PeerPid}) -> PeerPid;
extract_peer_pid(_) -> undefined.

start_node(#state{nodes = Nodes}) ->
    Id = map_size(Nodes) + 1,
    NodeShortName = list_to_atom("syn_prop_" ++ integer_to_list(Id)
        ++ "_" ++ integer_to_list(erlang:unique_integer([positive]))),
    {ok, PeerPid, Node} = peer:start(#{
        name => NodeShortName,
        args => ["-connect_all", "false", "-kernel", "dist_auto_connect", "never"],
        connection => 0
    }),
    CodePath = lists:filter(fun(Path) ->
        nomatch =/= string:find(Path, "/syn/")
    end, code:get_path()),
    ok = rpc:call(Node, code, add_pathsa, [CodePath]),
    ExistingNodes = [N#node_st.node || N <- maps:values(Nodes)],
    lists:foreach(fun(EN) ->
        rpc:call(Node, net_kernel, connect_node, [EN]),
        rpc:call(EN, net_kernel, connect_node, [Node])
    end, ExistingNodes),
    rpc:call(Node, net_kernel, connect_node, [node()]),
    {ok, _} = rpc:call(Node, application, ensure_all_started, [syn]),
    timer:sleep(200),
    {ok, Node, PeerPid}.

stop_node(#state{nodes = Nodes}, StoppedNode) ->
    case maps:get(StoppedNode, Nodes, undefined) of
        undefined -> ok;
        #node_st{peer_pid = PeerPid} when is_pid(PeerPid) ->
            catch rpc:call(StoppedNode, net_kernel, connect_node, [node()]),
            catch peer:stop(PeerPid),
            timer:sleep(?SYNC_WAIT),
            ok;
        _ ->
            ok
    end.

add_to_scope(#state{}, TargetNode) ->
    Res = rpc:call(TargetNode, syn, add_node_to_scopes, [[?SCOPE]]),
    timer:sleep(?SYNC_WAIT),
    Res.

spawn_process(#state{}, OnNode) ->
    spawn(OnNode, fun process_loop/0).

kill_process(#state{}, Pid) ->
    case is_process_alive_remote(Pid) of
        true ->
            MRef = monitor(process, Pid),
            exit(Pid, kill),
            receive
                {'DOWN', MRef, process, Pid, _} -> ok
            after 5000 ->
                demonitor(MRef, [flush]),
                timeout
            end;
        false ->
            already_dead
    end,
    timer:sleep(?SYNC_WAIT),
    ok.

register_process_no_meta(#state{}, Name, Pid, OnNode) ->
    case rpc:call(OnNode, syn, register, [?SCOPE, Name, Pid]) of
        {badrpc, {'EXIT', {invalid_scope, _}}} -> {badrpc, invalid_scope};
        {badrpc, {'EXIT', {invalid_remote_scope, _, _}}} -> {badrpc, invalid_remote_scope};
        {badrpc, Reason} -> {badrpc, Reason};
        Result ->
            timer:sleep(100),
            Result
    end.

register_process(#state{}, Name, Pid, Meta, OnNode) ->
    case rpc:call(OnNode, syn, register, [?SCOPE, Name, Pid, Meta]) of
        {badrpc, {'EXIT', {invalid_scope, _}}} -> {badrpc, invalid_scope};
        {badrpc, {'EXIT', {invalid_remote_scope, _, _}}} -> {badrpc, invalid_remote_scope};
        {badrpc, Reason} -> {badrpc, Reason};
        Result ->
            timer:sleep(100),
            Result
    end.

unregister_process(#state{}, Name, OnNode) ->
    case rpc:call(OnNode, syn, unregister, [?SCOPE, Name]) of
        {badrpc, {'EXIT', {invalid_scope, _}}} -> {badrpc, invalid_scope};
        {badrpc, Reason} -> {badrpc, Reason};
        Result ->
            timer:sleep(100),
            Result
    end.

update_registry(#state{}, Name, NewMeta, OnNode) ->
    Fun = fun(_Pid, _OldMeta) -> NewMeta end,
    case rpc:call(OnNode, syn, update_registry, [?SCOPE, Name, Fun]) of
        {badrpc, {'EXIT', {invalid_scope, _}}} -> {badrpc, invalid_scope};
        {badrpc, Reason} -> {badrpc, Reason};
        Result ->
            timer:sleep(100),
            Result
    end.

re_register_meta(#state{}, Name, NewMeta, OnNode) ->
    case rpc:call(OnNode, syn, lookup, [?SCOPE, Name]) of
        {badrpc, _} = Err ->
            Err;
        undefined ->
            {error, undefined};
        {Pid, _OldMeta} when is_pid(Pid) ->
            case rpc:call(OnNode, syn, register, [?SCOPE, Name, Pid, NewMeta]) of
                {badrpc, {'EXIT', {invalid_scope, _}}} -> {badrpc, invalid_scope};
                {badrpc, Reason} -> {badrpc, Reason};
                Result ->
                    timer:sleep(100),
                    Result
            end
    end.

%% === INVARIANT: lookup on connected scope nodes must agree ===
lookup_everywhere(#state{}, Name, ScopeNodes) ->
    timer:sleep(?SYNC_WAIT),
    Results = lists:map(fun(Node) ->
        Res = case rpc:call(Node, syn, lookup, [?SCOPE, Name]) of
            {badrpc, {'EXIT', {invalid_scope, _}}} -> {badrpc, invalid_scope};
            {badrpc, Reason} -> {badrpc, Reason};
            R -> R
        end,
        {Node, Res}
    end, ScopeNodes),
    ConnMap = build_conn_map(ScopeNodes),
    {Results, ConnMap}.

%% === INVARIANT: registry_count must be consistent among connected nodes ===
verify_count_consistency(#state{}, ScopeNodes) ->
    timer:sleep(?SYNC_WAIT),
    Counts = lists:map(fun(Node) ->
        Count = case rpc:call(Node, syn, registry_count, [?SCOPE]) of
            {badrpc, {'EXIT', {invalid_scope, _}}} -> {badrpc, invalid_scope};
            {badrpc, Reason} -> {badrpc, Reason};
            C -> C
        end,
        {Node, Count}
    end, ScopeNodes),
    ConnMap = build_conn_map(ScopeNodes),
    {Counts, ConnMap}.

%% === INVARIANT: registry_count(Scope, Node) consistent across connected querying nodes ===
verify_registry_count_per_node(#state{}, ScopeNodes, TargetNode) ->
    timer:sleep(?SYNC_WAIT),
    Counts = lists:map(fun(QueryNode) ->
        Count = case rpc:call(QueryNode, syn, registry_count, [?SCOPE, TargetNode]) of
            {badrpc, {'EXIT', {invalid_scope, _}}} -> {badrpc, invalid_scope};
            {badrpc, Reason} -> {badrpc, Reason};
            C -> C
        end,
        {QueryNode, Count}
    end, ScopeNodes),
    ConnMap = build_conn_map(ScopeNodes),
    {Counts, ConnMap}.

%% === INVARIANT: local_registry_count(Scope) == registry_count(Scope, node()) ===
verify_local_registry_count(#state{}, ScopeNodes) ->
    timer:sleep(?SYNC_WAIT),
    lists:map(fun(Node) ->
        LocalCount = case rpc:call(Node, syn, local_registry_count, [?SCOPE]) of
            {badrpc, _} = E1 -> E1;
            C1 -> C1
        end,
        PerNodeCount = case rpc:call(Node, syn, registry_count, [?SCOPE, Node]) of
            {badrpc, _} = E2 -> E2;
            C2 -> C2
        end,
        {Node, LocalCount, PerNodeCount}
    end, ScopeNodes).

%% === INVARIANT: dead processes must be cleaned up ===
verify_cleanup_after_kill(#state{}, ScopeNodes, RegNames) ->
    timer:sleep(?SYNC_WAIT),
    QueryNode = hd(ScopeNodes),
    Results = lists:map(fun(Name) ->
        Res = case rpc:call(QueryNode, syn, lookup, [?SCOPE, Name]) of
            {badrpc, {'EXIT', {invalid_scope, _}}} -> {badrpc, invalid_scope};
            {badrpc, Reason} -> {badrpc, Reason};
            R -> R
        end,
        {Name, QueryNode, Res}
    end, RegNames),
    Results.

%% Net split: disconnect A from B one-directionally.
%% Because nodes are started with -connect_all false and dist_auto_connect never,
%% no other node will auto-reconnect them. This means if we have nodes A, B, C:
%% - netsplit(A, B) makes A and B unable to see each other
%% - but C can still see both A and B
%% This is the classic partial partition scenario.
netsplit(#state{}, NodeA, NodeB) ->
    rpc:call(NodeA, erlang, disconnect_node, [NodeB]),
    timer:sleep(?SYNC_WAIT),
    ok.

%% Heal: reconnect A and B bidirectionally.
heal_netsplit(#state{}, NodeA, NodeB) ->
    rpc:call(NodeA, net_kernel, connect_node, [NodeB]),
    rpc:call(NodeB, net_kernel, connect_node, [NodeA]),
    timer:sleep(?SYNC_WAIT),
    ok.

%% === INVARIANT: full convergence after reconnection ===
verify_convergence(#state{nodes = Nodes}) ->
    ScopeNodes = [Name || {Name, #node_st{in_scope = true}} <- maps:to_list(Nodes)],
    case length(ScopeNodes) < 2 of
        true -> ok;
        false ->
            %% Reconnect all scope nodes
            lists:foreach(fun(N1) ->
                lists:foreach(fun(N2) ->
                    case N1 =/= N2 of
                        true ->
                            rpc:call(N1, net_kernel, connect_node, [N2]);
                        false -> ok
                    end
                end, ScopeNodes)
            end, ScopeNodes),
            timer:sleep(?SYNC_WAIT * 2),
            Counts = lists:map(fun(Node) ->
                case rpc:call(Node, syn, registry_count, [?SCOPE]) of
                    {badrpc, _} -> -1;
                    C when is_integer(C) -> C;
                    _ -> -1
                end
            end, ScopeNodes),
            ValidCounts = [C || C <- Counts, C >= 0],
            case ValidCounts of
                [] -> ok;
                _ ->
                    case lists:usort(ValidCounts) of
                        [_] -> ok;
                        Multiple ->
                            {convergence_failure, #{
                                scope_nodes => ScopeNodes,
                                counts => lists:zip(ScopeNodes, Counts),
                                unique_counts => Multiple
                            }}
                    end
            end
    end.

%% ===================================================================
%% Generators
%% ===================================================================
gen_name() ->
    frequency([
        {5, {name, choose(1, ?MAX_NAMES)}},
        {3, choose(1, ?MAX_NAMES)},
        {2, elements([alpha, beta, gamma, delta, epsilon])}
    ]).

gen_meta() ->
    frequency([
        {3, undefined},
        {3, choose(1, 100)},
        {2, {meta, choose(1, 50)}},
        {2, list(choose(1, 5))}
    ]).

%% ===================================================================
%% Helpers
%% ===================================================================
build_conn_map(ScopeNodes) ->
    lists:foldl(fun(Node, Acc) ->
        Connected = case rpc:call(Node, erlang, nodes, []) of
            {badrpc, _} -> [];
            Ns -> Ns
        end,
        ScopeConnected = [N || N <- Connected, lists:member(N, ScopeNodes)],
        Acc#{Node => [Node | ScopeConnected]}
    end, #{}, ScopeNodes).

is_badrpc({badrpc, _}) -> true;
is_badrpc(_) -> false.

%% Shared postcondition helper for count consistency checks
check_count_consistency(Counts, ConnMap) ->
    CountMap = maps:from_list([{N, C} || {N, C} <- Counts,
                                          is_integer(C), C >= 0]),
    case maps:size(CountMap) < 2 of
        true -> true;
        false ->
            lists:all(fun({Node, Count}) ->
                case is_integer(Count) andalso Count >= 0 of
                    false -> true;
                    true ->
                        ConnectedNodes = maps:get(Node, ConnMap, [Node]),
                        ConnCounts = [maps:get(CN, CountMap, skip)
                                      || CN <- ConnectedNodes,
                                         maps:is_key(CN, CountMap)],
                        ActualCounts = [C || C <- ConnCounts, C =/= skip],
                        case lists:usort(ActualCounts) of
                            [_] -> true;
                            [] -> true;
                            Multiple ->
                                ct:pal("DOCS VIOLATION: count inconsistency among connected nodes!~n"
                                       "  Node ~p count: ~p~n"
                                       "  Connected counts: ~p~n"
                                       "  Unique: ~p~n",
                                       [Node, Count,
                                        [{CN, maps:get(CN, CountMap, skip)} || CN <- ConnectedNodes],
                                        Multiple]),
                                false
                        end
                end
            end, Counts)
    end.

process_loop() ->
    receive
        stop -> ok;
        _ -> process_loop()
    end.

is_process_alive_remote(Pid) ->
    try
        Node = node(Pid),
        case rpc:call(Node, erlang, is_process_alive, [Pid]) of
            true -> true;
            _ -> false
        end
    catch _:_ ->
        false
    end.

cleanup_all() ->
    %% Find all peer nodes we started
    PeerNodes = [N || N <- nodes(),
                 lists:prefix("syn_prop_", atom_to_list(N))],
    %% Stop syn on each peer
    lists:foreach(fun(N) ->
        catch rpc:call(N, application, stop, [syn])
    end, PeerNodes),
    %% Stop all peer processes (this actually kills the VMs)
    lists:foreach(fun(N) ->
        catch rpc:call(N, erlang, halt, [0])
    end, PeerNodes),
    %% Disconnect any lingering connections
    lists:foreach(fun(N) ->
        catch erlang:disconnect_node(N)
    end, PeerNodes),
    timer:sleep(300),
    %% Reset syn on CT node
    catch application:stop(syn),
    timer:sleep(100),
    catch syn:start(),
    ok.
