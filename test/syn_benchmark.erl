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
-compile([export_all]).

%% ===================================================================
%% API
%% ===================================================================

%% example run: `PROCESS_COUNT=100000 NODES_COUNT=2 make bench`
start() ->
    %% init
    SlavesCount = list_to_integer(os:getenv("NODES_COUNT", "1")),
    ProcessCount = list_to_integer(os:getenv("PROCESS_COUNT", "100000")),

    ProcessesPerNode = round(ProcessCount / SlavesCount),
    io:format("-----> Starting benchmark on ~w nodes (~w slaves) (for ~w processes total (~w / slave node)~n",
        [SlavesCount + 1, SlavesCount, ProcessCount, ProcessesPerNode]
    ),

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

%%    {ok, P} = eprof:start(),
%%    eprof:start_profiling(erlang:processes() -- [P]),

    %% start registration
    lists:foreach(fun({Node, FromName, _ToName}) ->
        Pids = maps:get(Node, PidsMap),
        rpc:cast(Node, ?MODULE, register_on_node, [CollectorPid, FromName, Pids])
    end, NodesInfo),

    %% wait
    RegRemoteNodesTimes = wait_from_all_remote_nodes(nodes(), []),

    io:format("----> Remote registration times:~n"),
    io:format("      --> MIN: ~p secs.~n", [lists:min(RegRemoteNodesTimes)]),
    io:format("      --> MAX: ~p secs.~n", [lists:max(RegRemoteNodesTimes)]),

    {RegPropagationTimeMs, _} = timer:tc(?MODULE, wait_registration_propagation, [NodesInfo]),
    RegPropagationTime = RegPropagationTimeMs / 1000000,
    io:format("----> Eventual additional time to propagate all to master: ~p secs.~n", [RegPropagationTime]),

    %% sum
    RegTakenTime = (lists:max(RegRemoteNodesTimes) + RegPropagationTime),
    RegistrationRate = ProcessCount / RegTakenTime,
    io:format("====> Registeration rate (with propagation): ~p/sec.~n~n", [RegistrationRate]),

%%    eprof:stop_profiling(),
%%    eprof:analyze(total),

    timer:sleep(1000),

    %% start unregistration
    lists:foreach(fun({Node, FromName, ToName}) ->
        rpc:cast(Node, ?MODULE, unregister_on_node, [CollectorPid, FromName, ToName])
    end, NodesInfo),

    %% wait
    UnregRemoteNodesTimes = wait_from_all_remote_nodes(nodes(), []),

    io:format("----> Remote unregistration times:~n"),
    io:format("      --> MIN: ~p secs.~n", [lists:min(UnregRemoteNodesTimes)]),
    io:format("      --> MAX: ~p secs.~n", [lists:max(UnregRemoteNodesTimes)]),

    {UnregPropagationTimeMs, _} = timer:tc(?MODULE, wait_unregistration_propagation, [NodesInfo]),
    UnregPropagationTime = UnregPropagationTimeMs / 1000000,
    io:format("----> Eventual additional time to propagate all to master: ~p secs.~n", [UnregPropagationTime]),

    %% sum
    UnregTakenTime = (lists:max(UnregRemoteNodesTimes) + UnregPropagationTime),
    UnregistrationRate = ProcessCount / UnregTakenTime,
    io:format("====> Unregisteration rate (with propagation): ~p/sec.~n~n", [UnregistrationRate]),

    %% start re-registration
    lists:foreach(fun({Node, FromName, _ToName}) ->
        Pids = maps:get(Node, PidsMap),
        rpc:cast(Node, ?MODULE, register_on_node, [CollectorPid, FromName, Pids])
    end, NodesInfo),

    %% wait
    ReRegRemoteNodesTimes = wait_from_all_remote_nodes(nodes(), []),

    io:format("----> Remote re-registration times:~n"),
    io:format("      --> MIN: ~p secs.~n", [lists:min(ReRegRemoteNodesTimes)]),
    io:format("      --> MAX: ~p secs.~n", [lists:max(ReRegRemoteNodesTimes)]),

    {ReRegPropagationTimeMs, _} = timer:tc(?MODULE, wait_registration_propagation, [NodesInfo]),
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
    {KillPropagationTimeMs, _} = timer:tc(?MODULE, wait_unregistration_propagation, [NodesInfo]),
    KillPropagationTime = KillPropagationTimeMs / 1000000,
    io:format("----> Time to propagate killed process to to master: ~p secs.~n", [KillPropagationTime]),

    KillRate = ProcessCount / KillPropagationTime,
    io:format("====> Unregistered after kill rate (with propagation): ~p/sec.~n~n", [KillRate]),

    %% stop node
    init:stop().

register_on_node(CollectorPid, FromName, Pids) ->
    {TimeMs, _} = timer:tc(?MODULE, do_register_on_node, [FromName, Pids]),
    Time = TimeMs / 1000000,
    io:format("----> Registered on node ~p on ~p secs.~n", [node(), Time]),
    CollectorPid ! {done, node(), Time}.

do_register_on_node(_Name, []) -> ok;
do_register_on_node(Name, [Pid | PidsTail]) ->
    ok = syn:register(Name, Pid),
    do_register_on_node(Name + 1, PidsTail).

unregister_on_node(CollectorPid, FromName, ToName) ->
    {TimeMs, _} = timer:tc(?MODULE, do_unregister_on_node, [FromName, ToName]),
    Time = TimeMs / 1000000,
    io:format("----> Unregistered on node ~p on ~p secs.~n", [node(), Time]),
    CollectorPid ! {done, node(), Time}.

do_unregister_on_node(FromName, ToName) when FromName > ToName -> ok;
do_unregister_on_node(Name, ToName) ->
    ok = syn:unregister(Name),
    do_unregister_on_node(Name + 1, ToName).

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

wait_registration_propagation([]) -> ok;
wait_registration_propagation([{_Node, _FromName, ToName} | NodeInfosTail] = NodesInfo) ->
    case syn:lookup(ToName) of
        undefined ->
            timer:sleep(50),
            wait_registration_propagation(NodesInfo);

        {_Pid, undefined} ->
            wait_registration_propagation(NodeInfosTail)
    end.

wait_unregistration_propagation([]) -> ok;
wait_unregistration_propagation([{_Node, _FromName, ToName} | NodeInfosTail] = NodesInfo) ->
    case syn:lookup(ToName) of
        undefined ->
            wait_unregistration_propagation(NodeInfosTail);

        {_Pid, undefined} ->
            timer:sleep(50),
            wait_unregistration_propagation(NodesInfo)
    end.
