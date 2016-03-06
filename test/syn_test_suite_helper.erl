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
-export([set_environment_variables/0, set_environment_variables/1]).
-export([start_slave/1, stop_slave/1]).
-export([connect_node/1, disconnect_node/1]).
-export([clean_after_test/0, clean_after_test/1]).
-export([start_process/0, start_process/1, start_process/2]).
-export([kill_process/1]).

%% internal
-export([process_main/0]).

%% macros
-define(SYN_TEST_CONFIG_FILENAME, "syn-test.config").


%% ===================================================================
%% API
%% ===================================================================
set_environment_variables() ->
    set_environment_variables(node()).
set_environment_variables(Node) ->
    % read config file
    ConfigFilePath = filename:join([filename:dirname(code:which(?MODULE)), ?SYN_TEST_CONFIG_FILENAME]),
    {ok, [AppsConfig]} = file:consult(ConfigFilePath),
    % loop to set variables
    F = fun({AppName, AppConfig}) ->
        set_environment_for_app(Node, AppName, AppConfig)
    end,
    lists:foreach(F, AppsConfig).

start_slave(NodeShortName) ->
    EbinFilePath = filename:join([filename:dirname(code:lib_dir(syn, ebin)), "ebin"]),
    TestFilePath = filename:join([filename:dirname(code:lib_dir(syn, ebin)), "test"]),
    %% start slave
    {ok, Node} = ct_slave:start(NodeShortName, [
        {boot_timeout, 10},
        {erl_flags, lists:concat(["-pa ", EbinFilePath, " ", TestFilePath])}
    ]),
    {ok, Node}.

stop_slave(NodeShortName) ->
    {ok, _} = ct_slave:stop(NodeShortName).

connect_node(Node) ->
    net_kernel:connect_node(Node).

disconnect_node(Node) ->
    erlang:disconnect_node(Node).

clean_after_test() ->
    %% delete table
    {atomic, ok} = mnesia:delete_table(syn_registry_table),
    %% stop mnesia
    mnesia:stop(),
    %% delete schema
    mnesia:delete_schema([node()]),
    %% stop syn
    syn:stop().

clean_after_test(undefined) ->
    clean_after_test();
clean_after_test(Node) ->
    %% delete table
    {atomic, ok} = mnesia:delete_table(syn_registry_table),
    %% stop mnesia
    mnesia:stop(),
    rpc:call(Node, mnesia, stop, []),
    %% delete schema
    mnesia:delete_schema([node(), Node]),
    %% stop syn
    syn:stop(),
    rpc:call(Node, syn, stop, []).

start_process() ->
    Pid = spawn(fun process_main/0),
    Pid.
start_process(Node) when is_atom(Node) ->
    Pid = spawn(Node, fun process_main/0),
    Pid;
start_process(Loop) when is_function(Loop) ->
    Pid = spawn(Loop),
    Pid.
start_process(Node, Loop)->
    Pid = spawn(Node, Loop),
    Pid.

kill_process(Pid) ->
    exit(Pid, kill).

%% ===================================================================
%% Internal
%% ===================================================================
set_environment_for_app(Node, AppName, AppConfig) ->
    F = fun({Key, Val}) ->
        ok = rpc:call(Node, application, set_env, [AppName, Key, Val])
    end,
    lists:foreach(F, AppConfig).

process_main() ->
    receive
        _ -> process_main()
    end.
