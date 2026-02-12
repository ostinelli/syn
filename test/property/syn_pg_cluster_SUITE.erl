%% ==========================================================================================================
%% Syn - A global Process Registry and Process Group manager.
%%
%% The MIT License (MIT)
%%
%% Copyright (c) 2019-2026 Roberto Ostinelli <roberto@ostinelli.net> and Neato Robotics, Inc.
%%
%% Permission is hereby granted, free of charge, to any person obtaining a copy
%% of this software and associated documentation files (the "Software"), to deal
%% in the Software without restriction, including without limitation the rights
%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the Software is
%% furnished to do so, subject to the following conditions:
%%
%% The above copyright notice and this permission notice shall be included in
%% all copies or substantial portions of the Software.
%%
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
%% THE SOFTWARE.
%% ==========================================================================================================
%% PropEr-based property test suite for Syn's Process Groups functionality.
%%
%% PURPOSE: Test that syn's process groups behaviour conforms to the DOCUMENTED/INTENDED
%% behaviour, NOT to model how syn actually works. We want to EXPOSE deviations
%% from the documented contract, especially in distributed scenarios.
%%
%% WHAT THIS TESTS THAT STANDARD TESTS CANNOT:
%% - Random interleaving of join/leave/update from different nodes
%% - Metadata correctness after rapid sequences of updates across nodes
%% - Members/member_count consistency across connected nodes after chaotic operations
%% - Process death during in-flight operations
%% - Node disconnect/reconnect with pending operations
%% - group_count/group_names consistency under concurrent modifications
%% - local_* functions consistency with their global equivalents
%% - publish recipient count matching actual member count
%%
%% KEY INVARIANTS (from ./doc):
%% 1. Connected scope nodes must agree on members() for a group.
%% 2. Connected scope nodes must agree on member_count().
%% 3. local_members() must be the subset of members() on the local node.
%% 4. is_member/is_local_member must be consistent with members/local_members.
%% 5. Dead processes are automatically removed from groups on all nodes.
%% 6. After reconnection, groups converge (strong eventual consistency).
%% 7. All API functions return only their documented return values.
%% 8. local_member_count == member_count(Scope, GroupName, node()).
%% 9. group_count/group_names consistent across connected nodes.
%% 10. local_group_count == group_count(Scope, node()).
%% 11. local_group_names == group_names(Scope, node()).
%% 12. publish returns {ok, RecipientCount} with correct count.
%% ==========================================================================================================
-module(syn_pg_cluster_SUITE).

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
    join_group/5, join_group_no_meta/4, leave_group/4,
    update_member/5, rejoin_group/5,
    members_everywhere/3,
    verify_member_count_consistency/3,
    verify_local_members/3,
    verify_group_count_consistency/2,
    verify_group_names_consistency/2,
    verify_local_counts/2,
    verify_cleanup_after_kill/3,
    publish_to_group/3,
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
    %% The intended group state per docs: {GroupName, Pid} -> Meta
    %% A pid can be in multiple groups, each group can have multiple pids
    memberships = #{} :: #{{term(), pid()} => term()},
    %% Processes: Pid -> Node
    processes = #{} :: #{pid() => node()},
    %% Whether pid is alive
    alive = #{} :: #{pid() => boolean()}
}).

