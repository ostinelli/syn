%% ==========================================================================================================
%% Syn - A global Process Registry and Process Group manager.
%%
%% The MIT License (MIT)
%%
%% Copyright (c) 2019 Roberto Ostinelli <roberto@ostinelli.net> and Neato Robotics, Inc.
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
-export([start/0]).
-export([register/1, unregister/1]).
-export([register_on_node/1, unregister_on_node/1]).
-export([process_loop/0]).

%% macros
-define(MAX_RETRIEVE_WAITING_TIME, 60000).

%% ===================================================================
%% API
%% ===================================================================
start() ->
    %% init
    NodeCount = list_to_integer(os:getenv("SYN_BENCH_NODE_COUNT", "4")),
    ProcessCount = list_to_integer(os:getenv("SYN_PROCESS_COUNT", "100000")),
    %% start nodes
    SlaveNodes = lists:foldl(fun(Count, Acc) ->
        ShortName = list_to_atom("syn_slave_" ++ integer_to_list(Count)),
        {ok, SlaveNode} = syn_test_suite_helper:start_slave(ShortName),
        [SlaveNode | Acc]
    end, [], lists:seq(1, NodeCount - 1)),
    io:format("-----> Started ~p nodes: ~p~n", [NodeCount, [node() | SlaveNodes]]),

    %% start syn
    lists:foreach(fun(Node) ->
        ok = rpc:call(Node, syn, start, [])
    end, [node() | nodes()]),
    timer:sleep(1000),

    try
        %% launch processes
        {UpperName, PidInfos} = launch_processes(ProcessCount),

        %% benchmark: register
        {TimeReg, _} = timer:tc(?MODULE, register, [PidInfos]),
        io:format("-----> Registered processes in ~p sec, at a rate of ~p/sec~n", [
            TimeReg / 1000000,
            ProcessCount / TimeReg * 1000000
        ]),

        %% benchmark: registration propagation
        {RetrievedInMs1, RetrieveProcess1} = retrieve(pid, UpperName),
        io:format("-----> Check that process with Name ~p was found: ~p in ~p ms~n", [
            UpperName, RetrieveProcess1, RetrievedInMs1
        ]),

        %% benchmark: unregister
        {TimeUnreg, _} = timer:tc(?MODULE, unregister, [PidInfos]),
        io:format("-----> Unregistered processes in ~p sec, at a rate of ~p/sec~n", [
            TimeUnreg / 1000000,
            ProcessCount / TimeUnreg * 1000000
        ]),

        %% benchmark: unregistration propagation
        {RetrievedInMs2, RetrieveProcess2} = retrieve(undefined, UpperName),
        io:format("-----> Check that process with Name ~p was NOT found: ~p in ~p ms~n", [
            UpperName, RetrieveProcess2, RetrievedInMs2
        ]),

        %% benchmark: re-registering
        {TimeReg2, _} = timer:tc(?MODULE, register, [PidInfos]),
        io:format("-----> Re-registered processes in ~p sec, at a rate of ~p/sec~n", [
            TimeReg2 / 1000000,
            ProcessCount / TimeReg2 * 1000000
        ]),

        %% benchmark: re-registration propagation
        {RetrievedInMs3, RetrieveProcess3} = retrieve(pid, UpperName),
        io:format("-----> Check that process with Name ~p was found: ~p in ~p ms~n", [
            UpperName, RetrieveProcess3, RetrievedInMs3
        ]),

        %% benchmark: monitoring
        kill_processes(PidInfos),
        {RetrievedInMs4, RetrieveProcess4} = retrieve(undefined, UpperName),
        io:format("-----> Check that process with Name ~p was NOT found: ~p in ~p ms~n", [
            UpperName, RetrieveProcess4, RetrievedInMs4
        ])

    after
        %% stop syn
        lists:foreach(fun(Node) ->
            ok = rpc:call(Node, syn, stop, [])
        end, [node() | nodes()]),
        timer:sleep(1000),

        %% stop nodes
        lists:foreach(fun(SlaveNode) ->
            syn_test_suite_helper:connect_node(SlaveNode),
            ShortName = list_to_atom(lists:nth(1, string:split(atom_to_list(SlaveNode), "@"))),
            syn_test_suite_helper:stop_slave(ShortName)
        end, SlaveNodes),
        io:format("-----> Stopped ~p nodes: ~p~n", [length(SlaveNodes) + 1, [node() | SlaveNodes]]),

        %% stop node
        init:stop()
    end.

