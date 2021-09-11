%% ==========================================================================================================
%% Syn - A global Process Registry and Process Group manager.
%%
%% The MIT License (MIT)
%%
%% Copyright (c) 2015-2021 Roberto Ostinelli <roberto@ostinelli.net> and Neato Robotics, Inc.
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
-module(syn_test_suite_helper).

%% API
-export([start_slave/1, start_slave/4]).
-export([stop_slave/1, stop_slave/2]).
-export([connect_node/1, disconnect_node/1]).
-export([clean_after_test/0]).
-export([start_process/0, start_process/1, start_process/2]).
-export([kill_process/1]).
-export([wait_cluster_connected/1]).
-export([use_custom_handler/0]).
-export([send_error_logger_to_disk/0]).

%% internal
-export([process_main/0]).

%% ===================================================================
%% API
%% ===================================================================
start_slave(NodeShortName) ->
    {ok, Node} = ct_slave:start(NodeShortName, [{boot_timeout, 10}]),
    CodePath = code:get_path(),
    true = rpc:call(Node, code, set_path, [CodePath]),
    {ok, Node}.
start_slave(NodeShortName, Host, Username, Password) ->
    {ok, Node} = ct_slave:start(Host, NodeShortName, [
        {boot_timeout, 10},
        {username, Username},
        {password, Password}
    ]),
    CodePath = code:get_path(),
    true = rpc:call(Node, code, set_path, [CodePath]),
    {ok, Node}.

stop_slave(NodeShortName) ->
    {ok, _} = ct_slave:stop(NodeShortName).
stop_slave(Host, NodeShortName) ->
    {ok, _} = ct_slave:stop(Host, NodeShortName).

connect_node(Node) ->
    net_kernel:connect_node(Node).

disconnect_node(Node) ->
    erlang:disconnect_node(Node).

clean_after_test() ->
    Nodes = [node() | nodes()],
    %% shutdown
    lists:foreach(fun(Node) ->
        %% close syn
        rpc:call(Node, application, stop, [syn]),
        %% clean env
        rpc:call(Node, application, unset_env, [syn, event_handler])
    end, Nodes).

start_process() ->
    Pid = spawn(fun process_main/0),
    Pid.
start_process(Node) when is_atom(Node) ->
    Pid = spawn(Node, fun process_main/0),
    Pid;
start_process(Loop) when is_function(Loop) ->
    Pid = spawn(Loop),
    Pid.
start_process(Node, Loop) ->
    Pid = spawn(Node, Loop),
    Pid.

kill_process(Pid) when is_pid(Pid) ->
    exit(Pid, kill);
kill_process(RegisteredName) when is_atom(RegisteredName) ->
    exit(whereis(RegisteredName), kill).

wait_cluster_connected(Nodes) ->
    wait_cluster_connected(Nodes, os:system_time(millisecond)).
wait_cluster_connected(Nodes, StartAt) ->
    AllSynced = lists:all(fun(Node) ->
        RemoteNodes = rpc:call(Node, erlang, nodes, []),
        AllNodes = [Node | RemoteNodes],
        lists:sort(AllNodes) == lists:sort(Nodes)
    end, Nodes),

    case AllSynced of
        true ->
            ok;

        false ->
            case os:system_time(millisecond) - StartAt > 5000 of
                true ->
                    {error, {could_not_init_cluster, Nodes}};
                false ->
                    timer:sleep(1000),
                    wait_cluster_connected(Nodes, StartAt)
            end
    end.

use_custom_handler() ->
    application:set_env(syn, event_handler, syn_test_event_handler).

send_error_logger_to_disk() ->
    error_logger:logfile({open, atom_to_list(node())}).

%% ===================================================================
%% Internal
%% ===================================================================
process_main() ->
    receive
        _ -> process_main()
    end.
