%% ==========================================================================================================
%% Syn - A global Process Registry and Process Group manager.
%%
%% The MIT License (MIT)
%%
%% Copyright (c) 2019-2021 Roberto Ostinelli <roberto@ostinelli.net> and Neato Robotics, Inc.
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
-module(syn_benchmark).

%% API
-export([
    start/0,
    start_processes/1,
    process_loop/0,
    register_on_node/4,
    unregister_on_node/4,
    join_on_node/3,
    leave_on_node/3,
    wait_registry_propagation/1,
    wait_groups_propagation/1
]).
-export([
    start_profiling/1,
    stop_profiling/1,
    start_profiling_on_node/0,
    stop_profiling_on_node/0
]).

%% macros
-define(TEST_GROUP_NAME, <<"test-group">>).

%% ===================================================================
%% API
%% ===================================================================

%% example run: `PROCESS_COUNT=100000 WORKERS_PER_NODE=100 NODES_COUNT=2 make bench`
start() ->
    %% init
    ProcessCount = list_to_integer(os:getenv("PROCESS_COUNT", "100000")),
    WorkersPerNode = list_to_integer(os:getenv("WORKERS_PER_NODE", "1")),
    SlavesCount = list_to_integer(os:getenv("NODES_COUNT", "1")),
    SkipRegistry = case os:getenv("SKIP_REGISTRY") of false -> false; _ -> true end,
    SkipGroups = case os:getenv("SKIP_GROUPS") of false -> false; _ -> true end,

    ProcessesPerNode = round(ProcessCount / SlavesCount),

    io:format("-----> Starting benchmark~n"),
    io:format("       --> Nodes: ~w / ~w slave(s)~n", [SlavesCount + 1, SlavesCount]),
    io:format("       --> Total processes: ~w (~w / slave node)~n", [ProcessCount, ProcessesPerNode]),
    io:format("       --> Workers per node: ~w~n~n", [WorkersPerNode]),

    %% start nodes
    NodesInfo = lists:foldl(fun(I, Acc) ->
        %% start slave
        CountBin = integer_to_binary(I),
        NodeShortName = binary_to_atom(<<"slave_", CountBin/binary>>),
        {ok, Node} = ct_slave:start(NodeShortName, [
            {boot_timeout, 10},
            {monitor_master, true}
        ]),
        %% add code path
        CodePath = code:get_path(),
        true = rpc:call(Node, code, set_path, [CodePath]),
        %% start syn
        rpc:call(Node, syn, start, []),
        %% gather data
        FromName = (I - 1) * ProcessesPerNode + 1,
        ToName = FromName + ProcessesPerNode - 1,
        %% fold
        [{Node, FromName, ToName} | Acc]
    end, [], lists:seq(1, SlavesCount)),

    %% start syn locally
    ok = syn:start(),
    timer:sleep(1000),

    CollectorPid = self(),

    %% start processes
    PidsMap = lists:foldl(fun({Node, _FromName, _ToName}, Acc) ->
        Pids = rpc:call(Node, ?MODULE, start_processes, [ProcessesPerNode]),
        maps:put(Node, Pids, Acc)
    end, #{}, NodesInfo),

    case SkipRegistry of
        false ->
            %% start registration
            lists:foreach(fun({Node, FromName, _ToName}) ->
                Pids = maps:get(Node, PidsMap),
                rpc:cast(Node, ?MODULE, register_on_node, [CollectorPid, WorkersPerNode, FromName, Pids])
            end, NodesInfo),

            %% wait
            RegRemoteNodesTimes = wait_from_all_remote_nodes(nodes(), []),

            io:format("----> Remote registration times:~n"),
            io:format("      --> MIN: ~p secs.~n", [lists:min(RegRemoteNodesTimes)]),
            io:format("      --> MAX: ~p secs.~n", [lists:max(RegRemoteNodesTimes)]),

            {RegPropagationTimeMs, _} = timer:tc(?MODULE, wait_registry_propagation, [ProcessCount]),
            RegPropagationTime = RegPropagationTimeMs / 1000000,
            io:format("----> Eventual additional time to propagate all to master: ~p secs.~n", [RegPropagationTime]),

            %% sum
            RegTakenTime = (lists:max(RegRemoteNodesTimes) + RegPropagationTime),
            RegistrationRate = ProcessCount / RegTakenTime,
            io:format("====> Registeration rate (with propagation): ~p/sec.~n~n", [RegistrationRate]),

            %% start unregistration
            lists:foreach(fun({Node, FromName, ToName}) ->
                rpc:cast(Node, ?MODULE, unregister_on_node, [CollectorPid, WorkersPerNode, FromName, ToName])
            end, NodesInfo),

            %% wait
            UnregRemoteNodesTimes = wait_from_all_remote_nodes(nodes(), []),

            io:format("----> Remote unregistration times:~n"),
            io:format("      --> MIN: ~p secs.~n", [lists:min(UnregRemoteNodesTimes)]),
            io:format("      --> MAX: ~p secs.~n", [lists:max(UnregRemoteNodesTimes)]),

            {UnregPropagationTimeMs, _} = timer:tc(?MODULE, wait_registry_propagation, [0]),
            UnregPropagationTime = UnregPropagationTimeMs / 1000000,
            io:format("----> Eventual additional time to propagate all to master: ~p secs.~n", [UnregPropagationTime]),

            %% sum
            UnregTakenTime = (lists:max(UnregRemoteNodesTimes) + UnregPropagationTime),
            UnregistrationRate = ProcessCount / UnregTakenTime,
            io:format("====> Unregisteration rate (with propagation): ~p/sec.~n~n", [UnregistrationRate]),

            %% start re-registration
            lists:foreach(fun({Node, FromName, _ToName}) ->
                Pids = maps:get(Node, PidsMap),
                rpc:cast(Node, ?MODULE, register_on_node, [CollectorPid, WorkersPerNode, FromName, Pids])
            end, NodesInfo),

            %% wait
            ReRegRemoteNodesTimes = wait_from_all_remote_nodes(nodes(), []),

            io:format("----> Remote re-registration times:~n"),
            io:format("      --> MIN: ~p secs.~n", [lists:min(ReRegRemoteNodesTimes)]),
            io:format("      --> MAX: ~p secs.~n", [lists:max(ReRegRemoteNodesTimes)]),

            {ReRegPropagationTimeMs, _} = timer:tc(?MODULE, wait_registry_propagation, [ProcessCount]),
            ReRegPropagationTime = ReRegPropagationTimeMs / 1000000,
            io:format("----> Eventual additional time to propagate all to master: ~p secs.~n", [ReRegPropagationTime]),

            %% sum
            ReRegTakenTime = (lists:max(ReRegRemoteNodesTimes) + ReRegPropagationTime),
            ReRegistrationRate = ProcessCount / ReRegTakenTime,
            io:format("====> Re-registeration rate (with propagation): ~p/sec.~n~n", [ReRegistrationRate]),

            %% kill all processes
            maps:foreach(fun(_Node, Pids) ->
                lists:foreach(fun(Pid) -> exit(Pid, kill) end, Pids)
            end, PidsMap),

            %% wait all unregistered
            {RegKillPropagationTimeMs, _} = timer:tc(?MODULE, wait_registry_propagation, [0]),
            RegKillPropagationTime = RegKillPropagationTimeMs / 1000000,
            io:format("----> Time to propagate killed process to to master: ~p secs.~n", [RegKillPropagationTime]),

            RegKillRate = ProcessCount / RegKillPropagationTime,
            io:format("====> Unregistered after kill rate (with propagation): ~p/sec.~n~n", [RegKillRate]);

        true ->
            io:format("~n====> Skipping REGISTRY.~n~n")
    end,

    case SkipGroups of
        false ->
            %% start joining
            lists:foreach(fun({Node, _FromName, _ToName}) ->
                Pids = maps:get(Node, PidsMap),
                rpc:cast(Node, ?MODULE, join_on_node, [CollectorPid, WorkersPerNode, Pids])
            end, NodesInfo),

            %% wait
            JoinRemoteNodesTimes = wait_from_all_remote_nodes(nodes(), []),

            io:format("----> Remote join times:~n"),
            io:format("      --> MIN: ~p secs.~n", [lists:min(JoinRemoteNodesTimes)]),
            io:format("      --> MAX: ~p secs.~n", [lists:max(JoinRemoteNodesTimes)]),

            {JoinPropagationTimeMs, _} = timer:tc(?MODULE, wait_groups_propagation, [ProcessCount]),
            JoinPropagationTime = JoinPropagationTimeMs / 1000000,
            io:format("----> Eventual additional time to propagate all to master: ~p secs.~n", [JoinPropagationTime]),

            %% sum
            JoinTakenTime = (lists:max(JoinRemoteNodesTimes) + JoinPropagationTime),
            JoinRate = ProcessCount / JoinTakenTime,
            io:format("====> Join rate (with propagation): ~p/sec.~n~n", [JoinRate]),

            %% start leaving
            lists:foreach(fun({Node, _FromName, _ToName}) ->
                Pids = maps:get(Node, PidsMap),
                rpc:cast(Node, ?MODULE, leave_on_node, [CollectorPid, WorkersPerNode, Pids])
            end, NodesInfo),

            %% wait
            LeaveRemoteNodesTimes = wait_from_all_remote_nodes(nodes(), []),

            io:format("----> Remote leave times:~n"),
            io:format("      --> MIN: ~p secs.~n", [lists:min(LeaveRemoteNodesTimes)]),
            io:format("      --> MAX: ~p secs.~n", [lists:max(LeaveRemoteNodesTimes)]),

            {LeavePropagationTimeMs, _} = timer:tc(?MODULE, wait_groups_propagation, [0]),
            LeavePropagationTime = LeavePropagationTimeMs / 1000000,
            io:format("----> Eventual additional time to propagate all to master: ~p secs.~n", [LeavePropagationTime]),

            %% sum
            LeaveTakenTime = (lists:max(LeaveRemoteNodesTimes) + LeavePropagationTime),
            LeaveRate = ProcessCount / LeaveTakenTime,
            io:format("====> Leave rate (with propagation): ~p/sec.~n~n", [LeaveRate]),

            %% start re-joining
            lists:foreach(fun({Node, _FromName, _ToName}) ->
                Pids = maps:get(Node, PidsMap),
                rpc:cast(Node, ?MODULE, join_on_node, [CollectorPid, WorkersPerNode, Pids])
            end, NodesInfo),

            %% wait
            ReJoinRemoteNodesTimes = wait_from_all_remote_nodes(nodes(), []),

            io:format("----> Remote join times:~n"),
            io:format("      --> MIN: ~p secs.~n", [lists:min(ReJoinRemoteNodesTimes)]),
            io:format("      --> MAX: ~p secs.~n", [lists:max(ReJoinRemoteNodesTimes)]),

            {ReJoinPropagationTimeMs, _} = timer:tc(?MODULE, wait_groups_propagation, [ProcessCount]),
            ReJoinPropagationTime = ReJoinPropagationTimeMs / 1000000,
            io:format("----> Eventual additional time to propagate all to master: ~p secs.~n", [ReJoinPropagationTime]),

            %% sum
            ReJoinTakenTime = (lists:max(ReJoinRemoteNodesTimes) + ReJoinPropagationTime),
            ReJoinRate = ProcessCount / ReJoinTakenTime,
            io:format("====> Re-join rate (with propagation): ~p/sec.~n~n", [ReJoinRate]),

            %% kill all processes
            maps:foreach(fun(_Node, Pids) ->
                lists:foreach(fun(Pid) -> exit(Pid, kill) end, Pids)
            end, PidsMap),

            %% wait all unregistered
            {GroupsKillPropagationTimeMs, _} = timer:tc(?MODULE, wait_groups_propagation, [0]),
            GroupsKillPropagationTime = GroupsKillPropagationTimeMs / 1000000,
            io:format("----> Time to propagate killed process to to master: ~p secs.~n", [GroupsKillPropagationTime]),

            GroupsKillRate = ProcessCount / GroupsKillPropagationTime,
            io:format("====> Left after kill rate (with propagation): ~p/sec.~n~n", [GroupsKillRate]);

        true ->
            io:format("~n====> Skipping GROUPS.~n")
    end,

    %% stop node
    init:stop().

register_on_node(CollectorPid, WorkersPerNode, FromName, Pids) ->
    %% split pids in workers
    PidsPerNode = round(length(Pids) / WorkersPerNode),
    {WorkerInfo, []} = lists:foldl(fun(I, {WInfo, RPids}) ->
        {WorkerPids, RestOfPids} = case I of
            WorkersPerNode ->
                %% last in the loop, get remaining pids
                {RPids, []};
            _ ->
                %% get portion of pids
                lists:split(PidsPerNode, RPids)
        end,
        WorkerFromName = FromName + (PidsPerNode * (I - 1)),
        {[{WorkerFromName, WorkerPids} | WInfo], RestOfPids}
    end, {[], Pids}, lists:seq(1, WorkersPerNode)),
    %% spawn workers
    ReplyPid = self(),
    lists:foreach(fun({WorkerFromName, WorkerPids}) ->
        spawn(fun() ->
            StartAt = os:system_time(millisecond),
            worker_register_on_node(WorkerFromName, WorkerPids),
            Time = (os:system_time(millisecond) - StartAt) / 1000,
            ReplyPid ! {done, Time}
        end)
    end, WorkerInfo),
    %% wait
    Time = wait_done_on_node(CollectorPid, 0, WorkersPerNode),
    io:format("----> Registered on node ~p on ~p secs.~n", [node(), Time]).

worker_register_on_node(_Name, []) -> ok;
worker_register_on_node(Name, [Pid | PidsTail]) ->
    ok = syn:register(Name, Pid),
    worker_register_on_node(Name + 1, PidsTail).

unregister_on_node(CollectorPid, WorkersPerNode, FromName, ToName) ->
    %% split pids in workers
    ProcessesPerNode = ToName - FromName + 1,
    ProcessesPerWorker = round(ProcessesPerNode / WorkersPerNode),
    WorkerInfo = lists:foldl(fun(I, Acc) ->
        {WorkerFromName, WorkerToName} = case I of
            WorkersPerNode ->
                %% last in the loop
                {FromName + (I - 1) * ProcessesPerWorker, ToName};

            _ ->
                {FromName + (I - 1) * ProcessesPerWorker, FromName + I * ProcessesPerWorker - 1}
        end,
        [{WorkerFromName, WorkerToName} | Acc]
    end, [], lists:seq(1, WorkersPerNode)),
    %% spawn workers
    ReplyPid = self(),
    lists:foreach(fun({WorkerFromName, WorkerToName}) ->
        spawn(fun() ->
            StartAt = os:system_time(millisecond),
            worker_unregister_on_node(WorkerFromName, WorkerToName),
            Time = (os:system_time(millisecond) - StartAt) / 1000,
            ReplyPid ! {done, Time}
        end)
    end, WorkerInfo),
    %% wait
    Time = wait_done_on_node(CollectorPid, 0, WorkersPerNode),
    io:format("----> Unregistered on node ~p on ~p secs.~n", [node(), Time]).

worker_unregister_on_node(FromName, ToName) when FromName > ToName -> ok;
worker_unregister_on_node(Name, ToName) ->
    ok = syn:unregister(Name),
    worker_unregister_on_node(Name + 1, ToName).

join_on_node(CollectorPid, WorkersPerNode, Pids) ->
    %% split pids in workers
    PidsPerNode = round(length(Pids) / WorkersPerNode),
    {PidsPerWorker, []} = lists:foldl(fun(I, {P, RPids}) ->
        {WPids, RestOfPids} = case I of
            WorkersPerNode ->
                %% last in the loop, get remaining pids
                {RPids, []};
            _ ->
                %% get portion of pids
                lists:split(PidsPerNode, RPids)
        end,
        {[WPids | P], RestOfPids}
    end, {[], Pids}, lists:seq(1, WorkersPerNode)),
    %% spawn workers
    ReplyPid = self(),
    lists:foreach(fun(WorkerPids) ->
        spawn(fun() ->
            StartAt = os:system_time(millisecond),
            worker_join_on_node(WorkerPids),
            Time = (os:system_time(millisecond) - StartAt) / 1000,
            ReplyPid ! {done, Time}
        end)
    end, PidsPerWorker),
    %% wait
    Time = wait_done_on_node(CollectorPid, 0, WorkersPerNode),
    io:format("----> Joined on node ~p on ~p secs.~n", [node(), Time]).

worker_join_on_node([]) -> ok;
worker_join_on_node([Pid | PidsTail]) ->
    ok = syn:join(?TEST_GROUP_NAME, Pid),
    worker_join_on_node(PidsTail).

leave_on_node(CollectorPid, WorkersPerNode, Pids) ->
    %% split pids in workers
    PidsPerNode = round(length(Pids) / WorkersPerNode),
    {PidsPerWorker, []} = lists:foldl(fun(I, {P, RPids}) ->
        {WPids, RestOfPids} = case I of
            WorkersPerNode ->
                %% last in the loop, get remaining pids
                {RPids, []};
            _ ->
                %% get portion of pids
                lists:split(PidsPerNode, RPids)
        end,
        {[WPids | P], RestOfPids}
    end, {[], Pids}, lists:seq(1, WorkersPerNode)),
    %% spawn workers
    ReplyPid = self(),
    lists:foreach(fun(WorkerPids) ->
        spawn(fun() ->
            StartAt = os:system_time(millisecond),
            worker_leave_on_node(WorkerPids),
            Time = (os:system_time(millisecond) - StartAt) / 1000,
            ReplyPid ! {done, Time}
        end)
    end, PidsPerWorker),
    %% wait
    Time = wait_done_on_node(CollectorPid, 0, WorkersPerNode),
    io:format("----> Left on node ~p on ~p secs.~n", [node(), Time]).

worker_leave_on_node([]) -> ok;
worker_leave_on_node([Pid | PidsTail]) ->
    ok = syn:leave(?TEST_GROUP_NAME, Pid),
    worker_leave_on_node(PidsTail).

wait_done_on_node(CollectorPid, Time, 0) ->
    CollectorPid ! {done, node(), Time},
    Time;
wait_done_on_node(CollectorPid, Time, WorkersRemainingCount) ->
    receive
        {done, WorkerTime} ->
            Time1 = lists:max([WorkerTime, Time]),
            wait_done_on_node(CollectorPid, Time1, WorkersRemainingCount - 1)
    end.

start_processes(Count) ->
    start_processes(Count, []).
start_processes(0, Pids) ->
    Pids;
start_processes(Count, Pids) ->
    Pid = spawn(fun process_loop/0),
    start_processes(Count - 1, [Pid | Pids]).

process_loop() ->
    receive
        _ -> ok
    end.

wait_from_all_remote_nodes([], Times) -> Times;
wait_from_all_remote_nodes([RemoteNode | Tail], Times) ->
    receive
        {done, RemoteNode, Time} ->
            wait_from_all_remote_nodes(Tail, [Time | Times])
    end.

wait_registry_propagation(DesiredCount) ->
    case syn:registry_count(default) of
        DesiredCount ->
            ok;

        _ ->
            timer:sleep(50),
            wait_registry_propagation(DesiredCount)
    end.

wait_groups_propagation(DesiredCount) ->
    case length(syn:members(?TEST_GROUP_NAME)) of
        DesiredCount ->
            ok;

        _ ->
            timer:sleep(50),
            wait_groups_propagation(DesiredCount)
    end.

start_profiling(NodesInfo) ->
    {Node, _FromName, _ToName} = hd(NodesInfo),
    ok = rpc:call(Node, ?MODULE, start_profiling_on_node, []).

stop_profiling(NodesInfo) ->
    {Node, _FromName, _ToName} = hd(NodesInfo),
    ok = rpc:call(Node, ?MODULE, stop_profiling_on_node, []).

start_profiling_on_node() ->
    {ok, P} = eprof:start(),
    eprof:start_profiling(erlang:processes() -- [P]),
    ok.

stop_profiling_on_node() ->
    eprof:stop_profiling(),
    eprof:analyze(total),
    ok.