%% ===================================================================
%% Internal
%% ===================================================================
process_loop() ->
    receive
        _ -> ok
    end.

launch_processes(ProcessCount) ->
    %% return the processes info in format [{Node, [{Name, Pid}]}, ...]
    Nodes = [node() | nodes()],
    ProcessesPerNode = round(ProcessCount / length(Nodes)),
    UpperName = integer_to_list(ProcessesPerNode * length(Nodes)),
    F = fun(Node, Acc) ->
        StartingName = length(Acc) * ProcessesPerNode,
        Pids = launch_processes_on_node(ProcessesPerNode, StartingName, Node),
        [{Node, Pids} | Acc]
    end,
    {UpperName, lists:foldl(F, [], Nodes)}.

launch_processes_on_node(ProcessesPerNode, StartingName, Node) ->
    %% return the name and process in a list of format [{Name, Pid}, ...]
    Seq = [
        integer_to_list(Name)
        || Name <- lists:seq(StartingName + 1, ProcessesPerNode + StartingName)
    ],
    [{Name, spawn(Node, ?MODULE, process_loop, [])} || Name <- Seq].

register(PidInfos) ->
    %% register in parallel on all nodes
    F = fun({Node, NodePidInfos}, Acc) ->
        RpcKey = rpc:async_call(Node, ?MODULE, register_on_node, [NodePidInfos]),
        [{Node, RpcKey} | Acc]
    end,
    RpcKeys = lists:foldl(F, [], PidInfos),
    %% wait for registration to complete on all nodes
    FResult = fun({Node, RpcKey}) ->
        Registered = rpc:yield(RpcKey),
        io:format("       Registered ~p processes on node ~p~n", [Registered, Node])
    end,
    lists:foreach(FResult, RpcKeys).

register_on_node(NodePidInfos) ->
    F = fun({Name, Pid}) ->
        syn:register(Name, Pid)
    end,
    lists:foreach(F, NodePidInfos),
    length(NodePidInfos).

retrieve(Expected, Name) ->
    StartTime = epoch_time_ms(),
    retrieve(Expected, Name, StartTime).
retrieve(pid, Name, StartTime) ->
    %% wait for a pid to be returned
    case syn:whereis(Name) of
        undefined ->
            timer:sleep(50),
            case epoch_time_ms() > StartTime + ?MAX_RETRIEVE_WAITING_TIME of
                true -> {error, timeout_during_retrieve};
                false -> retrieve(pid, Name, StartTime)
            end;
        Pid ->
            RetrievedInMs = epoch_time_ms() - StartTime,
            {RetrievedInMs, Pid}
    end;
retrieve(undefined, Name, StartTime) ->
    %% wait for undefined to be returned
    case syn:whereis(Name) of
        undefined ->
            RetrievedInMs = epoch_time_ms() - StartTime,
            {RetrievedInMs, undefined};
        _Pid ->
            timer:sleep(50),
            case epoch_time_ms() > StartTime + ?MAX_RETRIEVE_WAITING_TIME of
                true -> {error, timeout_during_retrieve};
                false -> retrieve(undefined, Name, StartTime)
            end
    end.

unregister(PidInfos) ->
    %% unregister in parallel on all nodes
    F = fun({Node, NodePidInfos}, Acc) ->
        RpcKey = rpc:async_call(Node, ?MODULE, unregister_on_node, [NodePidInfos]),
        [{Node, RpcKey} | Acc]
    end,
    RpcKeys = lists:foldl(F, [], PidInfos),
    %% wait for unregistration to complete on all nodes
    FResult = fun({Node, RpcKey}) ->
        Unregistered = rpc:yield(RpcKey),
        io:format("       Unregistered ~p processes on node ~p~n", [Unregistered, Node])
    end,
    lists:foreach(FResult, RpcKeys).

unregister_on_node(NodePidInfos) ->
    F = fun({Name, _Pid}) ->
        syn:unregister(Name)
    end,
    lists:foreach(F, NodePidInfos),
    length(NodePidInfos).

kill_processes(PidInfos) ->
    F = fun({_Node, NodePidInfos}) ->
        [exit(Pid, kill) || {_Name, Pid} <- NodePidInfos]
    end,
    lists:foreach(F, PidInfos).

epoch_time_ms() ->
    {Mega, Sec, Micro} = os:timestamp(),
    (Mega * 1000000 + Sec) * 1000 + round(Micro / 1000).
