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
-module(syn_registry_SUITE).

%% callbacks
-export([all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([groups/0, init_per_group/2, end_per_group/2]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% tests
-export([
    single_node_when_mnesia_is_ram_find_by_key/1,
    single_node_when_mnesia_is_ram_find_by_key_with_meta/1,
    single_node_when_mnesia_is_ram_find_by_pid/1,
    single_node_when_mnesia_is_ram_find_by_pid_with_meta/1,
    single_node_when_mnesia_is_ram_re_register_error/1,
    single_node_when_mnesia_is_ram_unregister/1,
    single_node_when_mnesia_is_ram_process_count/1,
    single_node_when_mnesia_is_ram_callback_on_process_exit/1,
    single_node_when_mnesia_is_disc_find_by_key/1
]).
-export([
    two_nodes_when_mnesia_is_ram_find_by_key/1,
    two_nodes_when_mnesia_is_ram_find_by_key_with_meta/1,
    two_nodes_when_mnesia_is_ram_process_count/1,
    two_nodes_when_mnesia_is_ram_callback_on_process_exit/1,
    two_nodes_when_mnesia_is_disc_find_by_pid/1
]).

%% internals
-export([registry_process_exit_callback_dummy/4]).

%% include
-include_lib("common_test/include/ct.hrl").


%% ===================================================================
%% Callbacks
%% ===================================================================

%% -------------------------------------------------------------------
%% Function: all() -> GroupsAndTestCases | {skip,Reason}
%% GroupsAndTestCases = [{group,GroupName} | TestCase]
%% GroupName = atom()
%% TestCase = atom()
%% Reason = term()
%% -------------------------------------------------------------------
all() ->
    [
        {group, single_node_process_registration},
        {group, two_nodes_process_registration}
    ].

%% -------------------------------------------------------------------
%% Function: groups() -> [Group]
%% Group = {GroupName,Properties,GroupsAndTestCases}
%% GroupName = atom()
%% Properties = [parallel | sequence | Shuffle | {RepeatType,N}]
%% GroupsAndTestCases = [Group | {group,GroupName} | TestCase]
%% TestCase = atom()
%% Shuffle = shuffle | {shuffle,{integer(),integer(),integer()}}
%% RepeatType = repeat | repeat_until_all_ok | repeat_until_all_fail |
%%			   repeat_until_any_ok | repeat_until_any_fail
%% N = integer() | forever
%% -------------------------------------------------------------------
groups() ->
    [
        {single_node_process_registration, [shuffle], [
            single_node_when_mnesia_is_ram_find_by_key,
            single_node_when_mnesia_is_ram_find_by_key_with_meta,
            single_node_when_mnesia_is_ram_find_by_pid,
            single_node_when_mnesia_is_ram_find_by_pid_with_meta,
            single_node_when_mnesia_is_ram_re_register_error,
            single_node_when_mnesia_is_ram_unregister,
            single_node_when_mnesia_is_ram_process_count,
            single_node_when_mnesia_is_ram_callback_on_process_exit,
            single_node_when_mnesia_is_disc_find_by_key
        ]},
        {two_nodes_process_registration, [shuffle], [
            two_nodes_when_mnesia_is_ram_find_by_key,
            two_nodes_when_mnesia_is_ram_find_by_key_with_meta,
            two_nodes_when_mnesia_is_ram_process_count,
            two_nodes_when_mnesia_is_ram_callback_on_process_exit,
            two_nodes_when_mnesia_is_disc_find_by_pid
        ]}
    ].
%% -------------------------------------------------------------------
%% Function: init_per_suite(Config0) ->
%%				Config1 | {skip,Reason} |
%%              {skip_and_save,Reason,Config1}
%% Config0 = Config1 = [tuple()]
%% Reason = term()
%% -------------------------------------------------------------------
init_per_suite(Config) ->
    %% config
    [
        {slave_node_short_name, syn_slave}
        | Config
    ].

%% -------------------------------------------------------------------
%% Function: end_per_suite(Config0) -> void() | {save_config,Config1}
%% Config0 = Config1 = [tuple()]
%% -------------------------------------------------------------------
end_per_suite(_Config) -> ok.

%% -------------------------------------------------------------------
%% Function: init_per_group(GroupName, Config0) ->
%%				Config1 | {skip,Reason} |
%%              {skip_and_save,Reason,Config1}
%% GroupName = atom()
%% Config0 = Config1 = [tuple()]
%% Reason = term()
%% -------------------------------------------------------------------
init_per_group(two_nodes_process_registration, Config) ->
    %% start slave
    SlaveNodeShortName = proplists:get_value(slave_node_short_name, Config),
    {ok, SlaveNode} = syn_test_suite_helper:start_slave(SlaveNodeShortName),
    %% config
    [
        {slave_node, SlaveNode}
        | Config
    ];
init_per_group(_GroupName, Config) -> Config.

%% -------------------------------------------------------------------
%% Function: end_per_group(GroupName, Config0) ->
%%				void() | {save_config,Config1}
%% GroupName = atom()
%% Config0 = Config1 = [tuple()]
%% -------------------------------------------------------------------
end_per_group(two_nodes_process_registration, Config) ->
    %% get slave node name
    SlaveNodeShortName = proplists:get_value(slave_node_short_name, Config),
    %% stop slave
    syn_test_suite_helper:stop_slave(SlaveNodeShortName);
end_per_group(_GroupName, _Config) ->
    ok.

% ----------------------------------------------------------------------------------------------------------
% Function: init_per_testcase(TestCase, Config0) ->
%				Config1 | {skip,Reason} | {skip_and_save,Reason,Config1}
% TestCase = atom()
% Config0 = Config1 = [tuple()]
% Reason = term()
% ----------------------------------------------------------------------------------------------------------
init_per_testcase(_TestCase, Config) ->
    Config.

% ----------------------------------------------------------------------------------------------------------
% Function: end_per_testcase(TestCase, Config0) ->
%				void() | {save_config,Config1} | {fail,Reason}
% TestCase = atom()
% Config0 = Config1 = [tuple()]
% Reason = term()
% ----------------------------------------------------------------------------------------------------------
end_per_testcase(_TestCase, Config) ->
    %% get slave
    SlaveNode = proplists:get_value(slave_node, Config),
    syn_test_suite_helper:clean_after_test(SlaveNode).

%% ===================================================================
%% Tests
%% ===================================================================
single_node_when_mnesia_is_ram_find_by_key(_Config) ->
    %% set schema location
    application:set_env(mnesia, schema_location, ram),
    %% start
    ok = syn:start(),
    ok = syn:init(),
    %% start process
    Pid = syn_test_suite_helper:start_process(),
    %% retrieve
    undefined = syn:find_by_key(<<"my proc">>),
    %% register
    ok = syn:register(<<"my proc">>, Pid),
    %% retrieve
    Pid = syn:find_by_key(<<"my proc">>),
    %% kill process
    syn_test_suite_helper:kill_process(Pid),
    timer:sleep(100),
    %% retrieve
    undefined = syn:find_by_key(<<"my proc">>).

single_node_when_mnesia_is_ram_find_by_key_with_meta(_Config) ->
    %% set schema location
    application:set_env(mnesia, schema_location, ram),
    %% start
    ok = syn:start(),
    ok = syn:init(),
    %% start process
    Pid1 = syn_test_suite_helper:start_process(),
    Pid2 = syn_test_suite_helper:start_process(),
    %% retrieve
    undefined = syn:find_by_key(<<"my proc 1">>, with_meta),
    undefined = syn:find_by_key(<<"my proc 2">>, with_meta),
    %% register
    Meta = [{some, 1}, {meta, <<"data">>}],
    ok = syn:register(<<"my proc 1">>, Pid1, Meta),
    ok = syn:register(<<"my proc 2">>, Pid2),
    %% retrieve
    {Pid1, Meta} = syn:find_by_key(<<"my proc 1">>, with_meta),
    {Pid2, undefined} = syn:find_by_key(<<"my proc 2">>, with_meta),
    %% kill process
    syn_test_suite_helper:kill_process(Pid1),
    syn_test_suite_helper:kill_process(Pid2),
    timer:sleep(100),
    %% retrieve
    undefined = syn:find_by_key(<<"my proc 1">>, with_meta),
    undefined = syn:find_by_key(<<"my proc 2">>, with_meta).

single_node_when_mnesia_is_ram_find_by_pid(_Config) ->
    %% set schema location
    application:set_env(mnesia, schema_location, ram),
    %% start
    ok = syn:start(),
    ok = syn:init(),
    %% start process
    Pid = syn_test_suite_helper:start_process(),
    %% register
    ok = syn:register(<<"my proc">>, Pid),
    %% retrieve
    <<"my proc">> = syn:find_by_pid(Pid),
    %% kill process
    syn_test_suite_helper:kill_process(Pid),
    timer:sleep(100),
    %% retrieve
    undefined = syn:find_by_pid(Pid).

single_node_when_mnesia_is_ram_find_by_pid_with_meta(_Config) ->
    %% set schema location
    application:set_env(mnesia, schema_location, ram),
    %% start
    ok = syn:start(),
    ok = syn:init(),
    %% start process
    Pid1 = syn_test_suite_helper:start_process(),
    Pid2 = syn_test_suite_helper:start_process(),
    %% retrieve
    undefined = syn:find_by_pid(Pid1, with_meta),
    undefined = syn:find_by_pid(Pid2, with_meta),
    %% register
    Meta = [{some, 1}, {meta, <<"data">>}],
    ok = syn:register(<<"my proc 1">>, Pid1, Meta),
    ok = syn:register(<<"my proc 2">>, Pid2),
    %% retrieve
    {<<"my proc 1">>, Meta} = syn:find_by_pid(Pid1, with_meta),
    {<<"my proc 2">>, undefined} = syn:find_by_pid(Pid2, with_meta),
    %% kill process
    syn_test_suite_helper:kill_process(Pid1),
    syn_test_suite_helper:kill_process(Pid2),
    timer:sleep(100),
    %% retrieve
    undefined = syn:find_by_pid(Pid1, with_meta),
    undefined = syn:find_by_pid(Pid2, with_meta).

single_node_when_mnesia_is_ram_re_register_error(_Config) ->
    %% set schema location
    application:set_env(mnesia, schema_location, ram),
    %% start
    ok = syn:start(),
    ok = syn:init(),
    %% start process
    Pid = syn_test_suite_helper:start_process(),
    Pid2 = syn_test_suite_helper:start_process(),
    %% register
    ok = syn:register(<<"my proc">>, Pid),
    {error, taken} = syn:register(<<"my proc">>, Pid2),
    %% retrieve
    Pid = syn:find_by_key(<<"my proc">>),
    %% kill process
    syn_test_suite_helper:kill_process(Pid),
    timer:sleep(100),
    %% retrieve
    undefined = syn:find_by_key(<<"my proc">>),
    %% reuse
    ok = syn:register(<<"my proc">>, Pid2),
    %% retrieve
    Pid2 = syn:find_by_key(<<"my proc">>),
    %% kill process
    syn_test_suite_helper:kill_process(Pid),
    timer:sleep(100),
    %% retrieve
    undefined = syn:find_by_pid(Pid).

single_node_when_mnesia_is_ram_unregister(_Config) ->
    %% set schema location
    application:set_env(mnesia, schema_location, ram),
    %% start
    ok = syn:start(),
    ok = syn:init(),
    %% start process
    Pid = syn_test_suite_helper:start_process(),
    %% unregister
    {error, undefined} = syn:unregister(<<"my proc">>),
    %% register
    ok = syn:register(<<"my proc">>, Pid),
    %% retrieve
    Pid = syn:find_by_key(<<"my proc">>),
    %% unregister
    ok = syn:unregister(<<"my proc">>),
    %% retrieve
    undefined = syn:find_by_key(<<"my proc">>),
    undefined = syn:find_by_pid(Pid),
    %% kill process
    syn_test_suite_helper:kill_process(Pid).

single_node_when_mnesia_is_ram_process_count(_Config) ->
    %% set schema location
    application:set_env(mnesia, schema_location, ram),
    %% start
    ok = syn:start(),
    ok = syn:init(),
    %% count
    0 = syn:registry_count(),
    %% start process
    Pid1 = syn_test_suite_helper:start_process(),
    Pid2 = syn_test_suite_helper:start_process(),
    Pid3 = syn_test_suite_helper:start_process(),
    %% register
    ok = syn:register(1, Pid1),
    ok = syn:register(2, Pid2),
    ok = syn:register(3, Pid3),
    %% count
    3 = syn:registry_count(),
    %% kill processes
    syn_test_suite_helper:kill_process(Pid1),
    syn_test_suite_helper:kill_process(Pid2),
    syn_test_suite_helper:kill_process(Pid3),
    timer:sleep(100),
    %% count
    0 = syn:registry_count().

single_node_when_mnesia_is_ram_callback_on_process_exit(_Config) ->
    CurrentNode = node(),
    %% set schema location
    application:set_env(mnesia, schema_location, ram),
    %% load configuration variables from syn-test.config => this defines the callback
    syn_test_suite_helper:set_environment_variables(),
    %% start
    ok = syn:start(),
    ok = syn:init(),
    %% register global process
    ResultPid = self(),
    global:register_name(syn_register_process_SUITE_result, ResultPid),
    %% start process
    Pid = syn_test_suite_helper:start_process(),
    %% register
    Meta = {some, meta},
    ok = syn:register(<<"my proc">>, Pid, Meta),
    %% kill process
    syn_test_suite_helper:kill_process(Pid),
    %% check callback were triggered
    receive
        {exited, CurrentNode, <<"my proc">>, Pid, Meta, killed} -> ok
    after 2000 ->
        ok = registry_process_exit_callback_was_not_called_from_local_node
    end,
    %% unregister
    global:unregister_name(syn_register_process_SUITE_result).

single_node_when_mnesia_is_disc_find_by_key(_Config) ->
    %% set schema location
    application:set_env(mnesia, schema_location, disc),
    %% create schema
    mnesia:create_schema([node()]),
    %% start
    ok = syn:start(),
    ok = syn:init(),
    %% start process
    Pid = syn_test_suite_helper:start_process(),
    %% retrieve
    undefined = syn:find_by_key(<<"my proc">>),
    %% register
    ok = syn:register(<<"my proc">>, Pid),
    %% retrieve
    Pid = syn:find_by_key(<<"my proc">>),
    %% kill process
    syn_test_suite_helper:kill_process(Pid),
    timer:sleep(100),
    %% retrieve
    undefined = syn:find_by_key(<<"my proc">>).

two_nodes_when_mnesia_is_ram_find_by_key(Config) ->
    %% get slave
    SlaveNode = proplists:get_value(slave_node, Config),
    %% set schema location
    application:set_env(mnesia, schema_location, ram),
    rpc:call(SlaveNode, mnesia, schema_location, [ram]),
    %% start
    ok = syn:start(),
    ok = syn:init(),
    ok = rpc:call(SlaveNode, syn, start, []),
    ok = rpc:call(SlaveNode, syn, init, []),
    timer:sleep(100),
    %% start process
    Pid = syn_test_suite_helper:start_process(),
    %% retrieve
    undefined = syn:find_by_key(<<"my proc">>),
    undefined = rpc:call(SlaveNode, syn, find_by_key, [<<"my proc">>]),
    %% register
    ok = syn:register(<<"my proc">>, Pid),
    %% retrieve
    Pid = syn:find_by_key(<<"my proc">>),
    Pid = rpc:call(SlaveNode, syn, find_by_key, [<<"my proc">>]),
    %% kill process
    syn_test_suite_helper:kill_process(Pid),
    timer:sleep(100),
    %% retrieve
    undefined = syn:find_by_key(<<"my proc">>),
    undefined = rpc:call(SlaveNode, syn, find_by_key, [<<"my proc">>]).

two_nodes_when_mnesia_is_ram_find_by_key_with_meta(Config) ->
    %% get slave
    SlaveNode = proplists:get_value(slave_node, Config),
    %% set schema location
    application:set_env(mnesia, schema_location, ram),
    rpc:call(SlaveNode, mnesia, schema_location, [ram]),
    %% start
    ok = syn:start(),
    ok = syn:init(),
    ok = rpc:call(SlaveNode, syn, start, []),
    ok = rpc:call(SlaveNode, syn, init, []),
    timer:sleep(100),
    %% start process
    Pid1 = syn_test_suite_helper:start_process(),
    Pid2 = syn_test_suite_helper:start_process(),
    %% retrieve
    undefined = syn:find_by_key(<<"my proc 1">>),
    undefined = rpc:call(SlaveNode, syn, find_by_key, [<<"my proc 1">>]),
    undefined = syn:find_by_key(<<"my proc 2">>),
    undefined = rpc:call(SlaveNode, syn, find_by_key, [<<"my proc 2">>]),
    %% register
    Meta = [{some, 1}, {meta, <<"data">>}],
    ok = syn:register(<<"my proc 1">>, Pid1, Meta),
    ok = syn:register(<<"my proc 2">>, Pid2),
    %% retrieve
    {Pid1, Meta} = syn:find_by_key(<<"my proc 1">>, with_meta),
    {Pid1, Meta} = rpc:call(SlaveNode, syn, find_by_key, [<<"my proc 1">>, with_meta]),
    {Pid2, undefined} = syn:find_by_key(<<"my proc 2">>, with_meta),
    {Pid2, undefined} = rpc:call(SlaveNode, syn, find_by_key, [<<"my proc 2">>, with_meta]),
    %% kill process
    syn_test_suite_helper:kill_process(Pid1),
    syn_test_suite_helper:kill_process(Pid2),
    timer:sleep(100),
    %% retrieve
    undefined = syn:find_by_key(<<"my proc 1">>),
    undefined = rpc:call(SlaveNode, syn, find_by_key, [<<"my proc 1">>]),
    undefined = syn:find_by_key(<<"my proc 2">>),
    undefined = rpc:call(SlaveNode, syn, find_by_key, [<<"my proc 2">>]).

two_nodes_when_mnesia_is_ram_process_count(Config) ->
    %% get slave
    SlaveNode = proplists:get_value(slave_node, Config),
    CurrentNode = node(),
    %% set schema location
    application:set_env(mnesia, schema_location, ram),
    rpc:call(SlaveNode, mnesia, schema_location, [ram]),
    %% start
    ok = syn:start(),
    ok = syn:init(),
    ok = rpc:call(SlaveNode, syn, start, []),
    ok = rpc:call(SlaveNode, syn, init, []),
    timer:sleep(100),
    %% count
    0 = syn:registry_count(),
    0 = rpc:call(SlaveNode, syn, registry_count, []),
    0 = syn:registry_count(CurrentNode),
    0 = syn:registry_count(SlaveNode),
    0 = rpc:call(SlaveNode, syn, registry_count, [CurrentNode]),
    0 = rpc:call(SlaveNode, syn, registry_count, [SlaveNode]),
    %% start processes
    PidLocal1 = syn_test_suite_helper:start_process(),
    PidLocal2 = syn_test_suite_helper:start_process(),
    PidSlave = syn_test_suite_helper:start_process(SlaveNode),
    %% register
    ok = syn:register(1, PidLocal1),
    ok = syn:register(2, PidLocal2),
    ok = syn:register(3, PidSlave),
    timer:sleep(100),
    %% count
    3 = syn:registry_count(),
    3 = rpc:call(SlaveNode, syn, registry_count, []),
    2 = syn:registry_count(CurrentNode),
    1 = syn:registry_count(SlaveNode),
    2 = rpc:call(SlaveNode, syn, registry_count, [CurrentNode]),
    1 = rpc:call(SlaveNode, syn, registry_count, [SlaveNode]),
    %% kill processes
    syn_test_suite_helper:kill_process(PidLocal1),
    syn_test_suite_helper:kill_process(PidLocal2),
    syn_test_suite_helper:kill_process(PidSlave),
    timer:sleep(100),
    %% count
    0 = syn:registry_count(),
    0 = rpc:call(SlaveNode, syn, registry_count, []),
    0 = syn:registry_count(CurrentNode),
    0 = syn:registry_count(SlaveNode),
    0 = rpc:call(SlaveNode, syn, registry_count, [CurrentNode]),
    0 = rpc:call(SlaveNode, syn, registry_count, [SlaveNode]).

two_nodes_when_mnesia_is_ram_callback_on_process_exit(Config) ->
    %% get slave
    SlaveNode = proplists:get_value(slave_node, Config),
    CurrentNode = node(),
    %% set schema location
    application:set_env(mnesia, schema_location, ram),
    rpc:call(SlaveNode, mnesia, schema_location, [ram]),
    %% load configuration variables from syn-test.config => this defines the callback
    syn_test_suite_helper:set_environment_variables(),
    syn_test_suite_helper:set_environment_variables(SlaveNode),
    %% start
    ok = syn:start(),
    ok = syn:init(),
    ok = rpc:call(SlaveNode, syn, start, []),
    ok = rpc:call(SlaveNode, syn, init, []),
    timer:sleep(100),
    %% register global process
    ResultPid = self(),
    global:register_name(syn_register_process_SUITE_result, ResultPid),
    %% start processes
    PidLocal = syn_test_suite_helper:start_process(),
    PidSlave = syn_test_suite_helper:start_process(SlaveNode),
    %% register
    Meta = {some, meta},
    ok = syn:register(<<"local">>, PidLocal, Meta),
    ok = syn:register(<<"slave">>, PidSlave),
    %% kill process
    syn_test_suite_helper:kill_process(PidLocal),
    syn_test_suite_helper:kill_process(PidSlave),
    %% check callback were triggered
    receive
        {exited, CurrentNode, <<"local">>, PidLocal, Meta, killed} -> ok
    after 2000 ->
        ok = registry_process_exit_callback_was_not_called_from_local_node
    end,
    receive
        {exited, SlaveNode, <<"slave">>, PidSlave, undefined, killed} -> ok
    after 2000 ->
        ok = registry_process_exit_callback_was_not_called_from_slave_node
    end,
    %% unregister
    global:unregister_name(syn_register_process_SUITE_result).

two_nodes_when_mnesia_is_disc_find_by_pid(Config) ->
    %% get slave
    SlaveNode = proplists:get_value(slave_node, Config),
    %% set schema location
    application:set_env(mnesia, schema_location, disc),
    rpc:call(SlaveNode, mnesia, schema_location, [disc]),
    %% create schema
    mnesia:create_schema([node(), SlaveNode]),
    %% start
    ok = syn:start(),
    ok = syn:init(),
    ok = rpc:call(SlaveNode, syn, start, []),
    ok = rpc:call(SlaveNode, syn, init, []),
    timer:sleep(100),
    %% start process
    Pid = syn_test_suite_helper:start_process(),
    %% register
    ok = syn:register(<<"my proc">>, Pid),
    %% retrieve
    <<"my proc">> = syn:find_by_pid(Pid),
    <<"my proc">> = rpc:call(SlaveNode, syn, find_by_pid, [Pid]),
    %% kill process
    syn_test_suite_helper:kill_process(Pid),
    timer:sleep(100),
    %% retrieve
    undefined = syn:find_by_pid(Pid),
    undefined = rpc:call(SlaveNode, syn, find_by_pid, [Pid]).

%% ===================================================================
%% Internal
%% ===================================================================
registry_process_exit_callback_dummy(Key, Pid, Meta, Reason) ->
    global:send(syn_register_process_SUITE_result, {exited, node(), Key, Pid, Meta, Reason}).
