%% ==========================================================================================================
%% Syn - A global Process Registry and Process Group manager.
%%
%% The MIT License (MIT)
%%
%% Copyright (c) 2015-2026 Roberto Ostinelli <roberto@ostinelli.net> and Neato Robotics, Inc.
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
%% Tests that drive the registry through specific message orders: a sender process that sends one message per step,
%% callbacks that block until the test lets them go, and messages injected as if a peer had sent them. Each test
%% checks that the nodes still end up agreeing, or that a call returns what it promises.
-module(syn_protocol_SUITE).
-export([all/0, suite/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% tests
-export([
    conflict_normal/1,
    conflict_second_split/1,
    conflict_skew/1,
    conflict_refresh_livelock/1,
    conflict_tie/1,
    discovery_incarnation_registry/1,
    discovery_incarnation_pg/1,
    ordered_update_withdraw/1,
    scope_update_withdraw/1,
    local_update_withdraw/1,
    late_down_after_resync/1,
    snapshot_aside_and_fences/1,
    restart_claims/1,
    killed_alias_exit_reason/1,
    ordered_adoption_fetches_snapshot/1,
    late_old_incarnation_recovers/1,
    disconnected_handshakes_ignored/1,
    killed_process_loses_both_names/1,
    unchanged_pairs_not_resolved/1,
    monitor_does_not_reconnect/1,
    messages_from_another_version_ignored/1
]).

%% run on other nodes, or by Syn as callbacks
-export([idle/0, hold/2, set_owner_time/2]).
-export([install_stepped_sender/0, stepped_sender/0, restore_sender/0]).
-export([on_process_registered/5, on_process_unregistered/5]).
-export([on_registry_process_updated/5, on_registry_process_updated/6]).
-export([resolve_registry_conflict/4]).
-include_lib("syn/src/syn.hrl").

all() -> [conflict_normal, conflict_second_split, conflict_skew, conflict_refresh_livelock, conflict_tie,
          discovery_incarnation_registry, discovery_incarnation_pg,
          ordered_update_withdraw, scope_update_withdraw, local_update_withdraw,
          late_down_after_resync, snapshot_aside_and_fences, restart_claims,
          killed_alias_exit_reason, ordered_adoption_fetches_snapshot,
          late_old_incarnation_recovers, disconnected_handshakes_ignored,
          killed_process_loses_both_names, unchanged_pairs_not_resolved, monitor_does_not_reconnect,
          messages_from_another_version_ignored].
suite() -> [{timetrap, {seconds, 30}}].

init_per_suite(Config) ->
    application:set_env(kernel, prevent_overlapping_partitions, false),
    Peers = [begin
        {ok, Peer, Node} = peer:start(#{name => Name, connection => 0,
            args => ["+S", "2", "-connect_all", "false", "-kernel",
                     "dist_auto_connect", "never", "prevent_overlapping_partitions", "false"]}),
        ok = rpc:call(Node, code, add_pathsa, [code:get_path()]),
        {Peer, Node}
    end || Name <- [syn_protocol_a, syn_protocol_b]],
    [{peers, Peers} | Config].
end_per_suite(Config) ->
    [peer:stop(Peer) || {Peer, _} <- proplists:get_value(peers, Config)], ok.
init_per_testcase(_, Config) ->
    [{_, A}, {_, B}] = proplists:get_value(peers, Config),
    true = rpc:call(A, net_kernel, connect_node, [B]),
    [begin
        ok = rpc:call(N, syn, start, []),
        ok = rpc:call(N, syn, add_node_to_scopes, [[protocol]])
    end || N <- [node(), A, B]],
    [wait(fun() -> lists:sort(rpc:call(N, syn_registry, subcluster_nodes, [protocol]))
                   =:= lists:sort([node(), A, B] -- [N]) end) || N <- [node(), A, B]],
    [{a, A}, {b, B} | Config].
end_per_testcase(_, Config) ->
    [net_kernel:connect_node(N) || {_, N} <- proplists:get_value(peers, Config)],
    [begin
        rpc:call(N, application, stop, [syn]),
        rpc:call(N, application, unset_env, [syn, event_handler]),
        rpc:call(N, application, unset_env, [syn, protocol_gate]),
        rpc:call(N, application, unset_env, [syn, protocol_observer]),
        rpc:call(N, application, unset_env, [syn, protocol_purge_gate])
    end || N <- [node(), proplists:get_value(a, Config), proplists:get_value(b, Config)]], ok.

wait(Fun) -> wait(Fun, 500).
wait(Fun, 0) -> ct:fail({wait_failed, Fun()});
wait(Fun, N) -> case catch Fun() of true -> ok; _ -> timer:sleep(10), wait(Fun, N-1) end.
idle() -> receive stop -> ok end.
pid(N) -> rpc:call(N, erlang, spawn, [?MODULE, idle, []]).
scope(N, Handler) -> rpc:call(N, erlang, whereis, [list_to_atom(atom_to_list(Handler) ++ "_protocol")]).
view(N) -> rpc:call(N, syn, lookup, [protocol, x]).
split(A, B) ->
    rpc:call(A, erlang, disconnect_node, [B]),
    rpc:call(B, erlang, disconnect_node, [A]),
    wait(fun() -> rpc:call(A, syn_registry, subcluster_nodes, [protocol]) =:= [node()]
          andalso rpc:call(B, syn_registry, subcluster_nodes, [protocol]) =:= [node()] end).
sender(N, Handler) -> (sys:get_state(scope(N, Handler)))#state.sender_pid.
pause_sender(N, Handler) ->
    Sender = sender(N, Handler),
    Pauser = rpc:call(N, erlang, spawn, [?MODULE, hold, [Sender, self()]]),
    receive {paused, Pauser} -> Pauser after 5000 -> error(pause_timeout) end.
hold(Pid, Test) ->
    true = erlang:suspend_process(Pid), Test ! {paused, self()},
    receive resume -> erlang:resume_process(Pid) after 20000 -> ok end.
resume_sender(_N, Pauser) -> Pauser ! resume, ok.
messages(Pid) -> {messages, Messages} = rpc:call(node(Pid), erlang, process_info, [Pid, messages]), Messages.
%% pretends that the clock of the node running P is ahead: changes the time of its registration and sends it to the
%% other nodes as that node would
set_owner_time(P, Time) ->
    sys:replace_state(scope(node(), syn_registry), fun(S) ->
        [{x, P, Meta, _, Ref, _}] = ets:lookup(S#state.table_by_name, x),
        syn_registry:add_to_local_table(x, P, Meta, Time, Ref, S#state.table_by_name, S#state.table_by_pid),
        syn_gen_scope:broadcast({'3.5', sync_register, self(), x, P, Meta, Time, normal}, S), S
    end), ok.
future() -> erlang:system_time() + erlang:convert_time_unit(3600, second, native).
resolve_registry_conflict(_Scope, Name, {P1, M1, _}, {P2, M2, _}) ->
    report({resolved, node(), Name, P1, P2}),
    case application:get_env(syn, protocol_gate) of
        {ok, Test} ->
            application:unset_env(syn, protocol_gate),
            Test ! {resolver_blocked, self()},
            receive protocol_continue -> ok after 10000 -> error(gate_timeout) end;
        undefined -> ok
    end,
    case M1 < M2 of true -> P1; false -> P2 end.
%% issue #96 without anything going wrong: the owners resolve, the winner neither refreshes its time nor announces
%% itself again, and every node ends up with the winner
conflict_normal(Config) -> conflict(Config, false).
%% issue #96 with the loser's clock ahead: the bystander shows the winner once the loser drops its own
conflict_skew(Config) -> conflict(Config, true).
conflict(Config, Skew) ->
    A = proplists:get_value(a, Config), B = proplists:get_value(b, Config),
    [rpc:call(N, syn, set_event_handler, [?MODULE]) || N <- [node(), A, B]],
    PA = pid(A), PB = pid(B),
    ok = rpc:call(A, syn, register, [protocol, x, PA, 1]),
    wait(fun() -> view(B) =:= {PA, 1} andalso view(node()) =:= {PA, 1} end),
    split(A, B),
    ok = rpc:call(B, syn, register, [protocol, x, PB, 2]),
    wait(fun() -> view(node()) =:= {PB, 2} end),
    case Skew of
        true -> ok = rpc:call(B, ?MODULE, set_owner_time, [PB, future()]),
                wait(fun() -> S = sys:get_state(scope(node(), syn_registry)),
                    [{x, PB, _, T, _, _}] = ets:lookup(S#state.table_by_name, x),
                    T > erlang:system_time() end);
        false -> ok
    end,
    %% B has sent its snapshot before its resolver runs. The resolver of B waits until the test lets it go, so that A
    %% handles that snapshot, keeps its process and sends nothing, before B drops its own.
    ok = rpc:call(B, application, set_env, [syn, protocol_gate, self()]),
    OldTime = owner_time(A),
    true = rpc:call(A, net_kernel, connect_node, [B]),
    Blocked = receive {resolver_blocked, SP} -> SP after 5000 -> ct:fail(no_conflict) end,
    %% A keeps its process without giving it a new time or telling the other nodes again
    _ = sys:get_state(scope(A, syn_registry)),
    OldTime = owner_time(A),
    Blocked ! protocol_continue,
    wait(fun() -> lists:all(fun(N) -> view(N) =:= {PA, 1} end, [node(), A, B]) end),
    quiescent([node(), A, B]),
    OldTime = owner_time(A),
    ct:pal("Skew=~p, converged A/B/Common: ~p", [Skew, [view(N) || N <- [A,B,node()]]]).
owner_time(N) ->
    S = sys:get_state(scope(N, syn_registry)),
    [{x, _, _, T, _, _}] = rpc:call(N, ets, lookup, [S#state.table_by_name, x]), T.

%% a sender that sends its next message only when the test says so, to the same nodes and in the same order as the
%% real one would
install_stepped_sender() ->
    S = sys:replace_state(scope(node(), syn_registry), fun(State) ->
        State#state.sender_pid ! terminate,
        State#state{sender_pid = spawn_link(?MODULE, stepped_sender, [])}
    end), S#state.sender_pid.
stepped_sender() ->
    receive
        {step, Test, Ref} ->
            receive
                {broadcast, Message, Excluded, Name, Nodes} ->
                    [erlang:send({Name, N}, Message, [noconnect]) || N <- Nodes -- Excluded];
                {send_single, N, Message, Name} -> erlang:send({Name, N}, Message, [noconnect])
            end,
            Test ! {stepped, Ref}, stepped_sender();
        {sync, Test, Ref, Nodes} ->
            [sys:get_state({syn_registry_protocol, N}) || N <- Nodes],
            Test ! {synced, Ref}, stepped_sender();
        terminate -> ok
    end.
restore_sender() ->
    sys:replace_state(scope(node(), syn_registry), fun(S) ->
        S#state.sender_pid ! terminate,
        S#state{sender_pid = spawn_link(syn_gen_scope, sender_loop, [])}
    end), ok.
step(Sender) ->
    Ref = make_ref(), Sender ! {step, self(), Ref},
    receive {stepped, Ref} -> ok after 3000 -> error(step_timeout) end.
%% issue #96 as seen on a cluster: the loser's snapshot never reaches the winner, as the connection drops again, and
%% the bystander still ends up with the winner
conflict_second_split(Config) ->
    A = proplists:get_value(a, Config), B = proplists:get_value(b, Config),
    [rpc:call(N, syn, set_event_handler, [?MODULE]) || N <- [node(), A, B]],
    PA = pid(A), PB = pid(B),
    ok = rpc:call(A, syn, register, [protocol, x, PA, 1]),
    wait(fun() -> view(B) =:= {PA, 1} andalso view(node()) =:= {PA, 1} end),
    split(A, B),
    ok = rpc:call(B, syn, register, [protocol, x, PB, 2]),
    wait(fun() -> view(node()) =:= {PB, 2} end),
    SB = rpc:call(B, ?MODULE, install_stepped_sender, []),
    true = rpc:call(A, net_kernel, connect_node, [B]),
    %% B's answer to the discover of A waits in B's sender, while B gets the snapshot of A
    wait(fun() -> length(messages(SB)) =:= 2 end),
    step(SB),
    wait(fun() -> view(B) =:= {PA, 1} end),
    %% B has already dropped its process, but its snapshot hasn't reached A: a second cut loses it. Common stays connected
    %% to both
    split(A, B),
    step(SB), step(SB),
    wait(fun() -> view(node()) =:= {PA, 1} end),
    ok = rpc:call(B, ?MODULE, restore_sender, []),
    true = rpc:call(A, net_kernel, connect_node, [B]),
    wait(fun() -> lists:sort(rpc:call(B, syn_registry, subcluster_nodes, [protocol]))
                  =:= lists:sort([node(), A]) andalso view(B) =:= {PA, 1} end),
    wait(fun() -> lists:all(fun(N) -> messages(scope(N, syn_registry)) =:= []
                    andalso messages(sender(N, syn_registry)) =:= [] end, [node(), A, B]) end),
    {PA, 1} = view(A), {PA, 1} = view(B), {PA, 1} = view(node()),
    ct:pal("Second split, no clock skew, A/B/Common: ~p", [[view(N) || N <- [A,B,node()]]]).
%% both owners update their registration while their snapshots are on the way: the conflict still ends, after a
%% bounded number of messages, and nobody refreshes its time
conflict_refresh_livelock(Config) ->
    A = proplists:get_value(a, Config), B = proplists:get_value(b, Config),
    split(A, B), PA = pid(A), PB = pid(B),
    ok = rpc:call(A, syn, register, [protocol, x, PA, initial_a]),
    ok = rpc:call(B, syn, register, [protocol, x, PB, initial_b]),
    wait(fun() -> messages(sender(A, syn_registry)) =:= []
          andalso messages(sender(B, syn_registry)) =:= [] end),
    SA = rpc:call(A, ?MODULE, install_stepped_sender, []),
    SB = rpc:call(B, ?MODULE, install_stepped_sender, []),
    true = rpc:call(A, net_kernel, connect_node, [B]),
    step(SA), step(SB),
    wait(fun() -> lists:any(fun(M) -> element(1,M) =:= send_single andalso
        element(2,element(3,M)) =:= ack_sync end, messages(SA)) andalso
        lists:any(fun(M) -> element(1,M) =:= send_single andalso
        element(2,element(3,M)) =:= ack_sync end, messages(SB)) end),
    %% both snapshots wait in the senders, and both nodes update their registration before getting the other's
    ok = rpc:call(A, syn, register, [protocol, x, PA, updated_a]),
    ok = rpc:call(B, syn, register, [protocol, x, PB, updated_b]),
    TimeA = owner_time(A), TimeB = owner_time(B),
    %% both nodes get the other's older snapshot first, and keep their own without giving it a new time
    step(SA), step(SB),
    _ = sys:get_state(scope(A, syn_registry)), _ = sys:get_state(scope(B, syn_registry)),
    TimeA = owner_time(A), TimeB = owner_time(B),
    Deliveries = pump([SA, SB], [node(), A, B], 0, 60),
    Expected = case TimeA > TimeB of true -> {PA, updated_a}; false -> {PB, updated_b} end,
    wait(fun() -> lists:all(fun(N) -> view(N) =:= Expected end, [node(), A, B]) end),
    ct:pal("Converged after ~p further FIFO sender instructions, no timestamp refresh", [Deliveries]),
    [] = messages(SA), [] = messages(SB), ok.

%% both owners register the name with the same metadata while apart, and this suite's resolver keeps the second
%% registration it gets on a tie: both nodes pass the two in the same order, so they keep the same process
conflict_tie(Config) ->
    A = proplists:get_value(a, Config), B = proplists:get_value(b, Config),
    [rpc:call(N, syn, set_event_handler, [?MODULE]) || N <- [node(), A, B]],
    split(A, B), PA = pid(A), PB = pid(B),
    ok = rpc:call(A, syn, register, [protocol, x, PA, same]),
    ok = rpc:call(B, syn, register, [protocol, x, PB, same]),
    true = rpc:call(A, net_kernel, connect_node, [B]),
    %% the registration of the node whose name sorts last comes second
    Kept = case A < B of true -> PB; false -> PA end,
    wait(fun() -> lists:all(fun(N) -> view(N) =:= {Kept, same} end, [node(), A, B]) end),
    quiescent([node(), A, B]),
    {Kept, same} = view(A), {Kept, same} = view(B), {Kept, same} = view(node()).

%% a new scope process' handshake arrives before the old one's DOWN, which Erlang allows: the messages are injected to
%% get this order every time. The node keeps the new one, then finds the live peer again
discovery_incarnation_registry(Config) -> incarnation(Config, syn_registry).
discovery_incarnation_pg(Config) -> incarnation(Config, syn_pg).
incarnation(Config, Handler) ->
    A = proplists:get_value(a, Config), Local = scope(node(), Handler), Old = scope(A, Handler),
    {Old, OldRef} = maps:get(A, (sys:get_state(Local))#state.nodes_map),
    Held = pause_sender(A, Handler), FakeNew = pid(A),
    Local ! {'3.5', discover, FakeNew},
    Local ! {'3.5', ack_sync, FakeNew, []},
    Local ! {'DOWN', OldRef, process, Old, killed},
    S = sys:get_state(Local),
    {FakeNew, _} = maps:get(A, S#state.nodes_map),
    exit(FakeNew, kill),
    resume_sender(A, Held),
    wait(fun() -> case maps:get(A, (sys:get_state(Local))#state.nodes_map, undefined) of
        {Old, _} -> true; _ -> false end end),
    ct:pal("~p retained the new pid on old DOWN, then rediscovered the live peer", [Handler]).

quiescent(Ns) ->
    [sys:get_state(scope(N, syn_registry)) || N <- Ns],
    wait(fun() -> lists:all(fun(N) -> messages(scope(N, syn_registry)) =:= []
        andalso messages(sender(N, syn_registry)) =:= [] end, Ns) end).
%% steps the stepped senders until they have nothing left to send, even once the scope processes of Nodes have handled
%% everything the senders sent them; returns how many messages were sent, and fails past Max
pump(Senders, Nodes, Count, Max) ->
    case [S || S <- Senders, messages(S) =/= []] of
        [] ->
            [sync(S, Nodes) || S <- Senders],
            case [S || S <- Senders, messages(S) =/= []] of
                [] -> Count;
                _ -> pump(Senders, Nodes, Count, Max)
            end;

        _ when Count >= Max ->
            ct:fail({traffic_did_not_stop, Count});

        Ready ->
            [step(S) || S <- Ready],
            pump(Senders, Nodes, Count + length(Ready), Max)
    end.

%% returns once the scope processes of Nodes have handled everything Sender sent them: the sender asks each of them,
%% and its questions arrive after its messages
sync(Sender, Nodes) ->
    Ref = make_ref(), Sender ! {sync, self(), Ref, Nodes},
    receive {synced, Ref} -> ok after 5000 -> error(sync_timeout) end.
report(Event) ->
    case application:get_env(syn, protocol_observer) of
        {ok, Test} -> Test ! Event;
        _ -> ok
    end.
on_process_registered(Scope, Name, Pid, Meta, Reason) ->
    report({registered, node(), Scope, Name, Pid, Meta, Reason}).
on_process_unregistered(Scope, Name, Pid, Meta, Reason) ->
    report({unregistered, node(), Scope, Name, Pid, Meta, Reason}),
    case application:get_env(syn, protocol_purge_gate) of
        {ok, Test} ->
            application:unset_env(syn, protocol_purge_gate),
            Test ! {purge_blocked, self()},
            receive protocol_continue -> ok after 10000 -> error(gate_timeout) end;
        _ -> ok
    end.
on_registry_process_updated(Scope, Name, Pid, Meta, Reason) ->
    report({updated5, node(), Scope, Name, Pid, Meta, Reason}).
on_registry_process_updated(Scope, Name, Pid, OldMeta, Meta, Reason) ->
    report({updated6, node(), Scope, Name, Pid, OldMeta, Meta, Reason}).
collect() -> receive M -> [M | collect()] after 0 -> [] end.

%% an update that makes the owner lose its conflict: the caller's node gets the result before the withdrawal, for a
%% call from another node, for a call from a scope process, and for a call on the owner's node
ordered_update_withdraw(C) -> update_withdraw(C, applied).
scope_update_withdraw(C) -> update_withdraw(C, handled).
local_update_withdraw(C) -> update_withdraw(C, local).
update_withdraw(Config, Kind) ->
    A = proplists:get_value(a, Config), B = proplists:get_value(b, Config),
    [rpc:call(N, syn, set_event_handler, [?MODULE]) || N <- [node(), A, B]],
    PA = pid(A), PB = pid(B),
    ok = rpc:call(A, syn, register, [protocol, x, PA, 1]),
    wait(fun() -> view(node()) =:= {PA, 1} end),
    %% A has the registration of B and keeps its own, while B doesn't know about the one of A yet
    ScopeB = scope(B, syn_registry), ScopeA = scope(A, syn_registry),
    ScopeA ! {'3.5', sync_register, ScopeB, x, PB, 2, 0, normal},
    scope(node(), syn_registry) ! {'3.5', sync_register, ScopeB, x, PB, 2, 0, normal},
    _ = sys:get_state(scope(node(), syn_registry)),
    _ = sys:get_state(ScopeA),
    S = rpc:call(A, ?MODULE, install_stepped_sender, []),
    rpc:call(A, application, set_env, [syn, protocol_observer, self()]),
    Test = self(),
    Call = fun() -> syn:update_registry(protocol, x, fun(_, _) -> 3 end) end,
    case Kind of
        applied -> spawn(fun() -> Test ! {update_result, Call()} end);
        handled -> sys:replace_state(scope(node(), syn_registry), fun(St) ->
            Test ! {update_result, Call()}, St end);
        local -> Test ! {update_result, rpc:call(A, syn, update_registry, [protocol, x, fun(_, _) -> 3 end])}
    end,
    ExpectedCount = case Kind of local -> 2; _ -> 3 end,
    wait(fun() -> length(messages(S)) =:= ExpectedCount end),
    Instructions = messages(S),
    Types = [case I of {broadcast, M, _, _, _} -> element(2, M);
                      {send_single, _, M, _} -> element(2, M) end || I <- Instructions],
    ExpectedTypes = case Kind of local -> [sync_register, sync_unregister];
        _ -> [sync_register, sync_register_reply, sync_unregister] end,
    ExpectedTypes = Types,
    [step(S) || _ <- Instructions],
    receive {update_result, Result} -> {ok, {PA, 3}} = Result after 5000 -> ct:fail(no_result) end,
    wait(fun() -> view(node()) =:= {PB, 2} end),
    Events = collect(),
    Update5 = {updated5, A, protocol, x, PA, 3, normal},
    Update6 = {updated6, A, protocol, x, PA, 1, 3, normal},
    Unregister = {unregistered, A, protocol, x, PA, 3, syn_conflict_resolution},
    Relevant = [E || E <- Events, lists:member(element(1, E), [updated5, updated6, unregistered])],
    [Update5, Update6, Unregister] = Relevant,
    ct:pal("~p result queued before withdrawal; both update arities precede conflict unregister", [Kind]).

%% a DOWN that arrives after the peer's snapshot: the node drops the peer, sees it's still connected, and asks again
late_down_after_resync(Config) ->
    A = proplists:get_value(a, Config), P = pid(A),
    ok = syn:register(protocol, x, P, meta),
    Local = scope(node(), syn_registry), Remote = scope(A, syn_registry),
    {Remote, Ref} = maps:get(A, (sys:get_state(Local))#state.nodes_map),
    {ok, Data} = rpc:call(A, syn_registry, get_local_data, [sys:get_state(Remote)]),
    Local ! {'3.5', ack_sync, Remote, Data},
    Local ! {'DOWN', Ref, process, Remote, noconnection},
    wait(fun() -> S = sys:get_state(Local),
        case maps:get(A, S#state.nodes_map, undefined) of
            {Remote, NewRef} when NewRef =/= Ref -> view(node()) =:= {P, meta};
            _ -> false
        end end),
    ct:pal("Late noconnection after snapshot purged and rediscovered current peer").

%% snapshots replace what a node had from a peer, registrations set aside come and go with them, and messages from
%% a scope process the node doesn't know are ignored, in the registry and in process groups
snapshot_aside_and_fences(Config) ->
    A = proplists:get_value(a, Config), B = proplists:get_value(b, Config),
    PA = pid(A), PA2 = pid(A), PB = pid(B),
    SA = scope(A, syn_registry), SB = scope(B, syn_registry), Local = scope(node(), syn_registry),
    Local ! {'3.5', ack_sync, SA, [{x, PA, old, 50}]},
    Local ! {'3.5', ack_sync, SB, [{x, PB, b, 100}]},
    Local ! {'3.5', ack_sync, SA, [{x, PA2, new, 10}]},
    _ = sys:get_state(Local),
    [{x, A, PA2, new, 10}] = read_aside(Local),
    {PB, b} = view(node()),
    Local ! {'3.5', ack_sync, SB, []},
    _ = sys:get_state(Local),
    {PA2, new} = view(node()), [] = read_aside(Local),
    Fake = pid(A),
    Local ! {'3.5', sync_register, Fake, x, PA, stale, 200, normal},
    Local ! {'3.5', sync_unregister, Fake, x, PA2, new, normal},
    Local ! {'3.5', sync_register_reply, Fake, x, PA, stale, 200, undefined},
    Local ! {'3.5', sync_unregister_reply, Fake, x, PA2, new, undefined},
    _ = sys:get_state(Local), {PA2, new} = view(node()),
    Local ! {'3.5', ack_sync, SA, []},
    _ = sys:get_state(Local), undefined = view(node()), [] = read_aside(Local),
    %% process groups ignore messages from a scope process they don't know in the same way
    PG = scope(node(), syn_pg), PGA = scope(A, syn_pg),
    PG ! {'3.5', ack_sync, PGA, [{g, PA, meta, 10}]},
    PG ! {'3.5', sync_join, Fake, g, PA, stale, 200, normal},
    PG ! {'3.5', sync_leave, Fake, g, PA, meta, normal},
    PG ! {'3.5', sync_join_reply, Fake, g, PA, stale, 200, undefined},
    PG ! {'3.5', sync_leave_reply, Fake, g, PA, meta, undefined},
    _ = sys:get_state(PG), [{PA, meta}] = syn:members(protocol, g).
read_aside(Local) ->
    S = sys:replace_state(Local, fun(St) ->
        put(protocol_aside, ets:tab2list(maps:get(aside, St#state.handler_state))), St end),
    {dictionary, D} = rpc:call(node(Local), erlang, process_info, [Local, dictionary]),
    true = is_map(S#state.handler_state), proplists:get_value(protocol_aside, D).

%% a scope process restart forgets the registrations set aside, keeps the node's own ones, and watches their
%% processes once each
restart_claims(Config) ->
    A = proplists:get_value(a, Config), Local = scope(node(), syn_registry), P = pid(node()), Q = pid(A),
    syn:set_event_handler(?MODULE),
    ok = syn:register(protocol, x, P, 1), ok = syn:register(protocol, y, P, 1),
    Remote = scope(A, syn_registry),
    Local ! {'3.5', sync_register, Remote, x, Q, 2, 0, normal},
    _ = sys:get_state(Local), [_] = read_aside(Local),
    OldAside = maps:get(aside, (sys:get_state(Local))#state.handler_state),
    exit(Local, kill),
    wait(fun() -> case scope(node(), syn_registry) of New0 when is_pid(New0) -> New0 =/= Local; _ -> false end end),
    New = scope(node(), syn_registry),
    _ = sys:get_state(New), undefined = ets:info(OldAside),
    [] = read_aside(New), {P, 1} = view(node()), {P, 1} = syn:lookup(protocol, y),
    {monitors, Mons} = process_info(New, monitors),
    1 = length([ok || {process, MP} <- Mons, MP =:= P]),
    exit(P, kill),
    wait(fun() -> syn:lookup(protocol, x) =:= undefined andalso syn:lookup(protocol, y) =:= undefined
        andalso syn:registry_count(protocol) =:= 0 end),
    ct:pal("Restart discarded aside, retained own aliases, rebuilt one monitor, and cleaned both on death").

%% one snapshot brings newer registrations for both names of a process: it loses both conflicts, so both names go with
%% syn_conflict_resolution, even though the first one already killed it
killed_process_loses_both_names(Config) ->
    A = proplists:get_value(a, Config), P = pid(node()), Q = pid(A),
    syn:set_event_handler(syn_test_event_handler_protocol),
    application:set_env(syn, protocol_observer, self()),
    ok = syn:register(protocol, x, P, local), ok = syn:register(protocol, y, P, local), collect(),
    Local = scope(node(), syn_registry), Remote = scope(A, syn_registry),
    Local ! {'3.5', ack_sync, Remote, [{x, Q, remote, future()}, {y, Q, remote, future()}]},
    _ = sys:get_state(Local),
    Events = collect(),
    Reasons = [{Name, Reason} || {unregistered, _, protocol, Name, LP, _, Reason} <- Events, LP =:= P],
    ct:pal("Local alias unregister reasons: ~p", [Reasons]),
    [{x, syn_conflict_resolution}, {y, syn_conflict_resolution}] = Reasons.

%% the resolver runs again only for a registration that changed
unchanged_pairs_not_resolved(Config) ->
    A = proplists:get_value(a, Config), B = proplists:get_value(b, Config),
    P = pid(node()), Q = pid(A), R = pid(B),
    syn:set_event_handler(?MODULE), application:set_env(syn, protocol_observer, self()),
    ok = syn:register(protocol, x, P, 0), collect(),
    Local = scope(node(), syn_registry), SA = scope(A, syn_registry), SB = scope(B, syn_registry),
    Local ! {'3.5', sync_register, SA, x, Q, 1, 10, normal},
    _ = sys:get_state(Local), [_] = [E || E = {resolved, _, _, _, _} <- collect()],
    Local ! {'3.5', sync_register, SB, x, R, 2, 20, normal},
    _ = sys:get_state(Local),
    NewPairCalls = [E || E = {resolved, _, _, _, _} <- collect()],
    Local ! {'3.5', ack_sync, SA, [{x, Q, 1, 10}]},
    _ = sys:get_state(Local),
    DuplicateCalls = [E || E = {resolved, _, _, _, _} <- collect()],
    ct:pal("Adding B called resolver ~p times; identical A snapshot called it ~p times", [length(NewPairCalls), length(DuplicateCalls)]),
    {1, 0} = {length(NewPairCalls), length(DuplicateCalls)}.

%% the connection drops while a node is busy with a new peer scope process: the node doesn't connect them again
monitor_does_not_reconnect(Config) ->
    A = proplists:get_value(a, Config), B = proplists:get_value(b, Config),
    P = pid(A), Fake = pid(A),
    ok = syn:register(protocol, x, P, meta),
    syn:set_event_handler(syn_test_event_handler_protocol),
    application:set_env(syn, protocol_purge_gate, self()),
    Local = scope(node(), syn_registry),
    Local ! {'3.5', discover, Fake},
    receive {purge_blocked, Local} -> ok after 5000 -> ct:fail(no_purge) end,
    %% cut the connection through B, so that this node doesn't talk to A again after it
    rpc:call(B, rpc, call, [A, erlang, disconnect_node, [node()]]),
    erlang:disconnect_node(A),
    false = lists:member(A, nodes()),
    Local ! protocol_continue,
    _ = sys:get_state(Local),
    timer:sleep(200),
    Connected = lists:member(A, nodes()),
    ct:pal("Connection after adopting the new pid across a disconnect: ~p", [Connected]),
    false = Connected.

%% a process loses a conflict for one of its names and is killed: its other name goes with its exit reason
killed_alias_exit_reason(Config) ->
    A = proplists:get_value(a, Config), P = pid(node()), Q = pid(A),
    syn:set_event_handler(syn_test_event_handler_protocol), application:set_env(syn, protocol_observer, self()),
    ok = syn:register(protocol, x, P, local), ok = syn:register(protocol, y, P, local), collect(),
    Local = scope(node(), syn_registry), Remote = scope(A, syn_registry),
    Local ! {'3.5', ack_sync, Remote, [{x, Q, remote, future()}]},
    receive {unregistered, _, protocol, y, P, local, Reason} ->
        {syn_resolve_kill, x, local} = Reason
    after 5000 -> ct:fail(missing_alias_down) end,
    _ = sys:get_state(Local), undefined = syn:lookup(protocol, y),
    {Q, remote} = syn:lookup(protocol, x).

%% a node learns of a scope process through a call from it: it sends its data and asks for that node's
ordered_adoption_fetches_snapshot(Config) ->
    A = proplists:get_value(a, Config), P = pid(node()), Q = pid(A),
    ok = syn:register(protocol, owned_here, P, local),
    wait(fun() -> rpc:call(A, syn, lookup, [protocol, owned_here]) =:= {P, local} end),
    LocalNode = node(), Remote = scope(A, syn_registry),
    sys:replace_state(Remote, fun(S) ->
        {_, Ref} = maps:get(LocalNode, S#state.nodes_map), erlang:demonitor(Ref, [flush]),
        syn_registry:purge_local_data_for_node(LocalNode, S),
        S#state{nodes_map = maps:remove(LocalNode, S#state.nodes_map),
                asked = lists:delete(LocalNode, S#state.asked)}
    end),
    undefined = rpc:call(A, syn, lookup, [protocol, owned_here]),
    ok = syn:register(protocol, owned_there, Q, remote),
    wait(fun() -> rpc:call(A, syn, lookup, [protocol, owned_here]) =:= {P, local} end),
    {Q, remote} = syn:lookup(protocol, owned_there).

%% a late handshake from a scope process that has restarted since: the node ends up with the live one
late_old_incarnation_recovers(Config) ->
    A = proplists:get_value(a, Config), P = pid(A),
    ok = syn:register(protocol, x, P, meta),
    [begin
        Local = scope(node(), Handler), Old = scope(A, Handler),
        exit(Old, kill),
        wait(fun() -> case scope(A, Handler) of N when is_pid(N), N =/= Old -> true; _ -> false end end),
        New = scope(A, Handler),
        wait(fun() -> case maps:get(A, (sys:get_state(Local))#state.nodes_map, undefined) of
            {New, _} -> true; _ -> false end end),
        Local ! {'3.5', ack_sync, Old, []},
        _ = sys:get_state(Local),
        wait(fun() -> case maps:get(A, (sys:get_state(Local))#state.nodes_map, undefined) of
            {New, _} -> true; _ -> false end end)
    end || Handler <- [syn_registry, syn_pg]],
    wait(fun() -> view(node()) =:= {P, meta} end).

%% handshakes from a node that isn't connected are ignored, and the nodes sync once connected
disconnected_handshakes_ignored(Config) ->
    A = proplists:get_value(a, Config), B = proplists:get_value(b, Config),
    SA = scope(A, syn_registry), SB = scope(B, syn_registry), Q = pid(B),
    split(A, B),
    SA ! {'3.5', discover, SB},
    SA ! {'3.5', ack_sync, SB, [{x, Q, stale, 1}]},
    _ = sys:get_state(SA),
    false = maps:is_key(B, (sys:get_state(SA))#state.nodes_map),
    undefined = view(A),
    false = lists:member(B, rpc:call(A, erlang, nodes, [])),
    true = rpc:call(A, net_kernel, connect_node, [B]),
    wait(fun() -> maps:is_key(B, (sys:get_state(SA))#state.nodes_map) end).

%% a node running Syn 3.4 sends its messages in the format of its own protocol, tagged '3.0': the scope processes ignore
%% them, so the two nodes don't sync, and a call gets undefined back
messages_from_another_version_ignored(Config) ->
    A = proplists:get_value(a, Config),
    Old = pid(A), P = pid(A), Time = erlang:system_time(),
    Registry = scope(node(), syn_registry), Pg = scope(node(), syn_pg),
    RegistryNodes = (sys:get_state(Registry))#state.nodes_map,
    PgNodes = (sys:get_state(Pg))#state.nodes_map,
    Registry ! {'3.0', discover, Old},
    Registry ! {'3.0', ack_sync, Old, [{y, P, meta, Time}]},
    Registry ! {'3.0', sync_register, x, P, meta, Time, normal},
    Pg ! {'3.0', discover, Old},
    Pg ! {'3.0', ack_sync, Old, [{g, P, meta, Time}]},
    Pg ! {'3.0', sync_join, g, P, meta, Time, normal},
    undefined = gen_server:call(Registry, {'3.0', register_or_update_on_node, A, z, pid(node()), meta}),
    undefined = gen_server:call(Registry, {'3.0', subcluster_nodes}),
    RegistryNodes = (sys:get_state(Registry))#state.nodes_map,
    PgNodes = (sys:get_state(Pg))#state.nodes_map,
    undefined = syn:lookup(protocol, x), undefined = syn:lookup(protocol, y), undefined = syn:lookup(protocol, z),
    [] = syn:members(protocol, g).
