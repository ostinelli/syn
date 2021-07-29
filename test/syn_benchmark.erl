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
-export([process_loop/0]).
-export([collection_loop/2]).
-export([run_test_on_node/3]).
-export([register_pids/1]).
-export([unregister_pids/1]).
-export([wait_for_unregistered/1]).

%% macros
-define(MAX_RETRIEVE_WAITING_TIME, 60000).

%% ===================================================================
%% API
%% ===================================================================
start() ->
    io:format("-----> Starting benchmark on node ~s~n", [node()]),
    %% init
    ConfigFilePath = filename:join([filename:dirname(code:which(?MODULE)), "syn_benchmark.config"]),
    {ok, BenchConfig} = file:consult(ConfigFilePath),
    RemoteHosts = proplists:get_value(remote_nodes, BenchConfig, []),
    ProcessCount = list_to_integer(os:getenv("SYN_PROCESS_COUNT", "100000")),
    %% start nodes
    lists:foreach(fun(RemoteHost) ->
        io:format("-----> Starting slave node ~s@~s~n", [maps:get(node, RemoteHost), maps:get(host, RemoteHost)]),
        {ok, _} = syn_test_suite_helper:start_slave(
            maps:get(node, RemoteHost),
            maps:get(host, RemoteHost),
            maps:get(user, RemoteHost),
            maps:get(pass, RemoteHost)
        )
    end, RemoteHosts),

    Nodes = [node() | nodes()],
    io:format("-----> Started ~p nodes: ~p~n", [length(Nodes), Nodes]),

    %% start syn everywhere
    lists:foreach(fun(Node) ->
        ok = rpc:call(Node, syn_test_suite_helper, start_syn, [])
    end, Nodes),
    timer:sleep(1000),

    %% compute names per node
    ProcessesPerNode = round(ProcessCount / length(Nodes)),
    io:format("-----> ~p processes per node~n", [ProcessesPerNode]),

    %% launch test everywhere
    CollectingPid = self(),
    lists:foldl(fun(Node, Acc) ->
        FromName = Acc * ProcessesPerNode + 1,
        ToName = FromName + ProcessesPerNode - 1,
        rpc:cast(Node, ?MODULE, run_test_on_node, [CollectingPid, FromName, ToName]),
        Acc + 1
    end, 0, Nodes),

    Results = collection_loop(Nodes, []),
    io:format("-----> Results: ~p~n", [Results]),

    %% stop syn everywhere
    lists:foreach(fun(Node) ->
        ok = rpc:call(Node, syn, stop, [])
    end, [node() | nodes()]),
    timer:sleep(1000),

    %% stop nodes
    lists:foreach(fun(SlaveNode) ->
        syn_test_suite_helper:connect_node(SlaveNode),
        ShortName = list_to_atom(lists:nth(1, string:split(atom_to_list(SlaveNode), "@"))),
        syn_test_suite_helper:stop_slave(ShortName)
    end, nodes()),
    io:format("-----> Stopped ~p nodes: ~p~n", [length(Nodes), Nodes]),

    %% stop node
    init:stop().

run_test_on_node(CollectingPid, FromName, ToName) ->
    %% launch processes - list is in format {Name, pid()}
    PidTuples = [{Name, spawn(?MODULE, process_loop, [])} || Name <- lists:seq(FromName, ToName)],
    {ToName, ToPid} = lists:last(PidTuples),

    %% register
    {TimeReg0, _} = timer:tc(?MODULE, register_pids, [PidTuples]),
    RegisteringRate1 = length(PidTuples) / TimeReg0 * 1000000,
    %% check
    ToPid = syn:whereis(ToName),

    %% unregister
    {TimeReg1, _} = timer:tc(?MODULE, unregister_pids, [PidTuples]),
    UnRegisteringRate1 = length(PidTuples) / TimeReg1 * 1000000,
    %% check
    undefined = syn:whereis(ToName),

    %% re-register
    {TimeReg3, _} = timer:tc(?MODULE, register_pids, [PidTuples]),
    RegisteringRate2 = length(PidTuples) / TimeReg3 * 1000000,
    %% check
    ToPid = syn:whereis(ToName),

    %% kill all
    lists:foreach(fun({_Name, Pid}) ->
        exit(Pid, kill)
    end, PidTuples),

    %% check all unregistered
    {TimeReg4, _} = timer:tc(?MODULE, wait_for_unregistered, [ToName]),
    CheckAllKilled = TimeReg4 / 1000000,

    %% return
    CollectingPid ! {node(), [
        {registering_rate_1, RegisteringRate1},
        {unregistering_rate_1, UnRegisteringRate1},
        {registering_rate_2, RegisteringRate2},
        {check_all_killed, CheckAllKilled}
    ]}.

%% ===================================================================
%% Internal
%% ===================================================================
collection_loop([], Results) -> Results;
collection_loop(Nodes, Results) ->
    receive
        {Node, Result} ->
            collection_loop(lists:delete(Node, Nodes), [{Node, Result} | Results])
    after ?MAX_RETRIEVE_WAITING_TIME ->
        io:format("COULD NOT COMPLETE TEST IN ~p seconds", [?MAX_RETRIEVE_WAITING_TIME])
    end.

process_loop() ->
    receive
        _ -> ok
    end.

register_pids([]) -> ok;
register_pids([{Name, Pid} | TPidTuples]) ->
    ok = syn:register(Name, Pid),
    register_pids(TPidTuples).

wait_for_unregistered(ToName) ->
    case syn:whereis(ToName) of
        undefined ->
            ok;
        _ ->
            timer:sleep(50),
            wait_for_unregistered(ToName)
    end.

unregister_pids([]) -> ok;
unregister_pids([{Name, _Pid} | TPidTuples]) ->
    ok = syn:unregister(Name),
    unregister_pids(TPidTuples).
