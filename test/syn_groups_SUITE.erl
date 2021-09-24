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
-module(syn_groups_SUITE).

%% callbacks
-export([all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([groups/0, init_per_group/2, end_per_group/2]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% tests
-export([
    three_nodes_discover_default_scope/1,
    three_nodes_discover_custom_scope/1
]).

%% include
-include_lib("common_test/include/ct.hrl").
-include_lib("syn/src/syn.hrl").

%% ===================================================================
%% Callbacks
%% ===================================================================

%% -------------------------------------------------------------------
%% Function: all() -> GroupsAndTestCases | {skip,Reason}
%% GroupsAndTestCases = [{group,GroupName} | TestCase]
%% GroupName = atom()
%% TestCase = atom()
%% Reason = any()
%% -------------------------------------------------------------------
all() ->
    [
        {group, three_nodes_groups}
    ].

%% -------------------------------------------------------------------
%% Function: groups() -> [Group]
%% Group = {GroupName,Properties,GroupsAndTestCases}
%% GroupName =  atom()
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
        {three_nodes_groups, [shuffle], [
            three_nodes_discover_default_scope,
            three_nodes_discover_custom_scope
        ]}
    ].
%% -------------------------------------------------------------------
%% Function: init_per_suite(Config0) ->
%%				Config1 | {skip,Reason} |
%%              {skip_and_save,Reason,Config1}
%% Config0 = Config1 = [tuple()]
%% Reason = any()
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
%% Reason = any()
%% -------------------------------------------------------------------
init_per_group(three_nodes_groups, Config) ->
    %% start slave
    {ok, SlaveNode1} = syn_test_suite_helper:start_slave(syn_slave_1),
    {ok, SlaveNode2} = syn_test_suite_helper:start_slave(syn_slave_2),
    syn_test_suite_helper:connect_node(SlaveNode1),
    syn_test_suite_helper:connect_node(SlaveNode2),
    rpc:call(SlaveNode1, syn_test_suite_helper, connect_node, [SlaveNode2]),
    %% wait full cluster
    case syn_test_suite_helper:wait_cluster_mesh_connected([node(), SlaveNode1, SlaveNode2]) of
        ok ->
            %% config
            [{slave_node_1, SlaveNode1}, {slave_node_2, SlaveNode2} | Config];

        Other ->
            ct:pal("*********** Could not get full cluster, skipping"),
            end_per_group(three_nodes_groups, Config),
            {skip, Other}
    end;

init_per_group(_GroupName, Config) ->
    Config.

%% -------------------------------------------------------------------
%% Function: end_per_group(GroupName, Config0) ->
%%				void() | {save_config,Config1}
%% GroupName = atom()
%% Config0 = Config1 = [tuple()]
%% -------------------------------------------------------------------
end_per_group(three_nodes_groups, Config) ->
    SlaveNode1 = proplists:get_value(slave_node_1, Config),
    syn_test_suite_helper:connect_node(SlaveNode1),
    SlaveNode2 = proplists:get_value(slave_node_2, Config),
    syn_test_suite_helper:connect_node(SlaveNode2),
    syn_test_suite_helper:clean_after_test(),
    syn_test_suite_helper:stop_slave(syn_slave_1),
    syn_test_suite_helper:stop_slave(syn_slave_2),
    timer:sleep(1000);
end_per_group(_GroupName, _Config) ->
    syn_test_suite_helper:clean_after_test().

%% -------------------------------------------------------------------
%% Function: init_per_testcase(TestCase, Config0) ->
%%				Config1 | {skip,Reason} | {skip_and_save,Reason,Config1}
%% TestCase = atom()
%% Config0 = Config1 = [tuple()]
%% Reason = any()
%% -------------------------------------------------------------------
init_per_testcase(TestCase, Config) ->
    ct:pal("Starting test: ~p", [TestCase]),
    Config.

%% -------------------------------------------------------------------
%% Function: end_per_testcase(TestCase, Config0) ->
%%				void() | {save_config,Config1} | {fail,Reason}
%% TestCase = atom()
%% Config0 = Config1 = [tuple()]
%% Reason = any()
%% -------------------------------------------------------------------
end_per_testcase(_, _Config) ->
    syn_test_suite_helper:clean_after_test().

%% ===================================================================
%% Tests
%% ===================================================================
three_nodes_discover_default_scope(Config) ->
    %% get slaves
    SlaveNode1 = proplists:get_value(slave_node_1, Config),
    SlaveNode2 = proplists:get_value(slave_node_2, Config),

    %% start syn on nodes
    ok = syn:start(),
    ok = rpc:call(SlaveNode1, syn, start, []),
    ok = rpc:call(SlaveNode2, syn, start, []),

    %% check
    syn_test_suite_helper:assert_groups_scope_subcluster(node(), default, [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode1, default, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode2, default, [node(), SlaveNode1]),

    %% simulate full netsplit
    rpc:call(SlaveNode1, syn_test_suite_helper, disconnect_node, [SlaveNode2]),
    syn_test_suite_helper:disconnect_node(SlaveNode1),
    syn_test_suite_helper:disconnect_node(SlaveNode2),
    syn_test_suite_helper:assert_cluster(node(), []),

    %% check
    syn_test_suite_helper:assert_groups_scope_subcluster(node(), default, []),

    %% reconnect slave 1
    syn_test_suite_helper:connect_node(SlaveNode1),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node()]),

    %% check
    syn_test_suite_helper:assert_groups_scope_subcluster(node(), default, [SlaveNode1]),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode1, default, [node()]),

    %% reconnect all
    syn_test_suite_helper:connect_node(SlaveNode2),
    rpc:call(SlaveNode1, syn_test_suite_helper, connect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node(), SlaveNode1]),

    %% check
    syn_test_suite_helper:assert_groups_scope_subcluster(node(), default, [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode1, default, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode2, default, [node(), SlaveNode1]),

    %% simulate full netsplit, again
    rpc:call(SlaveNode1, syn_test_suite_helper, disconnect_node, [SlaveNode2]),
    syn_test_suite_helper:disconnect_node(SlaveNode1),
    syn_test_suite_helper:disconnect_node(SlaveNode2),
    syn_test_suite_helper:assert_cluster(node(), []),

    %% check
    syn_test_suite_helper:assert_groups_scope_subcluster(node(), default, []),
    %% reconnect all, again
    syn_test_suite_helper:connect_node(SlaveNode2),
    rpc:call(SlaveNode1, syn_test_suite_helper, connect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node(), SlaveNode1]),

    %% check
    syn_test_suite_helper:assert_groups_scope_subcluster(node(), default, [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode1, default, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode2, default, [node(), SlaveNode1]),

    %% crash the scope process on local
    syn_test_suite_helper:kill_process(syn_registry_default),
    syn_test_suite_helper:wait_process_name_ready(syn_registry_default),

    %% check, it should have rebuilt after supervisor restarts it
    syn_test_suite_helper:assert_groups_scope_subcluster(node(), default, [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode1, default, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode2, default, [node(), SlaveNode1]),

    %% crash scopes supervisor on local
    syn_test_suite_helper:kill_process(syn_scopes_sup),
    syn_test_suite_helper:wait_process_name_ready(syn_registry_default),

    %% check
    syn_test_suite_helper:assert_groups_scope_subcluster(node(), default, [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode1, default, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode2, default, [node(), SlaveNode1]).

three_nodes_discover_custom_scope(Config) ->
    %% get slaves
    SlaveNode1 = proplists:get_value(slave_node_1, Config),
    SlaveNode2 = proplists:get_value(slave_node_2, Config),

    %% start syn on nodes
    ok = syn:start(),
    ok = rpc:call(SlaveNode1, syn, start, []),
    ok = rpc:call(SlaveNode2, syn, start, []),

    %% add custom scopes
    ok = syn:add_node_to_scope(custom_scope_ab),
    ok = syn:add_node_to_scope(custom_scope_all),
    ok = rpc:call(SlaveNode1, syn, add_node_to_scopes, [[custom_scope_ab, custom_scope_bc, custom_scope_all]]),
    ok = rpc:call(SlaveNode2, syn, add_node_to_scopes, [[custom_scope_bc, custom_scope_c, custom_scope_all]]),

    %% get_subcluster_nodes should return invalid errors
    {'EXIT', {{invalid_scope, custom_abcdef}, _}} = catch syn_registry:get_subcluster_nodes(custom_abcdef),

    %% check
    syn_test_suite_helper:assert_groups_scope_subcluster(node(), custom_scope_ab, [SlaveNode1]),
    syn_test_suite_helper:assert_groups_scope_subcluster(node(), custom_scope_all, [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode1, custom_scope_ab, [node()]),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode1, custom_scope_bc, [SlaveNode2]),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode1, custom_scope_all, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode2, custom_scope_bc, [SlaveNode1]),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode2, custom_scope_c, []),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode2, custom_scope_all, [node(), SlaveNode1]),

    %% check default
    syn_test_suite_helper:assert_groups_scope_subcluster(node(), default, [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode1, default, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode2, default, [node(), SlaveNode1]),

    %% disconnect node 2 (node 1 can still see node 2)
    syn_test_suite_helper:disconnect_node(SlaveNode2),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node(), SlaveNode2]),

    %% check
    syn_test_suite_helper:assert_groups_scope_subcluster(node(), custom_scope_ab, [SlaveNode1]),
    syn_test_suite_helper:assert_groups_scope_subcluster(node(), custom_scope_all, [SlaveNode1]),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode1, custom_scope_ab, [node()]),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode1, custom_scope_bc, [SlaveNode2]),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode1, custom_scope_all, [node(), SlaveNode2]),

    %% reconnect node 2
    syn_test_suite_helper:connect_node(SlaveNode2),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node(), SlaveNode1]),

    %% check
    syn_test_suite_helper:assert_groups_scope_subcluster(node(), custom_scope_ab, [SlaveNode1]),
    syn_test_suite_helper:assert_groups_scope_subcluster(node(), custom_scope_all, [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode1, custom_scope_ab, [node()]),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode1, custom_scope_bc, [SlaveNode2]),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode1, custom_scope_all, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode2, custom_scope_bc, [SlaveNode1]),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode2, custom_scope_c, []),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode2, custom_scope_all, [node(), SlaveNode1]),

    %% crash a scope process on 2
    rpc:call(SlaveNode2, syn_test_suite_helper, kill_process, [syn_registry_custom_scope_bc]),
    rpc:call(SlaveNode2, syn_test_suite_helper, wait_process_name_ready, [syn_registry_default]),

    %% check
    syn_test_suite_helper:assert_groups_scope_subcluster(node(), custom_scope_ab, [SlaveNode1]),
    syn_test_suite_helper:assert_groups_scope_subcluster(node(), custom_scope_all, [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode1, custom_scope_ab, [node()]),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode1, custom_scope_bc, [SlaveNode2]),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode1, custom_scope_all, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode2, custom_scope_bc, [SlaveNode1]),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode2, custom_scope_c, []),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode2, custom_scope_all, [node(), SlaveNode1]),

    %% crash scopes supervisor on local
    syn_test_suite_helper:kill_process(syn_scopes_sup),
    syn_test_suite_helper:wait_process_name_ready(syn_registry_default),

    %% check
    syn_test_suite_helper:assert_groups_scope_subcluster(node(), custom_scope_ab, [SlaveNode1]),
    syn_test_suite_helper:assert_groups_scope_subcluster(node(), custom_scope_all, [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode1, custom_scope_ab, [node()]),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode1, custom_scope_bc, [SlaveNode2]),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode1, custom_scope_all, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode2, custom_scope_bc, [SlaveNode1]),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode2, custom_scope_c, []),
    syn_test_suite_helper:assert_groups_scope_subcluster(SlaveNode2, custom_scope_all, [node(), SlaveNode1]).
