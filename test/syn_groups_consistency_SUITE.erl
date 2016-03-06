%% ==========================================================================================================
%% Syn - A global Process Registry and Process Group manager.
%%
%% The MIT License (MIT)
%%
%% Copyright (c) 2016 Roberto Ostinelli <roberto@ostinelli.net> and Neato Robotics, Inc.
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
-module(syn_groups_consistency_SUITE).

%% callbacks
-export([all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([groups/0, init_per_group/2, end_per_group/2]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% tests
-export([
    two_nodes_netsplit_when_there_are_no_conflicts/1
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
        {group, two_nodes_netsplits}
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
            two_nodes_netsplit_when_there_are_no_conflicts
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
init_per_group(_GroupName, Config) -> Config.

%% -------------------------------------------------------------------
%% Function: end_per_group(GroupName, Config0) ->
%%				void() | {save_config,Config1}
%% GroupName = atom()
%% Config0 = Config1 = [tuple()]
%% -------------------------------------------------------------------
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

    %% set schema location
    application:set_env(mnesia, schema_location, ram),
    rpc:call(SlaveNode, mnesia, schema_location, [ram]),

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

    %% join
    ok = syn:join({group, tuple_name}, LocalPid),
    ok = syn:join({group, tuple_name}, SlavePidLocal),    %% joined on local node
    ok = rpc:call(SlaveNode, syn, join, [{group, tuple_name}, SlavePidSlave]),    %% joined on slave node
    timer:sleep(100),

    %% check tables
    3 = mnesia:table_info(syn_groups_table, size),
    3 = rpc:call(SlaveNode, mnesia, table_info, [syn_groups_table, size]),

    LocalActiveReplicas = mnesia:table_info(syn_groups_table, active_replicas),
    2 = length(LocalActiveReplicas),
    true = lists:member(SlaveNode, LocalActiveReplicas),
    true = lists:member(CurrentNode, LocalActiveReplicas),

    SlaveActiveReplicas = rpc:call(SlaveNode, mnesia, table_info, [syn_groups_table, active_replicas]),
    2 = length(SlaveActiveReplicas),
    true = lists:member(SlaveNode, SlaveActiveReplicas),
    true = lists:member(CurrentNode, SlaveActiveReplicas),

    %% simulate net split
    syn_test_suite_helper:disconnect_node(SlaveNode),
    timer:sleep(1000),

    %% check tables
    1 = mnesia:table_info(syn_groups_table, size),
    [CurrentNode] = mnesia:table_info(syn_groups_table, active_replicas),

    %% reconnect
    syn_test_suite_helper:connect_node(SlaveNode),
    timer:sleep(1000),

    %% check tables
    3 = mnesia:table_info(syn_groups_table, size),
    3 = rpc:call(SlaveNode, mnesia, table_info, [syn_groups_table, size]),

    LocalActiveReplicasAfter = mnesia:table_info(syn_groups_table, active_replicas),
    2 = length(LocalActiveReplicasAfter),
    true = lists:member(SlaveNode, LocalActiveReplicasAfter),
    true = lists:member(CurrentNode, LocalActiveReplicasAfter),

    SlaveActiveReplicasAfter = rpc:call(SlaveNode, mnesia, table_info, [syn_groups_table, active_replicas]),
    2 = length(SlaveActiveReplicasAfter),
    true = lists:member(SlaveNode, SlaveActiveReplicasAfter),
    true = lists:member(CurrentNode, SlaveActiveReplicasAfter),

    %% check grouos
    3 = length(syn:get_members({group, tuple_name})),
    true = syn:member(LocalPid, {group, tuple_name}),
    true = syn:member(SlavePidLocal, {group, tuple_name}),
    true = syn:member(SlavePidSlave, {group, tuple_name}),
    3 = length(rpc:call(SlaveNode, syn, get_members, [{group, tuple_name}])),
    true = rpc:call(SlaveNode, syn, member, [LocalPid, {group, tuple_name}]),
    true = rpc:call(SlaveNode, syn, member, [SlavePidLocal, {group, tuple_name}]),
    true = rpc:call(SlaveNode, syn, member, [SlavePidSlave, {group, tuple_name}]).
