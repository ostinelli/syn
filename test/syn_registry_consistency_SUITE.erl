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
-module(syn_registry_consistency_SUITE).

%% callbacks
-export([all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([groups/0, init_per_group/2, end_per_group/2]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% tests
-export([
    two_nodes_netsplit_when_there_are_no_conflicts/1,
    two_nodes_netsplit_kill_resolution_when_there_are_conflicts/1,
    two_nodes_netsplit_callback_resolution_when_there_are_conflicts/1
]).

-export([
    three_nodes_netsplit_kill_resolution_when_there_are_conflicts/1
]).

%% internal
-export([process_reply_main/0]).
-export([registry_conflicting_process_callback_dummy/3]).

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
        {group, two_nodes_netsplits},
        {group, three_nodes_netsplits}
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
        {two_nodes_netsplits, [shuffle], [
            two_nodes_netsplit_when_there_are_no_conflicts,
            two_nodes_netsplit_kill_resolution_when_there_are_conflicts,
            two_nodes_netsplit_callback_resolution_when_there_are_conflicts
        ]},
        {three_nodes_netsplits, [shuffle], [
            three_nodes_netsplit_kill_resolution_when_there_are_conflicts
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
    %% init
    SlaveNodeShortName = syn_slave,
    %% start slave
    {ok, SlaveNode} = syn_test_suite_helper:start_slave(SlaveNodeShortName),
    %% config
    [
        {slave_node_short_name, SlaveNodeShortName},
        {slave_node, SlaveNode}
        | Config
    ].

%% -------------------------------------------------------------------
%% Function: end_per_suite(Config0) -> void() | {save_config,Config1}
%% Config0 = Config1 = [tuple()]
%% -------------------------------------------------------------------
end_per_suite(Config) ->
    %% get slave node name
    SlaveNodeShortName = proplists:get_value(slave_node_short_name, Config),
    %% stop slave
    syn_test_suite_helper:stop_slave(SlaveNodeShortName).

%% -------------------------------------------------------------------
%% Function: init_per_group(GroupName, Config0) ->
%%				Config1 | {skip,Reason} |
%%              {skip_and_save,Reason,Config1}
%% GroupName = atom()
%% Config0 = Config1 = [tuple()]
%% Reason = term()
%% -------------------------------------------------------------------
init_per_group(three_nodes_netsplits, Config) ->
    %% init
    SlaveNode2ShortName = syn_slave_2,
    %% start slave 2
    {ok, SlaveNode2} = syn_test_suite_helper:start_slave(SlaveNode2ShortName),
    %% config
    [
        {slave_node_2_short_name, SlaveNode2ShortName},
        {slave_node_2, SlaveNode2}
        | Config
    ];
init_per_group(_GroupName, Config) -> Config.

%% -------------------------------------------------------------------
%% Function: end_per_group(GroupName, Config0) ->
%%				void() | {save_config,Config1}
%% GroupName = atom()
%% Config0 = Config1 = [tuple()]
%% -------------------------------------------------------------------
end_per_group(three_nodes_netsplits, Config) ->
    %% get slave node 2 name
    SlaveNode2ShortName = proplists:get_value(slave_node_2_short_name, Config),
    %% stop slave
    syn_test_suite_helper:stop_slave(SlaveNode2ShortName);
end_per_group(_GroupName, _Config) -> ok.

% ----------------------------------------------------------------------------------------------------------
% Function: init_per_testcase(TestCase, Config0) ->
%				Config1 | {skip,Reason} | {skip_and_save,Reason,Config1}
% TestCase = atom()
% Config0 = Config1 = [tuple()]
% Reason = term()
% ----------------------------------------------------------------------------------------------------------
init_per_testcase(_TestCase, Config) ->
    %% get slave
    SlaveNode = proplists:get_value(slave_node, Config),
    %% set schema location
    application:set_env(mnesia, schema_location, ram),
    rpc:call(SlaveNode, mnesia, schema_location, [ram]),
    %% return
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
two_nodes_netsplit_when_there_are_no_conflicts(Config) ->
    %% get slave
    SlaveNode = proplists:get_value(slave_node, Config),
    CurrentNode = node(),

    %% start syn
    ok = syn:start(),
    ok = syn:init(),
    ok = rpc:call(SlaveNode, syn, start, []),
    ok = rpc:call(SlaveNode, syn, init, []),
    timer:sleep(100),

    %% start processes
    LocalPid = syn_test_suite_helper:start_process(),
    SlavePidLocal = syn_test_suite_helper:start_process(SlaveNode),
    SlavePidSlave = syn_test_suite_helper:start_process(SlaveNode),

    %% register
    ok = syn:register(local_pid, LocalPid),
    ok = syn:register(slave_pid_local, SlavePidLocal),    %% slave registered on local node
    ok = rpc:call(SlaveNode, syn, register, [slave_pid_slave, SlavePidSlave]),    %% slave registered on slave node
    timer:sleep(100),

    %% check tables
    3 = mnesia:table_info(syn_registry_table, size),
    3 = rpc:call(SlaveNode, mnesia, table_info, [syn_registry_table, size]),

    LocalActiveReplicas = mnesia:table_info(syn_registry_table, active_replicas),
    2 = length(LocalActiveReplicas),
    true = lists:member(SlaveNode, LocalActiveReplicas),
    true = lists:member(CurrentNode, LocalActiveReplicas),

    SlaveActiveReplicas = rpc:call(SlaveNode, mnesia, table_info, [syn_registry_table, active_replicas]),
    2 = length(SlaveActiveReplicas),
    true = lists:member(SlaveNode, SlaveActiveReplicas),
    true = lists:member(CurrentNode, SlaveActiveReplicas),

    %% simulate net split
    syn_test_suite_helper:disconnect_node(SlaveNode),
    timer:sleep(1000),

    %% check tables
    1 = mnesia:table_info(syn_registry_table, size),
    [CurrentNode] = mnesia:table_info(syn_registry_table, active_replicas),

    %% reconnect
    syn_test_suite_helper:connect_node(SlaveNode),
    timer:sleep(1000),

    %% check tables
    3 = mnesia:table_info(syn_registry_table, size),
    3 = rpc:call(SlaveNode, mnesia, table_info, [syn_registry_table, size]),

    LocalActiveReplicas2 = mnesia:table_info(syn_registry_table, active_replicas),
    2 = length(LocalActiveReplicas2),
    true = lists:member(SlaveNode, LocalActiveReplicas2),
    true = lists:member(CurrentNode, LocalActiveReplicas2),

    SlaveActiveReplicas2 = rpc:call(SlaveNode, mnesia, table_info, [syn_registry_table, active_replicas]),
    2 = length(SlaveActiveReplicas2),
    true = lists:member(SlaveNode, SlaveActiveReplicas2),
    true = lists:member(CurrentNode, SlaveActiveReplicas2),

    %% check processes
    LocalPid = syn:find_by_key(local_pid),
    SlavePidLocal = syn:find_by_key(slave_pid_local),
    SlavePidSlave = syn:find_by_key(slave_pid_slave),

    LocalPid = rpc:call(SlaveNode, syn, find_by_key, [local_pid]),
    SlavePidLocal = rpc:call(SlaveNode, syn, find_by_key, [slave_pid_local]),
    SlavePidSlave = rpc:call(SlaveNode, syn, find_by_key, [slave_pid_slave]),

    %% kill processes
    syn_test_suite_helper:kill_process(LocalPid),
    syn_test_suite_helper:kill_process(SlavePidLocal),
    syn_test_suite_helper:kill_process(SlavePidSlave).

two_nodes_netsplit_kill_resolution_when_there_are_conflicts(Config) ->
    %% get slave
    SlaveNode = proplists:get_value(slave_node, Config),
    CurrentNode = node(),

    %% start syn
    ok = syn:start(),
    ok = syn:init(),
    ok = rpc:call(SlaveNode, syn, start, []),
    ok = rpc:call(SlaveNode, syn, init, []),
    timer:sleep(100),

    %% start processes
    LocalPid = syn_test_suite_helper:start_process(),
    SlavePid = syn_test_suite_helper:start_process(SlaveNode),

    %% register
    ok = syn:register(conflicting_key, SlavePid),
    timer:sleep(100),

    %% check tables
    1 = mnesia:table_info(syn_registry_table, size),
    1 = rpc:call(SlaveNode, mnesia, table_info, [syn_registry_table, size]),

    %% check process
    SlavePid = syn:find_by_key(conflicting_key),

    %% simulate net split
    syn_test_suite_helper:disconnect_node(SlaveNode),
    timer:sleep(1000),

    %% check tables
    0 = mnesia:table_info(syn_registry_table, size),
    [CurrentNode] = mnesia:table_info(syn_registry_table, active_replicas),

    %% now register the local pid with the same key
    ok = syn:register(conflicting_key, LocalPid),

    %% check process
    LocalPid = syn:find_by_key(conflicting_key),

    %% reconnect
    syn_test_suite_helper:connect_node(SlaveNode),
    timer:sleep(1000),

    %% check tables
    1 = mnesia:table_info(syn_registry_table, size),
    1 = rpc:call(SlaveNode, mnesia, table_info, [syn_registry_table, size]),

    %% check process
    FoundPid = syn:find_by_key(conflicting_key),
    true = lists:member(FoundPid, [LocalPid, SlavePid]),

    %% kill processes
    syn_test_suite_helper:kill_process(LocalPid),
    syn_test_suite_helper:kill_process(SlavePid),

    %% unregister
    global:unregister_name(syn_consistency_SUITE_result).

two_nodes_netsplit_callback_resolution_when_there_are_conflicts(Config) ->
    %% get slave
    SlaveNode = proplists:get_value(slave_node, Config),
    CurrentNode = node(),

    %% load configuration variables from syn-test.config => this sets the registry_conflicting_process_callback option
    syn_test_suite_helper:set_environment_variables(),
    syn_test_suite_helper:set_environment_variables(SlaveNode),

    %% start syn
    ok = syn:start(),
    ok = syn:init(),
    ok = rpc:call(SlaveNode, syn, start, []),
    ok = rpc:call(SlaveNode, syn, init, []),
    timer:sleep(100),

    %% start processes
    LocalPid = syn_test_suite_helper:start_process(fun process_reply_main/0),
    SlavePid = syn_test_suite_helper:start_process(SlaveNode, fun process_reply_main/0),

    %% register global process
    ResultPid = self(),
    global:register_name(syn_consistency_SUITE_result, ResultPid),

    %% register
    Meta = {some, meta, data},
    ok = syn:register(conflicting_key, SlavePid, Meta),
    timer:sleep(100),

    %% check tables
    1 = mnesia:table_info(syn_registry_table, size),
    1 = rpc:call(SlaveNode, mnesia, table_info, [syn_registry_table, size]),

    %% check process
    SlavePid = syn:find_by_key(conflicting_key),

    %% simulate net split
    syn_test_suite_helper:disconnect_node(SlaveNode),
    timer:sleep(1000),

    %% check tables
    0 = mnesia:table_info(syn_registry_table, size),
    [CurrentNode] = mnesia:table_info(syn_registry_table, active_replicas),

    %% now register the local pid with the same key
    ok = syn:register(conflicting_key, LocalPid, Meta),

    %% check process
    LocalPid = syn:find_by_key(conflicting_key),

    %% reconnect
    syn_test_suite_helper:connect_node(SlaveNode),
    timer:sleep(1000),

    %% check tables
    1 = mnesia:table_info(syn_registry_table, size),
    1 = rpc:call(SlaveNode, mnesia, table_info, [syn_registry_table, size]),

    %% check process
    FoundPid = syn:find_by_key(conflicting_key),
    true = lists:member(FoundPid, [LocalPid, SlavePid]),

    %% check message received from killed pid
    KilledPid = lists:nth(1, lists:delete(FoundPid, [LocalPid, SlavePid])),
    receive
        {exited, KilledPid, Meta} -> ok
    after 2000 ->
        ok = conflicting_process_did_not_receive_message
    end,

    %% kill processes
    syn_test_suite_helper:kill_process(LocalPid),
    syn_test_suite_helper:kill_process(SlavePid),

    %% unregister
    global:unregister_name(syn_consistency_SUITE_result).

three_nodes_netsplit_kill_resolution_when_there_are_conflicts(Config) ->
    %% get slaves
    SlaveNode = proplists:get_value(slave_node, Config),
    SlaveNode2 = proplists:get_value(slave_node_2, Config),
    CurrentNode = node(),

    %% start syn
    ok = syn:start(),
    ok = syn:init(),
    ok = rpc:call(SlaveNode, syn, start, []),
    ok = rpc:call(SlaveNode, syn, init, []),
    ok = rpc:call(SlaveNode2, syn, start, []),
    ok = rpc:call(SlaveNode2, syn, init, []),
    timer:sleep(100),

    %% start processes
    LocalPid = syn_test_suite_helper:start_process(),
    SlavePid = syn_test_suite_helper:start_process(SlaveNode),
    Slave2Pid = syn_test_suite_helper:start_process(SlaveNode2),

    %% register
    ok = syn:register(conflicting_key, SlavePid),
    ok = syn:register(slave_2_process, Slave2Pid),
    timer:sleep(100),

    %% check tables
    2 = mnesia:table_info(syn_registry_table, size),
    2 = rpc:call(SlaveNode, mnesia, table_info, [syn_registry_table, size]),
    2 = rpc:call(SlaveNode2, mnesia, table_info, [syn_registry_table, size]),

    %% check process
    SlavePid = syn:find_by_key(conflicting_key),

    %% simulate net split
    syn_test_suite_helper:disconnect_node(SlaveNode),
    timer:sleep(1000),

    %% check tables
    1 = mnesia:table_info(syn_registry_table, size),
    1 = rpc:call(SlaveNode2, mnesia, table_info, [syn_registry_table, size]),

    ActiveReplicaseDuringNetsplit = mnesia:table_info(syn_registry_table, active_replicas),
    true = lists:member(CurrentNode, ActiveReplicaseDuringNetsplit),
    true = lists:member(SlaveNode2, ActiveReplicaseDuringNetsplit),

    %% now register the local pid with the same conflicting key
    ok = syn:register(conflicting_key, LocalPid),

    %% check process
    LocalPid = syn:find_by_key(conflicting_key),

    %% reconnect
    syn_test_suite_helper:connect_node(SlaveNode),
    timer:sleep(1000),

    %% check tables
    2 = mnesia:table_info(syn_registry_table, size),
    2 = rpc:call(SlaveNode, mnesia, table_info, [syn_registry_table, size]),
    2 = rpc:call(SlaveNode2, mnesia, table_info, [syn_registry_table, size]),

    %% check processes
    FoundPid = syn:find_by_key(conflicting_key),
    true = lists:member(FoundPid, [LocalPid, SlavePid]),

    Slave2Pid = syn:find_by_key(slave_2_process),
    Slave2Pid = rpc:call(SlaveNode, syn, find_by_key, [slave_2_process]),
    Slave2Pid = rpc:call(SlaveNode2, syn, find_by_key, [slave_2_process]),

    %% kill processes
    syn_test_suite_helper:kill_process(LocalPid),
    syn_test_suite_helper:kill_process(SlavePid),
    syn_test_suite_helper:kill_process(Slave2Pid).

%% ===================================================================
%% Internal
%% ===================================================================
process_reply_main() ->
    receive
        {shutdown, Meta} ->
            timer:sleep(500), %% wait for global processes to propagate
            global:send(syn_consistency_SUITE_result, {exited, self(), Meta})
    end.

registry_conflicting_process_callback_dummy(_Key, Pid, Meta) ->
    Pid ! {shutdown, Meta}.
