%% ==========================================================================================================
%% Syn - A global Process Registry and Process Group manager.
%%
%% The MIT License (MIT)
%%
%% Copyright (c) 2015-2019 Roberto Ostinelli <roberto@ostinelli.net> and Neato Robotics, Inc.
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
    single_node_register_and_monitor/1,
    single_node_register_and_unregister/1,
    single_node_registration_errors/1,
    single_node_registry_count/1
]).
-export([
    two_nodes_register_monitor_and_unregister/1,
    two_nodes_registry_count/1
]).
-export([
    three_nodes_partial_netsplit_consistency/1,
    three_nodes_full_netsplit_consistency/1,
    three_nodes_start_syn_before_connecting_cluster/1
]).

%% support
-export([
    start_syn_delayed_and_register_local_process/3
]).

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
        {group, two_nodes_process_registration},
        {group, three_nodes_process_registration}
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
            single_node_register_and_monitor,
            single_node_register_and_unregister,
            single_node_registration_errors,
            single_node_registry_count
        ]},
        {two_nodes_process_registration, [shuffle], [
            two_nodes_register_monitor_and_unregister,
            two_nodes_registry_count
        ]},
        {three_nodes_process_registration, [shuffle], [
            three_nodes_partial_netsplit_consistency,
            three_nodes_full_netsplit_consistency,
            three_nodes_start_syn_before_connecting_cluster
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
    Config.

%% -------------------------------------------------------------------
%% Function: end_per_suite(Config0) -> void() | {save_config,Config1}
%% Config0 = Config1 = [tuple()]
%% -------------------------------------------------------------------
end_per_suite(_Config) ->
    ok.

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
    {ok, SlaveNode} = syn_test_suite_helper:start_slave(syn_slave),
    %% config
    [{slave_node, SlaveNode} | Config];
init_per_group(three_nodes_process_registration, Config) ->
    %% start slave
    {ok, SlaveNode1} = syn_test_suite_helper:start_slave(syn_slave_1),
    {ok, SlaveNode2} = syn_test_suite_helper:start_slave(syn_slave_2),
    %% config
    [{slave_node_1, SlaveNode1}, {slave_node_2, SlaveNode2} | Config];
init_per_group(_GroupName, Config) ->
    Config.

%% -------------------------------------------------------------------
%% Function: end_per_group(GroupName, Config0) ->
%%				void() | {save_config,Config1}
%% GroupName = atom()
%% Config0 = Config1 = [tuple()]
%% -------------------------------------------------------------------
end_per_group(two_nodes_process_registration, Config) ->
    SlaveNode = proplists:get_value(slave_node, Config),
    syn_test_suite_helper:connect_node(SlaveNode),
    syn_test_suite_helper:stop_slave(syn_slave),
    timer:sleep(1000);
end_per_group(three_nodes_process_registration, Config) ->
    SlaveNode1 = proplists:get_value(slave_node_1, Config),
    syn_test_suite_helper:connect_node(SlaveNode1),
    SlaveNode2 = proplists:get_value(slave_node_2, Config),
    syn_test_suite_helper:connect_node(SlaveNode2),
    syn_test_suite_helper:stop_slave(syn_slave_1),
    syn_test_suite_helper:stop_slave(syn_slave_2),
    timer:sleep(1000);
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
end_per_testcase(_, _Config) ->
    syn_test_suite_helper:clean_after_test().

%% ===================================================================
%% Tests
%% ===================================================================
single_node_register_and_monitor(_Config) ->
    %% start
    ok = syn:start(),
    %% start processes
    Pid = syn_test_suite_helper:start_process(),
    PidWithMeta = syn_test_suite_helper:start_process(),
    %% retrieve
    undefined = syn:whereis(<<"my proc">>),
    %% register
    ok = syn:register(<<"my proc">>, Pid),
    ok = syn:register(<<"my proc 2">>, Pid),
    ok = syn:register(<<"my proc with meta">>, PidWithMeta, {meta, <<"meta">>}),
    %% retrieve
    Pid = syn:whereis(<<"my proc">>),
    Pid = syn:whereis(<<"my proc 2">>),
    {PidWithMeta, {meta, <<"meta">>}} = syn:whereis(<<"my proc with meta">>, with_meta),
    %% kill process
    syn_test_suite_helper:kill_process(Pid),
    syn_test_suite_helper:kill_process(PidWithMeta),
    timer:sleep(100),
    %% retrieve
    undefined = syn:whereis(<<"my proc">>),
    undefined = syn:whereis(<<"my proc 2">>),
    undefined = syn:whereis(<<"my proc with meta">>).

single_node_register_and_unregister(_Config) ->
    %% start
    ok = syn:start(),
    %% start process
    Pid = syn_test_suite_helper:start_process(),
    %% retrieve
    undefined = syn:whereis(<<"my proc">>),
    %% register
    ok = syn:register(<<"my proc">>, Pid),
    ok = syn:register(<<"my proc 2">>, Pid),
    %% retrieve
    Pid = syn:whereis(<<"my proc">>),
    Pid = syn:whereis(<<"my proc 2">>),
    %% unregister 1
    ok = syn:unregister(<<"my proc">>),
    %% retrieve
    undefined = syn:whereis(<<"my proc">>),
    Pid = syn:whereis(<<"my proc 2">>),
    %% unregister 2
    ok = syn:unregister(<<"my proc 2">>),
    {error, undefined} = syn:unregister(<<"my proc 2">>),
    %% retrieve
    undefined = syn:whereis(<<"my proc">>),
    undefined = syn:whereis(<<"my proc 2">>),
    %% kill process
    syn_test_suite_helper:kill_process(Pid).

single_node_registration_errors(_Config) ->
    %% start
    ok = syn:start(),
    %% start process
    Pid = syn_test_suite_helper:start_process(),
    Pid2 = syn_test_suite_helper:start_process(),
    %% register
    ok = syn:register(<<"my proc">>, Pid),
    {error, taken} = syn:register(<<"my proc">>, Pid2),
    %% kill processes
    syn_test_suite_helper:kill_process(Pid),
    syn_test_suite_helper:kill_process(Pid2),
    timer:sleep(100),
    %% retrieve
    undefined = syn:whereis(<<"my proc">>),
    %% try registering a dead pid
    {error, not_alive} = syn:register(<<"my proc">>, Pid).

single_node_registry_count(_Config) ->
    %% start
    ok = syn:start(),
    %% start process
    Pid = syn_test_suite_helper:start_process(),
    Pid2 = syn_test_suite_helper:start_process(),
    PidUnregistered = syn_test_suite_helper:start_process(),
    %% register
    ok = syn:register(<<"my proc">>, Pid),
    ok = syn:register(<<"my proc 2">>, Pid2),
    %% count
    2 = syn:registry_count(),
    2 = syn:registry_count(node()),
    %% kill & unregister
    syn_test_suite_helper:kill_process(Pid),
    ok = syn:unregister(<<"my proc 2">>),
    syn_test_suite_helper:kill_process(PidUnregistered),
    timer:sleep(100),
    %% count
    0 = syn:registry_count(),
    0 = syn:registry_count(node()).

two_nodes_register_monitor_and_unregister(Config) ->
    %% get slave
    SlaveNode = proplists:get_value(slave_node, Config),
    %% start
    ok = syn:start(),
    ok = rpc:call(SlaveNode, syn, start, []),
    timer:sleep(100),
    %% start processes
    LocalPid = syn_test_suite_helper:start_process(),
    RemotePid = syn_test_suite_helper:start_process(SlaveNode),
    RemotePidRegRemote = syn_test_suite_helper:start_process(SlaveNode),
    %% retrieve
    undefined = syn:whereis(<<"local proc">>),
    undefined = syn:whereis(<<"remote proc">>),
    undefined = syn:whereis(<<"remote proc reg_remote">>),
    undefined = rpc:call(SlaveNode, syn, whereis, [<<"local proc">>]),
    undefined = rpc:call(SlaveNode, syn, whereis, [<<"remote proc">>]),
    undefined = rpc:call(SlaveNode, syn, whereis, [<<"remote proc reg_remote">>]),
    %% register
    ok = syn:register(<<"local proc">>, LocalPid),
    ok = syn:register(<<"remote proc">>, RemotePid),
    ok = rpc:call(SlaveNode, syn, register, [<<"remote proc reg_remote">>, RemotePidRegRemote]),
    timer:sleep(500),
    %% retrieve
    LocalPid = syn:whereis(<<"local proc">>),
    RemotePid = syn:whereis(<<"remote proc">>),
    RemotePidRegRemote = syn:whereis(<<"remote proc reg_remote">>),
    LocalPid = rpc:call(SlaveNode, syn, whereis, [<<"local proc">>]),
    RemotePid = rpc:call(SlaveNode, syn, whereis, [<<"remote proc">>]),
    RemotePidRegRemote = rpc:call(SlaveNode, syn, whereis, [<<"remote proc reg_remote">>]),
    %% kill & unregister processes
    syn_test_suite_helper:kill_process(LocalPid),
    ok = syn:unregister(<<"remote proc">>),
    syn_test_suite_helper:kill_process(RemotePidRegRemote),
    timer:sleep(100),
    %% retrieve
    undefined = syn:whereis(<<"local proc">>),
    undefined = syn:whereis(<<"remote proc">>),
    undefined = syn:whereis(<<"remote proc reg_remote">>),
    undefined = rpc:call(SlaveNode, syn, whereis, [<<"local proc">>]),
    undefined = rpc:call(SlaveNode, syn, whereis, [<<"remote proc">>]),
    undefined = rpc:call(SlaveNode, syn, whereis, [<<"remote proc reg_remote">>]),
    %% kill proc
    syn_test_suite_helper:kill_process(RemotePid).

two_nodes_registry_count(Config) ->
    %% get slave
    SlaveNode = proplists:get_value(slave_node, Config),
    %% start
    ok = syn:start(),
    ok = rpc:call(SlaveNode, syn, start, []),
    timer:sleep(100),
    %% start processes
    LocalPid = syn_test_suite_helper:start_process(),
    RemotePid = syn_test_suite_helper:start_process(SlaveNode),
    RemotePidRegRemote = syn_test_suite_helper:start_process(SlaveNode),
    PidUnregistered = syn_test_suite_helper:start_process(),
    %% register
    ok = syn:register(<<"local proc">>, LocalPid),
    ok = syn:register(<<"remote proc">>, RemotePid),
    ok = rpc:call(SlaveNode, syn, register, [<<"remote proc reg_remote">>, RemotePidRegRemote]),
    timer:sleep(500),
    %% count
    3 = syn:registry_count(),
    1 = syn:registry_count(node()),
    2 = syn:registry_count(SlaveNode),
    %% kill & unregister processes
    syn_test_suite_helper:kill_process(LocalPid),
    ok = syn:unregister(<<"remote proc">>),
    syn_test_suite_helper:kill_process(RemotePidRegRemote),
    timer:sleep(100),
    %% count
    0 = syn:registry_count(),
    0 = syn:registry_count(node()),
    0 = syn:registry_count(SlaveNode),
    %% kill proc
    syn_test_suite_helper:kill_process(RemotePid).

three_nodes_partial_netsplit_consistency(Config) ->
    %% get slaves
    SlaveNode1 = proplists:get_value(slave_node_1, Config),
    SlaveNode2 = proplists:get_value(slave_node_2, Config),
    %% start syn on nodes
    ok = syn:start(),
    ok = rpc:call(SlaveNode1, syn, start, []),
    ok = rpc:call(SlaveNode2, syn, start, []),
    timer:sleep(100),
    %% start processes
    Pid0 = syn_test_suite_helper:start_process(),
    Pid0b = syn_test_suite_helper:start_process(),
    Pid1 = syn_test_suite_helper:start_process(SlaveNode1),
    Pid2 = syn_test_suite_helper:start_process(SlaveNode2),
    timer:sleep(100),
    %% retrieve
    undefined = syn:whereis(<<"proc0">>),
    undefined = syn:whereis(<<"proc0b">>),
    undefined = syn:whereis(<<"proc1">>),
    undefined = syn:whereis(<<"proc2">>),
    undefined = rpc:call(SlaveNode1, syn, whereis, [<<"proc0">>]),
    undefined = rpc:call(SlaveNode1, syn, whereis, [<<"proc0b">>]),
    undefined = rpc:call(SlaveNode1, syn, whereis, [<<"proc1">>]),
    undefined = rpc:call(SlaveNode1, syn, whereis, [<<"proc2">>]),
    undefined = rpc:call(SlaveNode2, syn, whereis, [<<"proc0">>]),
    undefined = rpc:call(SlaveNode2, syn, whereis, [<<"proc0b">>]),
    undefined = rpc:call(SlaveNode2, syn, whereis, [<<"proc1">>]),
    undefined = rpc:call(SlaveNode2, syn, whereis, [<<"proc2">>]),
    %% register (mix nodes)
    ok = rpc:call(SlaveNode2, syn, register, [<<"proc0">>, Pid0]),
    ok = syn:register(<<"proc1">>, Pid1),
    ok = rpc:call(SlaveNode1, syn, register, [<<"proc2">>, Pid2]),
    ok = rpc:call(SlaveNode1, syn, register, [<<"proc0b">>, Pid0b]),
    timer:sleep(200),
    %% retrieve
    Pid0 = syn:whereis(<<"proc0">>),
    Pid0b = syn:whereis(<<"proc0b">>),
    Pid1 = syn:whereis(<<"proc1">>),
    Pid2 = syn:whereis(<<"proc2">>),
    Pid0 = rpc:call(SlaveNode1, syn, whereis, [<<"proc0">>]),
    Pid0b = rpc:call(SlaveNode1, syn, whereis, [<<"proc0b">>]),
    Pid1 = rpc:call(SlaveNode1, syn, whereis, [<<"proc1">>]),
    Pid2 = rpc:call(SlaveNode1, syn, whereis, [<<"proc2">>]),
    Pid0 = rpc:call(SlaveNode2, syn, whereis, [<<"proc0">>]),
    Pid0b = rpc:call(SlaveNode2, syn, whereis, [<<"proc0b">>]),
    Pid1 = rpc:call(SlaveNode2, syn, whereis, [<<"proc1">>]),
    Pid2 = rpc:call(SlaveNode2, syn, whereis, [<<"proc2">>]),
    %% disconnect slave 2 from main (slave 1 can still see slave 2)
    syn_test_suite_helper:disconnect_node(SlaveNode2),
    timer:sleep(500),
    %% retrieve
    Pid0 = syn:whereis(<<"proc0">>),
    Pid0b = syn:whereis(<<"proc0b">>),
    Pid1 = syn:whereis(<<"proc1">>),
    undefined = syn:whereis(<<"proc2">>), %% main has lost slave 2 so 'proc2' is removed
    Pid0 = rpc:call(SlaveNode1, syn, whereis, [<<"proc0">>]),
    Pid0b = rpc:call(SlaveNode1, syn, whereis, [<<"proc0b">>]),
    Pid1 = rpc:call(SlaveNode1, syn, whereis, [<<"proc1">>]),
    Pid2 = rpc:call(SlaveNode1, syn, whereis, [<<"proc2">>]), %% slave 1 still has slave 2 so 'proc2' is still there
    %% disconnect slave 1
    syn_test_suite_helper:disconnect_node(SlaveNode1),
    timer:sleep(500),
    %% unregister 0b
    ok = syn:unregister(<<"proc0b">>),
    %% retrieve
    Pid0 = syn:whereis(<<"proc0">>),
    undefined = syn:whereis(<<"proc0b">>),
    undefined = syn:whereis(<<"proc1">>),
    undefined = syn:whereis(<<"proc2">>),
    %% reconnect all
    syn_test_suite_helper:connect_node(SlaveNode1),
    syn_test_suite_helper:connect_node(SlaveNode2),
    timer:sleep(5000),
    %% retrieve
    Pid0 = syn:whereis(<<"proc0">>),
    undefined = syn:whereis(<<"proc0b">>),
    Pid1 = syn:whereis(<<"proc1">>),
    Pid2 = syn:whereis(<<"proc2">>),
    Pid0 = rpc:call(SlaveNode1, syn, whereis, [<<"proc0">>]),
    undefined = rpc:call(SlaveNode1, syn, whereis, [<<"proc0b">>]),
    Pid1 = rpc:call(SlaveNode1, syn, whereis, [<<"proc1">>]),
    Pid2 = rpc:call(SlaveNode1, syn, whereis, [<<"proc2">>]),
    Pid0 = rpc:call(SlaveNode2, syn, whereis, [<<"proc0">>]),
    undefined = rpc:call(SlaveNode2, syn, whereis, [<<"proc0b">>]),
    Pid1 = rpc:call(SlaveNode2, syn, whereis, [<<"proc1">>]),
    Pid2 = rpc:call(SlaveNode2, syn, whereis, [<<"proc2">>]),
    %% kill processes
    syn_test_suite_helper:kill_process(Pid0),
    syn_test_suite_helper:kill_process(Pid1),
    syn_test_suite_helper:kill_process(Pid2).

three_nodes_full_netsplit_consistency(Config) ->
    %% get slaves
    SlaveNode1 = proplists:get_value(slave_node_1, Config),
    SlaveNode2 = proplists:get_value(slave_node_2, Config),
    %% start syn on nodes
    ok = syn:start(),
    ok = rpc:call(SlaveNode1, syn, start, []),
    ok = rpc:call(SlaveNode2, syn, start, []),
    timer:sleep(100),
    %% start processes
    Pid0 = syn_test_suite_helper:start_process(),
    Pid0b = syn_test_suite_helper:start_process(),
    Pid1 = syn_test_suite_helper:start_process(SlaveNode1),
    Pid2 = syn_test_suite_helper:start_process(SlaveNode2),
    timer:sleep(100),
    %% retrieve
    undefined = syn:whereis(<<"proc0">>),
    undefined = syn:whereis(<<"proc0b">>),
    undefined = syn:whereis(<<"proc1">>),
    undefined = syn:whereis(<<"proc2">>),
    undefined = rpc:call(SlaveNode1, syn, whereis, [<<"proc0">>]),
    undefined = rpc:call(SlaveNode1, syn, whereis, [<<"proc0b">>]),
    undefined = rpc:call(SlaveNode1, syn, whereis, [<<"proc1">>]),
    undefined = rpc:call(SlaveNode1, syn, whereis, [<<"proc2">>]),
    undefined = rpc:call(SlaveNode2, syn, whereis, [<<"proc0">>]),
    undefined = rpc:call(SlaveNode2, syn, whereis, [<<"proc0b">>]),
    undefined = rpc:call(SlaveNode2, syn, whereis, [<<"proc1">>]),
    undefined = rpc:call(SlaveNode2, syn, whereis, [<<"proc2">>]),
    %% register (mix nodes)
    ok = rpc:call(SlaveNode2, syn, register, [<<"proc0">>, Pid0]),
    ok = rpc:call(SlaveNode2, syn, register, [<<"proc0b">>, Pid0b]),
    ok = syn:register(<<"proc1">>, Pid1),
    ok = rpc:call(SlaveNode1, syn, register, [<<"proc2">>, Pid2]),
    timer:sleep(200),
    %% retrieve
    Pid0 = syn:whereis(<<"proc0">>),
    Pid0b = syn:whereis(<<"proc0b">>),
    Pid1 = syn:whereis(<<"proc1">>),
    Pid2 = syn:whereis(<<"proc2">>),
    Pid0 = rpc:call(SlaveNode1, syn, whereis, [<<"proc0">>]),
    Pid0b = rpc:call(SlaveNode1, syn, whereis, [<<"proc0b">>]),
    Pid1 = rpc:call(SlaveNode1, syn, whereis, [<<"proc1">>]),
    Pid2 = rpc:call(SlaveNode1, syn, whereis, [<<"proc2">>]),
    Pid0 = rpc:call(SlaveNode2, syn, whereis, [<<"proc0">>]),
    Pid0b = rpc:call(SlaveNode2, syn, whereis, [<<"proc0b">>]),
    Pid1 = rpc:call(SlaveNode2, syn, whereis, [<<"proc1">>]),
    Pid2 = rpc:call(SlaveNode2, syn, whereis, [<<"proc2">>]),
    %% disconnect slave 2 from main (slave 1 can still see slave 2)
    syn_test_suite_helper:disconnect_node(SlaveNode2),
    timer:sleep(500),
    %% retrieve
    Pid0 = syn:whereis(<<"proc0">>),
    Pid0b = syn:whereis(<<"proc0b">>),
    Pid1 = syn:whereis(<<"proc1">>),
    undefined = syn:whereis(<<"proc2">>), %% main has lost slave 2 so 'proc2' is removed
    Pid0 = rpc:call(SlaveNode1, syn, whereis, [<<"proc0">>]),
    Pid0b = rpc:call(SlaveNode1, syn, whereis, [<<"proc0b">>]),
    Pid1 = rpc:call(SlaveNode1, syn, whereis, [<<"proc1">>]),
    Pid2 = rpc:call(SlaveNode1, syn, whereis, [<<"proc2">>]), %% slave 1 still has slave 2 so 'proc2' is still there
    %% disconnect slave 2 from slave 1
    rpc:call(SlaveNode1, syn_test_suite_helper, disconnect_node, [SlaveNode2]),
    timer:sleep(500),
    %% retrieve
    Pid0 = syn:whereis(<<"proc0">>),
    Pid0b = syn:whereis(<<"proc0b">>),
    Pid1 = syn:whereis(<<"proc1">>),
    undefined = syn:whereis(<<"proc2">>), %% main has lost slave 2 so 'proc2' is removed
    undefined = syn:whereis(<<"proc2">>, with_meta),
    Pid0 = rpc:call(SlaveNode1, syn, whereis, [<<"proc0">>]),
    Pid0b = rpc:call(SlaveNode1, syn, whereis, [<<"proc0b">>]),
    Pid1 = rpc:call(SlaveNode1, syn, whereis, [<<"proc1">>]),
    undefined = rpc:call(SlaveNode1, syn, whereis, [<<"proc2">>]),
    %% disconnect slave 1
    syn_test_suite_helper:disconnect_node(SlaveNode1),
    timer:sleep(500),
    %% unregister
    ok = syn:unregister(<<"proc0b">>),
    %% retrieve
    Pid0 = syn:whereis(<<"proc0">>),
    undefined = syn:whereis(<<"proc0b">>),
    undefined = syn:whereis(<<"proc1">>),
    undefined = syn:whereis(<<"proc2">>),
    %% reconnect all
    syn_test_suite_helper:connect_node(SlaveNode1),
    syn_test_suite_helper:connect_node(SlaveNode2),
    rpc:call(SlaveNode1, syn_test_suite_helper, connect_node, [SlaveNode2]),
    timer:sleep(1500),
    %% retrieve
    Pid0 = syn:whereis(<<"proc0">>),
    undefined = syn:whereis(<<"proc0b">>),
    Pid1 = syn:whereis(<<"proc1">>),
    Pid2 = syn:whereis(<<"proc2">>),
    Pid0 = rpc:call(SlaveNode1, syn, whereis, [<<"proc0">>]),
    undefined = rpc:call(SlaveNode1, syn, whereis, [<<"proc0b">>]),
    Pid1 = rpc:call(SlaveNode1, syn, whereis, [<<"proc1">>]),
    Pid2 = rpc:call(SlaveNode1, syn, whereis, [<<"proc2">>]),
    Pid0 = rpc:call(SlaveNode2, syn, whereis, [<<"proc0">>]),
    undefined = rpc:call(SlaveNode2, syn, whereis, [<<"proc0b">>]),
    Pid1 = rpc:call(SlaveNode2, syn, whereis, [<<"proc1">>]),
    Pid2 = rpc:call(SlaveNode2, syn, whereis, [<<"proc2">>]),
    %% kill processes
    syn_test_suite_helper:kill_process(Pid0),
    syn_test_suite_helper:kill_process(Pid0b),
    syn_test_suite_helper:kill_process(Pid1),
    syn_test_suite_helper:kill_process(Pid2).

three_nodes_start_syn_before_connecting_cluster(Config) ->
    ConflictingName = "COMMON",
    %% get slaves
    SlaveNode1 = proplists:get_value(slave_node_1, Config),
    SlaveNode2 = proplists:get_value(slave_node_2, Config),
    %% start processes
    Pid0 = syn_test_suite_helper:start_process(),
    Pid1 = syn_test_suite_helper:start_process(SlaveNode1),
    Pid2 = syn_test_suite_helper:start_process(SlaveNode2),
    %% start delayed
    start_syn_delayed_and_register_local_process(ConflictingName, Pid0, 1500),
    rpc:cast(SlaveNode1, ?MODULE, start_syn_delayed_and_register_local_process, [ConflictingName, Pid1, 1500]),
    rpc:cast(SlaveNode2, ?MODULE, start_syn_delayed_and_register_local_process, [ConflictingName, Pid2, 1500]),
    timer:sleep(500),
    %% disconnect all
    rpc:call(SlaveNode1, syn_test_suite_helper, disconnect_node, [SlaveNode2]),
    syn_test_suite_helper:disconnect_node(SlaveNode1),
    syn_test_suite_helper:disconnect_node(SlaveNode2),
    timer:sleep(1000),
    [] = nodes(),
    %% reconnect all
    syn_test_suite_helper:connect_node(SlaveNode1),
    syn_test_suite_helper:connect_node(SlaveNode2),
    rpc:call(SlaveNode1, syn_test_suite_helper, connect_node, [SlaveNode2]),
    timer:sleep(1500),
    %% count
    1 = syn:registry_count(),
    1 = rpc:call(SlaveNode1, syn, registry_count, []),
    1 = rpc:call(SlaveNode2, syn, registry_count, []),
    %% retrieve
    true = lists:member(syn:whereis(ConflictingName), [Pid0, Pid1, Pid2]),
    true = lists:member(rpc:call(SlaveNode1, syn, whereis, [ConflictingName]), [Pid0, Pid1, Pid2]),
    true = lists:member(rpc:call(SlaveNode2, syn, whereis, [ConflictingName]), [Pid0, Pid1, Pid2]),
    %% kill processes
    syn_test_suite_helper:kill_process(Pid0),
    syn_test_suite_helper:kill_process(Pid1),
    syn_test_suite_helper:kill_process(Pid2).

%% ===================================================================
%% Internal
%% ===================================================================
start_syn_delayed_and_register_local_process(Name, Pid, Ms) ->
    spawn(fun() ->
        lists:foreach(fun(Node) ->
            syn_test_suite_helper:disconnect_node(Node)
        end, nodes()),
        timer:sleep(Ms),
        [] = nodes(),
        syn:start(),
        ok = syn:register(Name, Pid, node())
    end).
