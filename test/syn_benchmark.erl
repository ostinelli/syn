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
    wait_registration_propagation/1,
    wait_unregistration_propagation/0
]).
-export([
    start_profiling/0,
    stop_profiling/0
]).

%% ===================================================================
%% API
%% ===================================================================

%% example run: `PROCESS_COUNT=100000 WORKERS_PER_NODE=100 NODES_COUNT=2 make bench`
start() ->
    %% init
    ProcessCount = list_to_integer(os:getenv("PROCESS_COUNT", "100000")),
    WorkersPerNode = list_to_integer(os:getenv("WORKERS_PER_NODE", "1")),
    SlavesCount = list_to_integer(os:getenv("NODES_COUNT", "1")),

    ProcessesPerNode = round(ProcessCount / SlavesCount),

    io:format("-----> Starting benchmark~n"),
    io:format("       --> Nodes: ~w (~w slaves)~n", [SlavesCount + 1, SlavesCount]),
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

    {RegPropagationTimeMs, _} = timer:tc(?MODULE, wait_registration_propagation, [ProcessCount]),
    RegPropagationTime = RegPropagationTimeMs / 1000000,
    io:format("----> Eventual additional time to propagate all to master: ~p secs.~n", [RegPropagationTime]),

    %% sum
    RegTakenTime = (lists:max(RegRemoteNodesTimes) + RegPropagationTime),
    RegistrationRate = ProcessCount / RegTakenTime,
    io:format("====> Registeration rate (with propagation): ~p/sec.~n~n", [RegistrationRate]),

    timer:sleep(1000),

    %% start unregistration
    lists:foreach(fun({Node, FromName, ToName}) ->
        rpc:cast(Node, ?MODULE, unregister_on_node, [CollectorPid, WorkersPerNode, FromName, ToName])
    end, NodesInfo),

    %% wait
    UnregRemoteNodesTimes = wait_from_all_remote_nodes(nodes(), []),

    io:format("----> Remote unregistration times:~n"),
    io:format("      --> MIN: ~p secs.~n", [lists:min(UnregRemoteNodesTimes)]),
    io:format("      --> MAX: ~p secs.~n", [lists:max(UnregRemoteNodesTimes)]),

    {UnregPropagationTimeMs, _} = timer:tc(?MODULE, wait_unregistration_propagation, []),
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

    {ReRegPropagationTimeMs, _} = timer:tc(?MODULE, wait_registration_propagation, [ProcessCount]),
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
    {KillPropagationTimeMs, _} = timer:tc(?MODULE, wait_unregistration_propagation, []),
    KillPropagationTime = KillPropagationTimeMs / 1000000,
    io:format("----> Time to propagate killed process to to master: ~p secs.~n", [KillPropagationTime]),

    KillRate = ProcessCount / KillPropagationTime,
    io:format("====> Unregistered after kill rate (with propagation): ~p/sec.~n~n", [KillRate]),

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
    wait_register_on_node(CollectorPid, 0, WorkersPerNode).

worker_register_on_node(_Name, []) -> ok;
worker_register_on_node(Name, [Pid | PidsTail]) ->
    ok = syn:register(Name, Pid),
    worker_register_on_node(Name + 1, PidsTail).

wait_register_on_node(CollectorPid, Time, 0) ->
    io:format("----> Registered on node ~p on ~p secs.~n", [node(), Time]),
    CollectorPid ! {done, node(), Time};
wait_register_on_node(CollectorPid, Time, WorkersRemainingCount) ->
    receive
        {done, WorkerTime} ->
            Time1 = lists:max([WorkerTime, Time]),
            wait_register_on_node(CollectorPid, Time1, WorkersRemainingCount - 1)
    end.

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
    wait_unregister_on_node(CollectorPid, 0, WorkersPerNode).

worker_unregister_on_node(FromName, ToName) when FromName > ToName -> ok;
worker_unregister_on_node(Name, ToName) ->
    ok = syn:unregister(Name),
    worker_unregister_on_node(Name + 1, ToName).

wait_unregister_on_node(CollectorPid, Time, 0) ->
    io:format("----> Unregistered on node ~p on ~p secs.~n", [node(), Time]),
    CollectorPid ! {done, node(), Time};
wait_unregister_on_node(CollectorPid, Time, WorkersRemainingCount) ->
    receive
        {done, WorkerTime} ->
            Time1 = lists:max([WorkerTime, Time]),
            wait_unregister_on_node(CollectorPid, Time1, WorkersRemainingCount - 1)
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

wait_registration_propagation(ProcessCount) ->
    case syn:registry_count(default) of
        ProcessCount ->
            ok;

        _ ->
            timer:sleep(50),
            wait_registration_propagation(ProcessCount)
    end.

wait_unregistration_propagation() ->
    case syn:registry_count(default) of
        0 ->
            ok;

        _ ->
            timer:sleep(50),
            wait_unregistration_propagation()
    end.

start_profiling() ->
    {ok, P} = eprof:start(),
    eprof:start_profiling(erlang:processes() -- [P]).

stop_profiling() ->
    eprof:stop_profiling(),
    eprof:analyze(total).