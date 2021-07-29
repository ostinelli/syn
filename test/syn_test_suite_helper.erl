%% ==========================================================================================================
%% Syn - A global Process Registry and Process Group manager.
%%
%% The MIT License (MIT)
%%
%% Copyright (c) 2015 Roberto Ostinelli <roberto@ostinelli.net> and Neato Robotics, Inc.
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
-export([use_custom_handler/0]).
-export([use_anti_entropy/2]).
-export([send_error_logger_to_disk/0]).
-export([kill_sharded/1]).
-export([start_syn/0, start_syn/1]).

%% internal
-export([process_main/0]).

-define(SYN_DEFAULT_SHARDS_NUM, 4).

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
        rpc:call(Node, application, unset_env, [syn, event_handler]),
        rpc:call(Node, application, unset_env, [syn, anti_entropy])
    end, Nodes).

start_syn() ->
    start_syn(?SYN_DEFAULT_SHARDS_NUM).

start_syn(SynShards) ->
    application:set_env(syn, syn_shards, SynShards),
    syn:start().

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

kill_process(Pid) ->
    exit(Pid, kill).

use_custom_handler() ->
    application:set_env(syn, event_handler, syn_test_event_handler).

use_anti_entropy(registry, Interval) ->
    application:set_env(syn, anti_entropy, [
        {registry, [
            {interval, Interval},
            {interval_max_deviation, 0.1}
        ]}
    ]);
use_anti_entropy(groups, Interval) ->
    application:set_env(syn, anti_entropy, [
        {groups, [
            {interval, Interval},
            {interval_max_deviation, 0.1}
        ]}
    ]).

send_error_logger_to_disk() ->
    error_logger:logfile({open, atom_to_list(node())}).

kill_sharded(Module) ->
    SynInstances = application:get_env(syn, syn_shards, 1),
    lists:foreach(fun (I) ->
        Name = syn_backbone:get_process_name(Module, I),
        exit(whereis(Name), kill)
        end, lists:seq(1, SynInstances)
    ).

%% ===================================================================
%% Internal
%% ===================================================================
process_main() ->
    receive
        _ -> process_main()
    end.