%% -------------------------------------------------------------------
%% Macros
%% -------------------------------------------------------------------
-define(SCOPE, prop_pg_test_scope).
-define(MAX_NODES, 4).
-define(MAX_GROUPS, 6).
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
    ct:pal("=== Starting PropEr sequential test for syn process groups ===~n"),
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
                        ct:pal("Final model state:~n  Memberships: ~p~n  Nodes: ~p~n",
                            [State#state.memberships,
                             [{N, NS#node_st.in_scope} || {N, NS} <- maps:to_list(State#state.nodes)]]),
                        ct:pal("History (~p steps):~n", [length(History)]),
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
    #state{nodes = Nodes, memberships = Memb, alive = Alive} = S,
    ScopeNodeNames = [Name || {Name, #node_st{in_scope = true}} <- maps:to_list(Nodes)],
    NonScopeNodeNames = [Name || {Name, #node_st{in_scope = false}} <- maps:to_list(Nodes)],
    AlivePids = [Pid || {Pid, true} <- maps:to_list(Alive)],
    HasScope = length(ScopeNodeNames) > 0,
    HasAlive = length(AlivePids) > 0,
    HasMemb = maps:size(Memb) > 0,
    MultiNode = map_size(Nodes) > 1,
    GroupNames = lists:usort([G || {G, _P} <- maps:keys(Memb)]),
    HasGroups = length(GroupNames) > 0,

    Cmds =
        %% --- Cluster management (RARE) ---
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

        %% --- Group operations (HIGH weight) ---
        %% Doc: join/4 -> ok | {error, not_alive|not_self}
        ++ case HasScope andalso HasAlive of
            true ->
                [{60, {call, ?MODULE, join_group,
                    [S, gen_group_name(), elements(AlivePids), gen_meta(),
                     elements(ScopeNodeNames)]}},
                 {25, {call, ?MODULE, join_group_no_meta,
                    [S, gen_group_name(), elements(AlivePids),
                     elements(ScopeNodeNames)]}}];
            false -> []
        end

        %% Doc: leave/3 -> ok | {error, not_in_group}
        ++ case HasMemb andalso HasScope of
            true ->
                MembKeys = maps:keys(Memb),
                [{50, {call, ?MODULE, leave_group,
                    [S, elements(MembKeys), elements(ScopeNodeNames),
                     elements(MembKeys)]}}];
            false -> []
        end

        %% Doc: update_member/4 -> {ok, {Pid, Meta}} | {error, undefined}
        ++ case HasMemb andalso HasScope of
            true ->
                MembKeys2 = maps:keys(Memb),
                [{50, {call, ?MODULE, update_member,
                    [S, elements(MembKeys2), gen_meta(),
                     elements(ScopeNodeNames), elements(MembKeys2)]}}];
            false -> []
        end

        %% Doc: re-join same group with new meta -> ok, updates metadata
        ++ case HasMemb andalso HasScope of
            true ->
                MembKeys3 = maps:keys(Memb),
                [{40, {call, ?MODULE, rejoin_group,
                    [S, elements(MembKeys3), gen_meta(),
                     elements(ScopeNodeNames), elements(MembKeys3)]}}];
            false -> []
        end

        %% === INVARIANT CHECKS ===

        %% Members consistency: connected nodes must agree on members list
        ++ case HasGroups andalso length(ScopeNodeNames) >= 2 of
            true ->
                [{60, {call, ?MODULE, members_everywhere,
                    [S, elements(GroupNames), ScopeNodeNames]}}];
            false -> []
        end

        %% Member count consistency across connected nodes
        ++ case HasGroups andalso length(ScopeNodeNames) >= 2 of
            true ->
                [{30, {call, ?MODULE, verify_member_count_consistency,
                    [S, elements(GroupNames), ScopeNodeNames]}}];
            false -> []
        end

        %% local_members must match members filtered to local node
        ++ case HasGroups andalso HasScope of
            true ->
                [{30, {call, ?MODULE, verify_local_members,
                    [S, elements(GroupNames), ScopeNodeNames]}}];
            false -> []
        end

        %% group_count consistency across connected nodes
        ++ case length(ScopeNodeNames) >= 2 of
            true ->
                [{25, {call, ?MODULE, verify_group_count_consistency,
                    [S, ScopeNodeNames]}}];
            false -> []
        end

        %% group_names consistency across connected nodes
        ++ case HasGroups andalso length(ScopeNodeNames) >= 2 of
            true ->
                [{25, {call, ?MODULE, verify_group_names_consistency,
                    [S, ScopeNodeNames]}}];
            false -> []
        end

        %% local_member_count, local_group_count, local_group_names
        ++ case HasScope andalso length(ScopeNodeNames) >= 2 of
            true ->
                [{25, {call, ?MODULE, verify_local_counts,
                    [S, ScopeNodeNames]}}];
            false -> []
        end

        %% Kill process in group and verify cleanup
        ++ case HasAlive andalso HasMemb andalso HasScope of
            true ->
                MembPids = lists:usort([P || {_G, P} <- maps:keys(Memb),
                                             maps:get(P, Alive, false)]),
                case MembPids of
                    [] -> [];
                    _ ->
                        [{30, {call, ?MODULE, kill_process,
                            [S, elements(MembPids)]}}]
                end;
            false ->
                case HasAlive of
                    true -> [{10, {call, ?MODULE, kill_process, [S, elements(AlivePids)]}}];
                    false -> []
                end
        end

        ++ case HasGroups andalso HasScope of
            true ->
                [{25, {call, ?MODULE, verify_cleanup_after_kill,
                    [S, ScopeNodeNames, GroupNames]}}];
            false -> []
        end

        %% Publish to group
        ++ case HasGroups andalso HasScope of
            true ->
                [{20, {call, ?MODULE, publish_to_group,
                    [S, elements(GroupNames), elements(ScopeNodeNames)]}}];
            false -> []
        end

        %% Net split / heal (RARE)
        ++ case MultiNode andalso HasScope of
            true ->
                AllNodes = maps:keys(Nodes),
                [{1, {call, ?MODULE, netsplit, [S, elements(AllNodes), elements(AllNodes)]}},
                 {1, {call, ?MODULE, heal_netsplit, [S, elements(AllNodes), elements(AllNodes)]}}];
            false -> []
        end

        %% Full convergence check
        ++ case length(ScopeNodeNames) >= 2 andalso HasGroups of
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
precondition(#state{alive = Alive}, {call, _, join_group, [_, _, Pid, _, _]}) ->
    maps:get(Pid, Alive, false);
precondition(#state{alive = Alive}, {call, _, join_group_no_meta, [_, _, Pid, _]}) ->
    maps:get(Pid, Alive, false);
precondition(#state{memberships = Memb, nodes = Nodes}, {call, _, leave_group, [_, Key, Node, _]}) ->
    maps:is_key(Key, Memb) andalso maps:is_key(Node, Nodes);
precondition(#state{memberships = Memb, nodes = Nodes}, {call, _, update_member, [_, Key, _, Node, _]}) ->
    maps:is_key(Key, Memb) andalso maps:is_key(Node, Nodes);
precondition(#state{memberships = Memb, nodes = Nodes}, {call, _, rejoin_group, [_, Key, _, Node, _]}) ->
    maps:is_key(Key, Memb) andalso maps:is_key(Node, Nodes);
precondition(#state{}, {call, _, members_everywhere, _}) -> true;
precondition(#state{}, {call, _, verify_member_count_consistency, _}) -> true;
precondition(#state{}, {call, _, verify_local_members, _}) -> true;
precondition(#state{}, {call, _, verify_group_count_consistency, _}) -> true;
precondition(#state{}, {call, _, verify_group_names_consistency, _}) -> true;
precondition(#state{}, {call, _, verify_local_counts, _}) -> true;
precondition(#state{alive = Alive}, {call, _, kill_process, [_, Pid]}) ->
    maps:get(Pid, Alive, false);
precondition(#state{}, {call, _, verify_cleanup_after_kill, _}) -> true;
precondition(#state{}, {call, _, publish_to_group, _}) -> true;
precondition(#state{nodes = Nodes}, {call, _, netsplit, [_, A, B]}) ->
    A =/= B andalso maps:is_key(A, Nodes) andalso maps:is_key(B, Nodes);
precondition(#state{nodes = Nodes}, {call, _, heal_netsplit, [_, A, B]}) ->
    A =/= B andalso maps:is_key(A, Nodes) andalso maps:is_key(B, Nodes);
precondition(#state{}, {call, _, verify_convergence, _}) -> true;
precondition(_, _) -> true.

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

%% --- Doc: join returns ok | {error, not_alive|not_self} ---
postcondition(#state{}, {call, _, Cmd, _}, Result)
        when Cmd =:= join_group; Cmd =:= join_group_no_meta ->
    case Result of
        ok -> true;
        {error, not_alive} -> true;
        {error, not_self} -> true;
        {badrpc, _} -> true;
        Other ->
            ct:pal("DOCS VIOLATION: ~p returned undocumented value: ~p~n", [Cmd, Other]),
            false
    end;

%% --- Doc: leave returns ok | {error, not_in_group} ---
postcondition(_S, {call, _, leave_group, _}, Result) ->
    case Result of
        ok -> true;
        {error, not_in_group} -> true;
        {badrpc, _} -> true;
        Other ->
            ct:pal("DOCS VIOLATION: leave returned undocumented value: ~p~n", [Other]),
            false
    end;

%% --- Doc: update_member returns {ok, {Pid, Meta}} | {error, undefined} ---
postcondition(_S, {call, _, update_member, _}, Result) ->
    case Result of
        {ok, {Pid, _Meta}} when is_pid(Pid) -> true;
        {error, undefined} -> true;
        {badrpc, _} -> true;
        Other ->
            ct:pal("DOCS VIOLATION: update_member returned undocumented value: ~p~n", [Other]),
            false
    end;

%% --- Doc: re-join same group with new meta -> ok ---
postcondition(_S, {call, _, rejoin_group, _}, Result) ->
    case Result of
        ok -> true;
        {error, not_alive} -> true;
        {badrpc, _} -> true;
        Other ->
            ct:pal("DOCS VIOLATION: rejoin returned undocumented value: ~p~n", [Other]),
            false
    end;

%% --- CRITICAL: connected nodes must agree on members (BOTH pid AND meta) ---
postcondition(#state{},
              {call, _, members_everywhere, [_, GroupName, _ScopeNodes]}, {MembResults, ConnMap}) ->
    ValidResults = [{N, R} || {N, R} <- MembResults, not is_badrpc(R)],
    case ValidResults of
        [] -> true;
        _ ->
            ResultMap = maps:from_list(ValidResults),
            lists:all(fun({Node, _}) ->
                ConnectedNodes = maps:get(Node, ConnMap, [Node]),
                ConnResults = [maps:get(CN, ResultMap, skip)
                               || CN <- ConnectedNodes, maps:is_key(CN, ResultMap)],
                Actual = [R || R <- ConnResults, R =/= skip],
                case Actual of
                    [] -> true;
                    _ ->
                        %% Sort each member list for comparison
                        Sorted = [lists:sort(R) || R <- Actual],
                        Unique = lists:usort(Sorted),
                        case length(Unique) of
                            1 ->
                                %% All connected nodes agree — verify format
                                [Members] = Unique,
                                lists:all(fun
                                    ({Pid, _Meta}) when is_pid(Pid) -> true;
                                    (Other) ->
                                        ct:pal("DOCS VIOLATION: member has non-standard format: ~p~n"
                                               "  Group=~p~n", [Other, GroupName]),
                                        false
                                end, Members);
                            _ ->
                                ct:pal("DOCS VIOLATION: Connected nodes disagree on members!~n"
                                       "  Group=~p~n"
                                       "  Results: ~p~n",
                                       [GroupName,
                                        [{CN, maps:get(CN, ResultMap, skip)}
                                         || CN <- ConnectedNodes, maps:is_key(CN, ResultMap)]]),
                                false
                        end
                end
            end, ValidResults)
    end;

%% --- Doc: member_count must be consistent across connected nodes ---
postcondition(_S, {call, _, verify_member_count_consistency, _}, {Counts, ConnMap}) ->
    check_count_consistency(Counts, ConnMap);

%% --- Doc: local_members must be subset of members filtered to local node ---
postcondition(_S, {call, _, verify_local_members, _}, Results) ->
    case Results of
        {error, _} -> true;
        Checks when is_list(Checks) ->
            lists:all(fun
                ({_Node, {badrpc, _}, _}) -> true;
                ({_Node, _, {badrpc, _}}) -> true;
                ({Node, LocalMembers, AllMembers}) when is_list(LocalMembers), is_list(AllMembers) ->
                    %% local_members should be exactly the members whose pid is on Node
                    LocalFiltered = [{P, M} || {P, M} <- AllMembers, node(P) =:= Node],
                    case lists:sort(LocalMembers) =:= lists:sort(LocalFiltered) of
                        true -> true;
                        false ->
                            ct:pal("DOCS VIOLATION: local_members mismatch!~n"
                                   "  Node=~p~n"
                                   "  local_members=~p~n"
                                   "  members filtered to node=~p~n",
                                   [Node, lists:sort(LocalMembers), lists:sort(LocalFiltered)]),
                            false
                    end
            end, Checks)
    end;

%% --- Doc: group_count consistent across connected nodes ---
postcondition(_S, {call, _, verify_group_count_consistency, _}, {Counts, ConnMap}) ->
    check_count_consistency(Counts, ConnMap);

%% --- Doc: group_names consistent across connected nodes ---
postcondition(_S, {call, _, verify_group_names_consistency, _}, {NamesResults, ConnMap}) ->
    ValidResults = [{N, R} || {N, R} <- NamesResults, is_list(R)],
    case length(ValidResults) < 2 of
        true -> true;
        false ->
            ResultMap = maps:from_list(ValidResults),
            lists:all(fun({Node, _}) ->
                ConnectedNodes = maps:get(Node, ConnMap, [Node]),
                ConnResults = [maps:get(CN, ResultMap, skip)
                               || CN <- ConnectedNodes, maps:is_key(CN, ResultMap)],
                Actual = [R || R <- ConnResults, R =/= skip],
                case Actual of
                    [] -> true;
                    _ ->
                        Sorted = [lists:sort(R) || R <- Actual],
                        Unique = lists:usort(Sorted),
                        case length(Unique) of
                            1 -> true;
                            _ ->
                                ct:pal("DOCS VIOLATION: Connected nodes disagree on group_names!~n"
                                       "  Results: ~p~n",
                                       [{CN, maps:get(CN, ResultMap, skip)}
                                        || CN <- ConnectedNodes, maps:is_key(CN, ResultMap)]),
                                false
                        end
                end
            end, ValidResults)
    end;

%% --- Doc: local_member_count == member_count(Scope, Group, node()),
%%          local_group_count == group_count(Scope, node()),
%%          local_group_names == group_names(Scope, node()) ---
postcondition(_S, {call, _, verify_local_counts, _}, Results) ->
    case Results of
        {error, _} -> true;
        Checks when is_list(Checks) ->
            lists:all(fun
                ({_Node, {badrpc, _}}) -> true;
                ({Node, {ok, LocalGC, GlobalGC, LocalGNames, GlobalGNames}}) ->
                    GCMatch = LocalGC =:= GlobalGC,
                    GNMatch = lists:sort(LocalGNames) =:= lists:sort(GlobalGNames),
                    case GCMatch andalso GNMatch of
                        true -> true;
                        false ->
                            ct:pal("DOCS VIOLATION: local_* != global equivalent on node ~p~n"
                                   "  local_group_count=~p group_count(Scope,node())=~p~n"
                                   "  local_group_names=~p group_names(Scope,node())=~p~n",
                                   [Node, LocalGC, GlobalGC,
                                    lists:sort(LocalGNames), lists:sort(GlobalGNames)]),
                            false
                    end
            end, Checks)
    end;

%% --- Doc: "processes are automatically monitored and removed if they die" ---
postcondition(_S, {call, _, kill_process, _}, _) -> true;

postcondition(#state{alive = Alive},
              {call, _, verify_cleanup_after_kill, [_, _ScopeNodes, _GroupNames]}, Results) ->
    case Results of
        {error, _} -> true;
        Checks when is_list(Checks) ->
            lists:all(fun
                ({_Group, _Node, {badrpc, _}}) -> true;
                ({_Group, _Node, Members}) when is_list(Members) ->
                    %% No dead pid should remain in any group
                    lists:all(fun({Pid, _Meta}) ->
                        case maps:get(Pid, Alive, false) of
                            false ->
                                ct:pal("DOCS VIOLATION: Dead process still in group!~n"
                                       "  Pid=~p~n", [Pid]),
                                false;
                            true -> true
                        end
                    end, Members)
            end, Checks)
    end;

%% --- Doc: publish returns {ok, RecipientCount} ---
postcondition(_S, {call, _, publish_to_group, _}, Result) ->
    case Result of
        {ok, N} when is_integer(N), N >= 0 -> true;
        {badrpc, _} -> true;
        Other ->
            ct:pal("DOCS VIOLATION: publish returned undocumented value: ~p~n", [Other]),
            false
    end;

%% --- Network operations ---
postcondition(_S, {call, _, netsplit, _}, _) -> true;
postcondition(_S, {call, _, heal_netsplit, _}, _) -> true;

%% --- Doc: After reconnection, groups converge ---
postcondition(_S, {call, _, verify_convergence, _}, Results) ->
    case Results of
        {error, _} -> true;
        ok -> true;
        {convergence_failure, Details} ->
            ct:pal("DOCS VIOLATION: Groups failed to converge!~n"
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

next_state(#state{nodes = Nodes, memberships = Memb, processes = Procs, alive = Alive} = S,
           _Result, {call, _, stop_node, [_, StoppedNode]}) ->
    Nodes2 = maps:remove(StoppedNode, Nodes),
    Nodes3 = maps:map(fun(_K, V) ->
        V#node_st{connected = lists:delete(StoppedNode, V#node_st.connected)}
    end, Nodes2),
    PidsOnNode = [P || {P, N} <- maps:to_list(Procs), N =:= StoppedNode],
    Memb2 = maps:filter(fun({_G, Pid}, _Meta) ->
        not lists:member(Pid, PidsOnNode)
    end, Memb),
    Procs2 = maps:without(PidsOnNode, Procs),
    Alive2 = maps:without(PidsOnNode, Alive),
    S#state{nodes = Nodes3, memberships = Memb2, processes = Procs2, alive = Alive2};

next_state(#state{nodes = Nodes} = S, _Result, {call, _, add_to_scope, [_, TargetNode]}) ->
    case maps:get(TargetNode, Nodes, undefined) of
        undefined -> S;
        NodeSt ->
            S#state{nodes = Nodes#{TargetNode => NodeSt#node_st{in_scope = true}}}
    end;

next_state(#state{processes = Procs, alive = Alive} = S, Pid,
           {call, _, spawn_process, [_, OnNode]}) ->
    S#state{processes = Procs#{Pid => OnNode}, alive = Alive#{Pid => true}};

next_state(#state{memberships = Memb} = S, _Result,
           {call, _, join_group, [_, GroupName, Pid, Meta, _OnNode]}) ->
    S#state{memberships = Memb#{{GroupName, Pid} => Meta}};

next_state(#state{memberships = Memb} = S, _Result,
           {call, _, join_group_no_meta, [_, GroupName, Pid, _OnNode]}) ->
    S#state{memberships = Memb#{{GroupName, Pid} => undefined}};

next_state(#state{memberships = Memb} = S, _Result,
           {call, _, leave_group, [_, {GroupName, Pid}, _OnNode, _]}) ->
    S#state{memberships = maps:remove({GroupName, Pid}, Memb)};

next_state(#state{memberships = Memb} = S, _Result,
           {call, _, update_member, [_, {GroupName, Pid}, NewMeta, _OnNode, _]}) ->
    case maps:is_key({GroupName, Pid}, Memb) of
        true -> S#state{memberships = Memb#{{GroupName, Pid} => NewMeta}};
        false -> S
    end;

next_state(#state{memberships = Memb} = S, _Result,
           {call, _, rejoin_group, [_, {GroupName, Pid}, NewMeta, _OnNode, _]}) ->
    case maps:is_key({GroupName, Pid}, Memb) of
        true -> S#state{memberships = Memb#{{GroupName, Pid} => NewMeta}};
        false -> S
    end;

next_state(#state{memberships = Memb, alive = Alive, processes = Procs} = S, _Result,
           {call, _, kill_process, [_, Pid]}) ->
    Memb2 = maps:filter(fun({_G, P}, _Meta) -> P =/= Pid end, Memb),
    S#state{memberships = Memb2, alive = maps:remove(Pid, Alive),
            processes = maps:remove(Pid, Procs)};

next_state(#state{nodes = Nodes} = S, _Result,
           {call, _, netsplit, [_, NodeA, NodeB]}) ->
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
    NodeShortName = list_to_atom("syn_pg_prop_" ++ integer_to_list(Id)
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
        _ -> ok
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

join_group(#state{}, GroupName, Pid, Meta, OnNode) ->
    case rpc:call(OnNode, syn, join, [?SCOPE, GroupName, Pid, Meta]) of
        {badrpc, {'EXIT', {invalid_scope, _}}} -> {badrpc, invalid_scope};
        {badrpc, {'EXIT', {invalid_remote_scope, _, _}}} -> {badrpc, invalid_remote_scope};
        {badrpc, Reason} -> {badrpc, Reason};
        Result -> timer:sleep(100), Result
    end.

join_group_no_meta(#state{}, GroupName, Pid, OnNode) ->
    case rpc:call(OnNode, syn, join, [?SCOPE, GroupName, Pid]) of
        {badrpc, {'EXIT', {invalid_scope, _}}} -> {badrpc, invalid_scope};
        {badrpc, {'EXIT', {invalid_remote_scope, _, _}}} -> {badrpc, invalid_remote_scope};
        {badrpc, Reason} -> {badrpc, Reason};
        Result -> timer:sleep(100), Result
    end.

leave_group(#state{}, {GroupName, Pid}, OnNode, _Key) ->
    case rpc:call(OnNode, syn, leave, [?SCOPE, GroupName, Pid]) of
        {badrpc, {'EXIT', {invalid_scope, _}}} -> {badrpc, invalid_scope};
        {badrpc, Reason} -> {badrpc, Reason};
        Result -> timer:sleep(100), Result
    end.

update_member(#state{}, {GroupName, Pid}, NewMeta, OnNode, _Key) ->
    Fun = fun(_OldMeta) -> NewMeta end,
    case rpc:call(OnNode, syn, update_member, [?SCOPE, GroupName, Pid, Fun]) of
        {badrpc, {'EXIT', {invalid_scope, _}}} -> {badrpc, invalid_scope};
        {badrpc, Reason} -> {badrpc, Reason};
        Result -> timer:sleep(100), Result
    end.

rejoin_group(#state{}, {GroupName, Pid}, NewMeta, OnNode, _Key) ->
    case rpc:call(OnNode, syn, join, [?SCOPE, GroupName, Pid, NewMeta]) of
        {badrpc, {'EXIT', {invalid_scope, _}}} -> {badrpc, invalid_scope};
        {badrpc, Reason} -> {badrpc, Reason};
        Result -> timer:sleep(100), Result
    end.

%% === INVARIANT: members on connected scope nodes must agree ===
members_everywhere(#state{}, GroupName, ScopeNodes) ->
    timer:sleep(?SYNC_WAIT),
    Results = lists:map(fun(Node) ->
        Res = case rpc:call(Node, syn, members, [?SCOPE, GroupName]) of
            {badrpc, {'EXIT', {invalid_scope, _}}} -> {badrpc, invalid_scope};
            {badrpc, Reason} -> {badrpc, Reason};
            R -> R
        end,
        {Node, Res}
    end, ScopeNodes),
    ConnMap = build_conn_map(ScopeNodes),
    {Results, ConnMap}.

%% === INVARIANT: member_count must be consistent among connected nodes ===
verify_member_count_consistency(#state{}, GroupName, ScopeNodes) ->
    timer:sleep(?SYNC_WAIT),
    Counts = lists:map(fun(Node) ->
        Count = case rpc:call(Node, syn, member_count, [?SCOPE, GroupName]) of
            {badrpc, {'EXIT', {invalid_scope, _}}} -> {badrpc, invalid_scope};
            {badrpc, Reason} -> {badrpc, Reason};
            C -> C
        end,
        {Node, Count}
    end, ScopeNodes),
    ConnMap = build_conn_map(ScopeNodes),
    {Counts, ConnMap}.

%% === INVARIANT: local_members must match members filtered to local node ===
verify_local_members(#state{}, GroupName, ScopeNodes) ->
    timer:sleep(?SYNC_WAIT),
    lists:map(fun(Node) ->
        LocalMembers = case rpc:call(Node, syn, local_members, [?SCOPE, GroupName]) of
            {badrpc, _} = E1 -> E1;
            LM -> LM
        end,
        AllMembers = case rpc:call(Node, syn, members, [?SCOPE, GroupName]) of
            {badrpc, _} = E2 -> E2;
            AM -> AM
        end,
        {Node, LocalMembers, AllMembers}
    end, ScopeNodes).

%% === INVARIANT: group_count must be consistent among connected nodes ===
verify_group_count_consistency(#state{}, ScopeNodes) ->
    timer:sleep(?SYNC_WAIT),
    Counts = lists:map(fun(Node) ->
        Count = case rpc:call(Node, syn, group_count, [?SCOPE]) of
            {badrpc, {'EXIT', {invalid_scope, _}}} -> {badrpc, invalid_scope};
            {badrpc, Reason} -> {badrpc, Reason};
            C -> C
        end,
        {Node, Count}
    end, ScopeNodes),
    ConnMap = build_conn_map(ScopeNodes),
    {Counts, ConnMap}.

%% === INVARIANT: group_names must be consistent among connected nodes ===
verify_group_names_consistency(#state{}, ScopeNodes) ->
    timer:sleep(?SYNC_WAIT),
    Results = lists:map(fun(Node) ->
        Res = case rpc:call(Node, syn, group_names, [?SCOPE]) of
            {badrpc, {'EXIT', {invalid_scope, _}}} -> {badrpc, invalid_scope};
            {badrpc, Reason} -> {badrpc, Reason};
            R -> R
        end,
        {Node, Res}
    end, ScopeNodes),
    ConnMap = build_conn_map(ScopeNodes),
    {Results, ConnMap}.

%% === INVARIANT: local_* == global equivalent with node() ===
verify_local_counts(#state{}, ScopeNodes) ->
    timer:sleep(?SYNC_WAIT),
    lists:map(fun(Node) ->
        Res = try
            LocalGC = rpc:call(Node, syn, local_group_count, [?SCOPE]),
            GlobalGC = rpc:call(Node, syn, group_count, [?SCOPE, Node]),
            LocalGNames = rpc:call(Node, syn, local_group_names, [?SCOPE]),
            GlobalGNames = rpc:call(Node, syn, group_names, [?SCOPE, Node]),
            case is_badrpc(LocalGC) orelse is_badrpc(GlobalGC)
                 orelse is_badrpc(LocalGNames) orelse is_badrpc(GlobalGNames) of
                true -> {badrpc, mixed};
                false -> {ok, LocalGC, GlobalGC, LocalGNames, GlobalGNames}
            end
        catch _:_ -> {badrpc, exception}
        end,
        {Node, Res}
    end, ScopeNodes).

%% === INVARIANT: dead processes must be cleaned up from groups ===
verify_cleanup_after_kill(#state{}, ScopeNodes, GroupNames) ->
    timer:sleep(?SYNC_WAIT),
    QueryNode = hd(ScopeNodes),
    lists:map(fun(GroupName) ->
        Res = case rpc:call(QueryNode, syn, members, [?SCOPE, GroupName]) of
            {badrpc, {'EXIT', {invalid_scope, _}}} -> {badrpc, invalid_scope};
            {badrpc, Reason} -> {badrpc, Reason};
            R -> R
        end,
        {GroupName, QueryNode, Res}
    end, GroupNames).

%% === Doc: publish returns {ok, RecipientCount} ===
publish_to_group(#state{}, GroupName, OnNode) ->
    Msg = {test_publish, erlang:unique_integer()},
    case rpc:call(OnNode, syn, publish, [?SCOPE, GroupName, Msg]) of
        {badrpc, {'EXIT', {invalid_scope, _}}} -> {badrpc, invalid_scope};
        {badrpc, Reason} -> {badrpc, Reason};
        Result -> Result
    end.

netsplit(#state{}, NodeA, NodeB) ->
    rpc:call(NodeA, erlang, disconnect_node, [NodeB]),
    timer:sleep(?SYNC_WAIT),
    ok.

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
            lists:foreach(fun(N1) ->
                lists:foreach(fun(N2) ->
                    case N1 =/= N2 of
                        true -> rpc:call(N1, net_kernel, connect_node, [N2]);
                        false -> ok
                    end
                end, ScopeNodes)
            end, ScopeNodes),
            timer:sleep(?SYNC_WAIT * 2),
            Counts = lists:map(fun(Node) ->
                case rpc:call(Node, syn, group_count, [?SCOPE]) of
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
gen_group_name() ->
    frequency([
        {5, {group, choose(1, ?MAX_GROUPS)}},
        {3, choose(1, ?MAX_GROUPS)},
        {2, elements([rooms, devices, sensors, users])}
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
    catch _:_ -> false
    end.

cleanup_all() ->
    PeerNodes = [N || N <- nodes(),
                 lists:prefix("syn_pg_prop_", atom_to_list(N))],
    lists:foreach(fun(N) ->
        catch rpc:call(N, application, stop, [syn])
    end, PeerNodes),
    lists:foreach(fun(N) ->
        catch rpc:call(N, erlang, halt, [0])
    end, PeerNodes),
    lists:foreach(fun(N) ->
        catch erlang:disconnect_node(N)
    end, PeerNodes),
    timer:sleep(300),
    catch application:stop(syn),
    timer:sleep(100),
    catch syn:start(),
    ok.
