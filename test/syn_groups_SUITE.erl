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
    three_nodes_discover_custom_scope/1,
    three_nodes_join_leave_and_monitor_default_scope/1,
    three_nodes_join_leave_and_monitor_custom_scope/1,
    three_nodes_cluster_changes/1,
    three_nodes_custom_event_handler_joined_left/1,
    three_nodes_publish_default_scope/1,
    three_nodes_publish_custom_scope/1,
    three_nodes_multi_call_default_scope/1,
    three_nodes_multi_call_custom_scope/1,
    three_nodes_group_names_default_scope/1,
    three_nodes_group_names_custom_scope/1
]).

%% internals
-export([
    subscriber_loop/2,
    recipient_loop/0
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
            three_nodes_discover_custom_scope,
            three_nodes_join_leave_and_monitor_default_scope,
            three_nodes_join_leave_and_monitor_custom_scope,
            three_nodes_cluster_changes,
            three_nodes_custom_event_handler_joined_left,
            three_nodes_publish_default_scope,
            three_nodes_publish_custom_scope,
            three_nodes_multi_call_default_scope,
            three_nodes_multi_call_custom_scope,
            three_nodes_group_names_default_scope,
            three_nodes_group_names_custom_scope
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

three_nodes_join_leave_and_monitor_default_scope(Config) ->
    %% get slaves
    SlaveNode1 = proplists:get_value(slave_node_1, Config),
    SlaveNode2 = proplists:get_value(slave_node_2, Config),

    %% start syn on nodes
    ok = syn:start(),
    ok = rpc:call(SlaveNode1, syn, start, []),
    ok = rpc:call(SlaveNode2, syn, start, []),

    %% start processes
    Pid = syn_test_suite_helper:start_process(),
    PidWithMeta = syn_test_suite_helper:start_process(),
    PidRemoteOn1 = syn_test_suite_helper:start_process(SlaveNode1),

    %% check
    [] = syn:members({group, "one"}),
    [] = rpc:call(SlaveNode1, syn, members, [{group, "one"}]),
    [] = rpc:call(SlaveNode2, syn, members, [{group, "one"}]),
    false = syn:is_member({group, "one"}, Pid),
    false = syn:is_member({group, "one"}, PidWithMeta),
    false = syn:is_member({group, "one"}, PidRemoteOn1),
    false = rpc:call(SlaveNode1, syn, is_member, [{group, "one"}, Pid]),
    false = rpc:call(SlaveNode1, syn, is_member, [{group, "one"}, PidWithMeta]),
    false = rpc:call(SlaveNode1, syn, is_member, [{group, "one"}, PidRemoteOn1]),
    false = rpc:call(SlaveNode2, syn, is_member, [{group, "one"}, Pid]),
    false = rpc:call(SlaveNode2, syn, is_member, [{group, "one"}, PidWithMeta]),
    false = rpc:call(SlaveNode2, syn, is_member, [{group, "one"}, PidRemoteOn1]),

    [] = syn:members({group, "two"}),
    [] = rpc:call(SlaveNode1, syn, members, [{group, "two"}]),
    [] = rpc:call(SlaveNode2, syn, members, [{group, "two"}]),
    false = syn:is_member({group, "two"}, Pid),
    false = syn:is_member({group, "two"}, PidWithMeta),
    false = syn:is_member({group, "two"}, PidRemoteOn1),
    false = rpc:call(SlaveNode1, syn, is_member, [{group, "two"}, Pid]),
    false = rpc:call(SlaveNode1, syn, is_member, [{group, "two"}, PidWithMeta]),
    false = rpc:call(SlaveNode1, syn, is_member, [{group, "two"}, PidRemoteOn1]),
    false = rpc:call(SlaveNode2, syn, is_member, [{group, "two"}, Pid]),
    false = rpc:call(SlaveNode2, syn, is_member, [{group, "two"}, PidWithMeta]),
    false = rpc:call(SlaveNode2, syn, is_member, [{group, "two"}, PidRemoteOn1]),

    [] = syn:local_members({group, "one"}),
    [] = rpc:call(SlaveNode1, syn, local_members, [{group, "one"}]),
    [] = rpc:call(SlaveNode2, syn, local_members, [{group, "one"}]),
    false = syn:is_local_member({group, "one"}, Pid),
    false = syn:is_local_member({group, "one"}, PidWithMeta),
    false = syn:is_local_member({group, "one"}, PidRemoteOn1),
    false = rpc:call(SlaveNode1, syn, is_local_member, [{group, "one"}, Pid]),
    false = rpc:call(SlaveNode1, syn, is_local_member, [{group, "one"}, PidWithMeta]),
    false = rpc:call(SlaveNode1, syn, is_local_member, [{group, "one"}, PidRemoteOn1]),
    false = rpc:call(SlaveNode2, syn, is_local_member, [{group, "one"}, Pid]),
    false = rpc:call(SlaveNode2, syn, is_local_member, [{group, "one"}, PidWithMeta]),
    false = rpc:call(SlaveNode2, syn, is_local_member, [{group, "one"}, PidRemoteOn1]),

    [] = syn:local_members({group, "two"}),
    [] = rpc:call(SlaveNode1, syn, local_members, [{group, "two"}]),
    [] = rpc:call(SlaveNode2, syn, local_members, [{group, "two"}]),
    false = syn:is_local_member({group, "two"}, Pid),
    false = syn:is_local_member({group, "two"}, PidWithMeta),
    false = syn:is_local_member({group, "two"}, PidRemoteOn1),
    false = rpc:call(SlaveNode1, syn, is_local_member, [{group, "two"}, Pid]),
    false = rpc:call(SlaveNode1, syn, is_local_member, [{group, "two"}, PidWithMeta]),
    false = rpc:call(SlaveNode1, syn, is_local_member, [{group, "two"}, PidRemoteOn1]),
    false = rpc:call(SlaveNode2, syn, is_local_member, [{group, "two"}, Pid]),
    false = rpc:call(SlaveNode2, syn, is_local_member, [{group, "two"}, PidWithMeta]),
    false = rpc:call(SlaveNode2, syn, is_local_member, [{group, "two"}, PidRemoteOn1]),

    0 = syn:group_count(),
    0 = syn:group_count(default, node()),
    0 = syn:group_count(default, SlaveNode1),
    0 = syn:group_count(default, SlaveNode2),

    %% join
    ok = syn:join({group, "one"}, Pid),
    ok = syn:join({group, "one"}, PidWithMeta, <<"with meta">>),
    ok = syn:join({group, "one"}, PidRemoteOn1),
    ok = syn:join({group, "two"}, Pid),
    ok = syn:join({group, "two"}, PidWithMeta, "with-meta-2"),

    %% errors
    {error, not_alive} = syn:join({"pid not alive"}, list_to_pid("<0.9999.0>")),
    {error, not_in_group} = syn:leave({group, "three"}, Pid),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, <<"with meta">>}, {PidRemoteOn1, undefined}]),
        fun() -> lists:sort(syn:members({group, "one"})) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, <<"with meta">>}, {PidRemoteOn1, undefined}]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [{group, "one"}])) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, <<"with meta">>}, {PidRemoteOn1, undefined}]),
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, members, [{group, "one"}])) end
    ),
    true = syn:is_member({group, "one"}, Pid),
    true = syn:is_member({group, "one"}, PidWithMeta),
    true = syn:is_member({group, "one"}, PidRemoteOn1),
    true = rpc:call(SlaveNode1, syn, is_member, [{group, "one"}, Pid]),
    true = rpc:call(SlaveNode1, syn, is_member, [{group, "one"}, PidWithMeta]),
    true = rpc:call(SlaveNode1, syn, is_member, [{group, "one"}, PidRemoteOn1]),
    true = rpc:call(SlaveNode2, syn, is_member, [{group, "one"}, Pid]),
    true = rpc:call(SlaveNode2, syn, is_member, [{group, "one"}, PidWithMeta]),
    true = rpc:call(SlaveNode2, syn, is_member, [{group, "one"}, PidRemoteOn1]),

    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, <<"with meta">>}]),
        fun() -> lists:sort(syn:local_members({group, "one"})) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn1, undefined}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [{group, "one"}])) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, local_members, [{group, "one"}])) end
    ),
    true = syn:is_local_member({group, "one"}, Pid),
    true = syn:is_local_member({group, "one"}, PidWithMeta),
    false = syn:is_local_member({group, "one"}, PidRemoteOn1),
    false = rpc:call(SlaveNode1, syn, is_local_member, [{group, "one"}, Pid]),
    false = rpc:call(SlaveNode1, syn, is_local_member, [{group, "one"}, PidWithMeta]),
    true = rpc:call(SlaveNode1, syn, is_local_member, [{group, "one"}, PidRemoteOn1]),
    false = rpc:call(SlaveNode2, syn, is_local_member, [{group, "one"}, Pid]),
    false = rpc:call(SlaveNode2, syn, is_local_member, [{group, "one"}, PidWithMeta]),
    false = rpc:call(SlaveNode2, syn, is_local_member, [{group, "one"}, PidRemoteOn1]),

    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, "with-meta-2"}]),
        fun() -> lists:sort(syn:members({group, "two"})) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, "with-meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [{group, "two"}])) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, "with-meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, members, [{group, "two"}])) end
    ),
    true = syn:is_member({group, "two"}, Pid),
    true = syn:is_member({group, "two"}, PidWithMeta),
    false = syn:is_member({group, "two"}, PidRemoteOn1),
    true = rpc:call(SlaveNode1, syn, is_member, [{group, "two"}, Pid]),
    true = rpc:call(SlaveNode1, syn, is_member, [{group, "two"}, PidWithMeta]),
    false = rpc:call(SlaveNode1, syn, is_member, [{group, "two"}, PidRemoteOn1]),
    true = rpc:call(SlaveNode2, syn, is_member, [{group, "two"}, Pid]),
    true = rpc:call(SlaveNode2, syn, is_member, [{group, "two"}, PidWithMeta]),
    false = rpc:call(SlaveNode2, syn, is_member, [{group, "two"}, PidRemoteOn1]),

    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, "with-meta-2"}]),
        fun() -> lists:sort(syn:local_members({group, "two"})) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [{group, "two"}])) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, local_members, [{group, "two"}])) end
    ),
    true = syn:is_local_member({group, "two"}, Pid),
    true = syn:is_local_member({group, "two"}, PidWithMeta),
    false = syn:is_local_member({group, "two"}, PidRemoteOn1),
    false = rpc:call(SlaveNode1, syn, is_local_member, [{group, "two"}, Pid]),
    false = rpc:call(SlaveNode1, syn, is_local_member, [{group, "two"}, PidWithMeta]),
    false = rpc:call(SlaveNode1, syn, is_local_member, [{group, "two"}, PidRemoteOn1]),
    false = rpc:call(SlaveNode2, syn, is_local_member, [{group, "two"}, Pid]),
    false = rpc:call(SlaveNode2, syn, is_local_member, [{group, "two"}, PidWithMeta]),
    false = rpc:call(SlaveNode2, syn, is_local_member, [{group, "two"}, PidRemoteOn1]),

    2 = syn:group_count(),
    2 = syn:group_count(default, node()),
    1 = syn:group_count(default, SlaveNode1),
    0 = syn:group_count(default, SlaveNode2),

    %% re-join to edit meta
    ok = syn:join({group, "one"}, PidWithMeta, <<"with updated meta">>),
    ok = rpc:call(SlaveNode2, syn, join, [{group, "one"}, PidRemoteOn1, added_meta]), %% updated on slave 2

    %% retrieve
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, <<"with updated meta">>}, {PidRemoteOn1, added_meta}]),
        fun() -> lists:sort(syn:members({group, "one"})) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, <<"with updated meta">>}, {PidRemoteOn1, added_meta}]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [{group, "one"}])) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, <<"with updated meta">>}, {PidRemoteOn1, added_meta}]),
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, members, [{group, "one"}])) end
    ),

    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, <<"with updated meta">>}]),
        fun() -> lists:sort(syn:local_members({group, "one"})) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn1, added_meta}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [{group, "one"}])) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, local_members, [{group, "one"}])) end
    ),

    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, "with-meta-2"}]),
        fun() -> lists:sort(syn:members({group, "two"})) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, "with-meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [{group, "two"}])) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, "with-meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, members, [{group, "two"}])) end
    ),

    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, "with-meta-2"}]),
        fun() -> lists:sort(syn:local_members({group, "two"})) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [{group, "two"}])) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, local_members, [{group, "two"}])) end
    ),

    2 = syn:group_count(),
    2 = syn:group_count(default, node()),
    1 = syn:group_count(default, SlaveNode1),
    0 = syn:group_count(default, SlaveNode2),

    %% crash scope process to ensure that monitors get recreated
    exit(whereis(syn_groups_default), kill),
    syn_test_suite_helper:wait_process_name_ready(syn_groups_default),

    %% kill process
    syn_test_suite_helper:kill_process(Pid),
    syn_test_suite_helper:kill_process(PidRemoteOn1),
    %% leave
    ok = syn:leave({group, "one"}, PidWithMeta),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(syn:members({group, "one"})) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [{group, "one"}])) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, members, [{group, "one"}])) end
    ),
    false = syn:is_member({group, "one"}, Pid),
    false = syn:is_member({group, "one"}, PidWithMeta),
    false = syn:is_member({group, "one"}, PidRemoteOn1),
    false = rpc:call(SlaveNode1, syn, is_member, [{group, "one"}, Pid]),
    false = rpc:call(SlaveNode1, syn, is_member, [{group, "one"}, PidWithMeta]),
    false = rpc:call(SlaveNode1, syn, is_member, [{group, "one"}, PidRemoteOn1]),
    false = rpc:call(SlaveNode2, syn, is_member, [{group, "one"}, Pid]),
    false = rpc:call(SlaveNode2, syn, is_member, [{group, "one"}, PidWithMeta]),
    false = rpc:call(SlaveNode2, syn, is_member, [{group, "one"}, PidRemoteOn1]),

    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(syn:local_members({group, "one"})) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [{group, "one"}])) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, local_members, [{group, "one"}])) end
    ),
    false = syn:is_local_member({group, "one"}, Pid),
    false = syn:is_local_member({group, "one"}, PidWithMeta),
    false = syn:is_local_member({group, "one"}, PidRemoteOn1),
    false = rpc:call(SlaveNode1, syn, is_local_member, [{group, "one"}, Pid]),
    false = rpc:call(SlaveNode1, syn, is_local_member, [{group, "one"}, PidWithMeta]),
    false = rpc:call(SlaveNode1, syn, is_local_member, [{group, "one"}, PidRemoteOn1]),
    false = rpc:call(SlaveNode2, syn, is_local_member, [{group, "one"}, Pid]),
    false = rpc:call(SlaveNode2, syn, is_local_member, [{group, "one"}, PidWithMeta]),
    false = rpc:call(SlaveNode2, syn, is_local_member, [{group, "one"}, PidRemoteOn1]),

    syn_test_suite_helper:assert_wait(
        [{PidWithMeta, "with-meta-2"}],
        fun() -> lists:sort(syn:members({group, "two"})) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidWithMeta, "with-meta-2"}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [{group, "two"}])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidWithMeta, "with-meta-2"}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, members, [{group, "two"}])) end
    ),
    false = syn:is_member({group, "two"}, Pid),
    true = syn:is_member({group, "two"}, PidWithMeta),
    false = syn:is_member({group, "two"}, PidRemoteOn1),
    false = rpc:call(SlaveNode1, syn, is_member, [{group, "two"}, Pid]),
    true = rpc:call(SlaveNode1, syn, is_member, [{group, "two"}, PidWithMeta]),
    false = rpc:call(SlaveNode1, syn, is_member, [{group, "two"}, PidRemoteOn1]),
    false = rpc:call(SlaveNode2, syn, is_member, [{group, "two"}, Pid]),
    true = rpc:call(SlaveNode2, syn, is_member, [{group, "two"}, PidWithMeta]),
    false = rpc:call(SlaveNode2, syn, is_member, [{group, "two"}, PidRemoteOn1]),

    syn_test_suite_helper:assert_wait(
        [{PidWithMeta, "with-meta-2"}],
        fun() -> lists:sort(syn:local_members({group, "two"})) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [{group, "two"}])) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, local_members, [{group, "two"}])) end
    ),
    false = syn:is_local_member({group, "two"}, Pid),
    true = syn:is_local_member({group, "two"}, PidWithMeta),
    false = syn:is_local_member({group, "two"}, PidRemoteOn1),
    false = rpc:call(SlaveNode1, syn, is_local_member, [{group, "two"}, Pid]),
    false = rpc:call(SlaveNode1, syn, is_local_member, [{group, "two"}, PidWithMeta]),
    false = rpc:call(SlaveNode1, syn, is_local_member, [{group, "two"}, PidRemoteOn1]),
    false = rpc:call(SlaveNode2, syn, is_local_member, [{group, "two"}, Pid]),
    false = rpc:call(SlaveNode2, syn, is_local_member, [{group, "two"}, PidWithMeta]),
    false = rpc:call(SlaveNode2, syn, is_local_member, [{group, "two"}, PidRemoteOn1]),

    1 = syn:group_count(),
    1 = syn:group_count(default, node()),
    0 = syn:group_count(default, SlaveNode1),
    0 = syn:group_count(default, SlaveNode2),

    %% errors
    {error, not_in_group} = syn:leave({group, "one"}, PidWithMeta).

three_nodes_join_leave_and_monitor_custom_scope(Config) ->
    %% get slaves
    SlaveNode1 = proplists:get_value(slave_node_1, Config),
    SlaveNode2 = proplists:get_value(slave_node_2, Config),

    %% start syn on nodes
    ok = syn:start(),
    ok = rpc:call(SlaveNode1, syn, start, []),
    ok = rpc:call(SlaveNode2, syn, start, []),

    %% add custom scopes
    ok = syn:add_node_to_scope(custom_scope_ab),
    ok = rpc:call(SlaveNode1, syn, add_node_to_scopes, [[custom_scope_ab, custom_scope_bc]]),
    ok = rpc:call(SlaveNode2, syn, add_node_to_scopes, [[custom_scope_bc]]),

    %% start processes
    Pid = syn_test_suite_helper:start_process(),
    PidWithMeta = syn_test_suite_helper:start_process(),
    PidRemoteOn1 = syn_test_suite_helper:start_process(SlaveNode1),
    PidRemoteOn2 = syn_test_suite_helper:start_process(SlaveNode2),

    %% check
    [] = syn:members(custom_scope_ab, {group, "one"}),
    [] = rpc:call(SlaveNode1, syn, members, [custom_scope_ab, {group, "one"}]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, members, [custom_scope_ab, {group, "one"}]),
    false = syn:is_member(custom_scope_ab, {group, "one"}, Pid),
    false = syn:is_member(custom_scope_ab, {group, "one"}, PidWithMeta),
    false = syn:is_member(custom_scope_ab, {group, "one"}, PidRemoteOn1),
    false = rpc:call(SlaveNode1, syn, is_member, [custom_scope_ab, {group, "one"}, Pid]),
    false = rpc:call(SlaveNode1, syn, is_member, [custom_scope_ab, {group, "one"}, PidWithMeta]),
    false = rpc:call(SlaveNode1, syn, is_member, [custom_scope_ab, {group, "one"}, PidRemoteOn1]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, is_member, [custom_scope_ab, {group, "one"}, Pid]),

    [] = syn:local_members(custom_scope_ab, {group, "one"}),
    [] = rpc:call(SlaveNode1, syn, local_members, [custom_scope_ab, {group, "one"}]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, local_members, [custom_scope_ab, {group, "one"}]),
    false = syn:is_local_member(custom_scope_ab, {group, "one"}, Pid),
    false = syn:is_local_member(custom_scope_ab, {group, "one"}, PidWithMeta),
    false = syn:is_local_member(custom_scope_ab, {group, "one"}, PidRemoteOn1),
    false = rpc:call(SlaveNode1, syn, is_local_member, [custom_scope_ab, {group, "one"}, Pid]),
    false = rpc:call(SlaveNode1, syn, is_local_member, [custom_scope_ab, {group, "one"}, PidWithMeta]),
    false = rpc:call(SlaveNode1, syn, is_local_member, [custom_scope_ab, {group, "one"}, PidRemoteOn1]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, is_local_member, [custom_scope_ab, {group, "one"}, Pid]),

    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:members(custom_scope_bc, {group, "one"}),
    [] = rpc:call(SlaveNode1, syn, members, [custom_scope_bc, {group, "one"}]),
    [] = rpc:call(SlaveNode2, syn, members, [custom_scope_bc, {group, "one"}]),

    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:local_members(custom_scope_bc, {group, "one"}),
    [] = rpc:call(SlaveNode1, syn, local_members, [custom_scope_bc, {group, "one"}]),
    [] = rpc:call(SlaveNode2, syn, local_members, [custom_scope_bc, {group, "one"}]),

    [] = syn:members(custom_scope_ab, {group, "two"}),
    [] = rpc:call(SlaveNode1, syn, members, [custom_scope_ab, {group, "two"}]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, members, [custom_scope_ab, {group, "two"}]),
    false = syn:is_member(custom_scope_ab, {group, "two"}, Pid),
    false = syn:is_member(custom_scope_ab, {group, "two"}, PidWithMeta),
    false = syn:is_member(custom_scope_ab, {group, "two"}, PidRemoteOn1),
    false = rpc:call(SlaveNode1, syn, is_member, [custom_scope_ab, {group, "two"}, Pid]),
    false = rpc:call(SlaveNode1, syn, is_member, [custom_scope_ab, {group, "two"}, PidWithMeta]),
    false = rpc:call(SlaveNode1, syn, is_member, [custom_scope_ab, {group, "two"}, PidRemoteOn1]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, is_member, [custom_scope_ab, {group, "two"}, Pid]),

    [] = syn:local_members(custom_scope_ab, {group, "two"}),
    [] = rpc:call(SlaveNode1, syn, local_members, [custom_scope_ab, {group, "two"}]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, local_members, [custom_scope_ab, {group, "two"}]),
    false = syn:is_local_member(custom_scope_ab, {group, "two"}, Pid),
    false = syn:is_local_member(custom_scope_ab, {group, "two"}, PidWithMeta),
    false = syn:is_local_member(custom_scope_ab, {group, "two"}, PidRemoteOn1),
    false = rpc:call(SlaveNode1, syn, is_local_member, [custom_scope_ab, {group, "two"}, Pid]),
    false = rpc:call(SlaveNode1, syn, is_local_member, [custom_scope_ab, {group, "two"}, PidWithMeta]),
    false = rpc:call(SlaveNode1, syn, is_local_member, [custom_scope_ab, {group, "two"}, PidRemoteOn1]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, is_local_member, [custom_scope_ab, {group, "two"}, Pid]),

    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:members(custom_scope_bc, {group, "two"}),
    [] = rpc:call(SlaveNode1, syn, members, [custom_scope_bc, {group, "two"}]),
    [] = rpc:call(SlaveNode2, syn, members, [custom_scope_bc, {group, "two"}]),

    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:local_members(custom_scope_bc, {group, "two"}),
    [] = rpc:call(SlaveNode1, syn, local_members, [custom_scope_bc, {group, "two"}]),
    [] = rpc:call(SlaveNode2, syn, local_members, [custom_scope_bc, {group, "two"}]),

    %% join
    ok = syn:join(custom_scope_ab, {group, "one"}, Pid),
    ok = syn:join(custom_scope_ab, {group, "one"}, PidWithMeta, <<"with meta">>),
    ok = rpc:call(SlaveNode1, syn, join, [custom_scope_bc, {group, "two"}, PidRemoteOn1]),
    ok = syn:join(custom_scope_ab, {group, "two"}, Pid),
    ok = syn:join(custom_scope_ab, {group, "two"}, PidWithMeta, "with-meta-2"),

    %% errors
    {error, not_alive} = syn:join({"pid not alive"}, list_to_pid("<0.9999.0>")),
    {error, not_in_group} = syn:leave({group, "three"}, Pid),
    {'EXIT', {{invalid_scope, custom_scope_ab}, _}} = catch syn:join(custom_scope_ab, {group, "one"}, PidRemoteOn2),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, <<"with meta">>}]),
        fun() -> lists:sort(syn:members(custom_scope_ab, {group, "one"})) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, <<"with meta">>}]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [custom_scope_ab, {group, "one"}])) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, members, [custom_scope_ab, {group, "one"}]),
    true = syn:is_member(custom_scope_ab, {group, "one"}, Pid),
    true = syn:is_member(custom_scope_ab, {group, "one"}, PidWithMeta),
    false = syn:is_member(custom_scope_ab, {group, "one"}, PidRemoteOn1),
    true = rpc:call(SlaveNode1, syn, is_member, [custom_scope_ab, {group, "one"}, Pid]),
    true = rpc:call(SlaveNode1, syn, is_member, [custom_scope_ab, {group, "one"}, PidWithMeta]),
    false = rpc:call(SlaveNode1, syn, is_member, [custom_scope_ab, {group, "one"}, PidRemoteOn1]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, is_member, [custom_scope_ab, {group, "one"}, Pid]),

    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, <<"with meta">>}]),
        fun() -> lists:sort(syn:local_members(custom_scope_ab, {group, "one"})) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [custom_scope_ab, {group, "one"}])) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, local_members, [custom_scope_ab, {group, "one"}]),
    true = syn:is_local_member(custom_scope_ab, {group, "one"}, Pid),
    true = syn:is_local_member(custom_scope_ab, {group, "one"}, PidWithMeta),
    false = syn:is_local_member(custom_scope_ab, {group, "one"}, PidRemoteOn1),
    false = rpc:call(SlaveNode1, syn, is_local_member, [custom_scope_ab, {group, "one"}, Pid]),
    false = rpc:call(SlaveNode1, syn, is_local_member, [custom_scope_ab, {group, "one"}, PidWithMeta]),
    false = rpc:call(SlaveNode1, syn, is_local_member, [custom_scope_ab, {group, "one"}, PidRemoteOn1]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, is_local_member, [custom_scope_ab, {group, "one"}, Pid]),

    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, "with-meta-2"}]),
        fun() -> lists:sort(syn:members(custom_scope_ab, {group, "two"})) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, "with-meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [custom_scope_ab, {group, "two"}])) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, members, [custom_scope_ab, {group, "two"}]),
    true = syn:is_member(custom_scope_ab, {group, "two"}, Pid),
    true = syn:is_member(custom_scope_ab, {group, "two"}, PidWithMeta),
    false = syn:is_member(custom_scope_ab, {group, "two"}, PidRemoteOn1),
    true = rpc:call(SlaveNode1, syn, is_member, [custom_scope_ab, {group, "two"}, Pid]),
    true = rpc:call(SlaveNode1, syn, is_member, [custom_scope_ab, {group, "two"}, PidWithMeta]),
    false = rpc:call(SlaveNode1, syn, is_member, [custom_scope_ab, {group, "two"}, PidRemoteOn1]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, is_member, [custom_scope_ab, {group, "two"}, Pid]),

    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, "with-meta-2"}]),
        fun() -> lists:sort(syn:local_members(custom_scope_ab, {group, "two"})) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [custom_scope_ab, {group, "two"}])) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, local_members, [custom_scope_ab, {group, "two"}]),
    true = syn:is_local_member(custom_scope_ab, {group, "two"}, Pid),
    true = syn:is_local_member(custom_scope_ab, {group, "two"}, PidWithMeta),
    false = syn:is_local_member(custom_scope_ab, {group, "two"}, PidRemoteOn1),
    false = rpc:call(SlaveNode1, syn, is_local_member, [custom_scope_ab, {group, "two"}, Pid]),
    false = rpc:call(SlaveNode1, syn, is_local_member, [custom_scope_ab, {group, "two"}, PidWithMeta]),
    false = rpc:call(SlaveNode1, syn, is_local_member, [custom_scope_ab, {group, "two"}, PidRemoteOn1]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, is_local_member, [custom_scope_ab, {group, "two"}, Pid]),

    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:members(custom_scope_bc, {group, "two"}),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn1, undefined}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [custom_scope_bc, {group, "two"}])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn1, undefined}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, members, [custom_scope_bc, {group, "two"}])) end
    ),

    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:local_members(custom_scope_bc, {group, "two"}),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn1, undefined}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [custom_scope_bc, {group, "two"}])) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, local_members, [custom_scope_bc, {group, "two"}])) end
    ),

    2 = syn:group_count(custom_scope_ab),
    2 = syn:group_count(custom_scope_ab, node()),
    0 = syn:group_count(custom_scope_ab, SlaveNode1),
    0 = syn:group_count(custom_scope_ab, SlaveNode2),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:group_count(custom_scope_bc),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:group_count(custom_scope_bc, node()),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:group_count(custom_scope_bc, SlaveNode1),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:group_count(custom_scope_bc, SlaveNode2),
    2 = rpc:call(SlaveNode1, syn, group_count, [custom_scope_ab]),
    2 = rpc:call(SlaveNode1, syn, group_count, [custom_scope_ab, node()]),
    0 = rpc:call(SlaveNode1, syn, group_count, [custom_scope_ab, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, group_count, [custom_scope_ab, SlaveNode2]),
    1 = rpc:call(SlaveNode1, syn, group_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode1, syn, group_count, [custom_scope_bc, node()]),
    1 = rpc:call(SlaveNode1, syn, group_count, [custom_scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, group_count, [custom_scope_bc, SlaveNode2]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, group_count, [custom_scope_ab]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, group_count, [custom_scope_ab, node()]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, group_count, [custom_scope_ab, SlaveNode1]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, group_count, [custom_scope_ab, SlaveNode2]),
    1 = rpc:call(SlaveNode2, syn, group_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode2, syn, group_count, [custom_scope_bc, node()]),
    1 = rpc:call(SlaveNode2, syn, group_count, [custom_scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode2, syn, group_count, [custom_scope_bc, SlaveNode2]),

    %% re-join to edit meta
    ok = syn:join(custom_scope_ab, {group, "one"}, PidWithMeta, <<"with updated meta">>),
    ok = rpc:call(SlaveNode2, syn, join, [custom_scope_bc, {group, "two"}, PidRemoteOn1, added_meta]), %% updated on slave 2

    %% retrieve
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, <<"with updated meta">>}]),
        fun() -> lists:sort(syn:members(custom_scope_ab, {group, "one"})) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, <<"with updated meta">>}]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [custom_scope_ab, {group, "one"}])) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, members, [custom_scope_ab, {group, "one"}]),

    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, <<"with updated meta">>}]),
        fun() -> lists:sort(syn:local_members(custom_scope_ab, {group, "one"})) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [custom_scope_ab, {group, "one"}])) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, local_members, [custom_scope_ab, {group, "one"}]),

    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, "with-meta-2"}]),
        fun() -> lists:sort(syn:members(custom_scope_ab, {group, "two"})) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, "with-meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [custom_scope_ab, {group, "two"}])) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, members, [custom_scope_ab, {group, "two"}]),

    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, "with-meta-2"}]),
        fun() -> lists:sort(syn:local_members(custom_scope_ab, {group, "two"})) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [custom_scope_ab, {group, "two"}])) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, local_members, [custom_scope_ab, {group, "two"}]),

    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:members(custom_scope_bc, {group, "two"}),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn1, added_meta}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [custom_scope_bc, {group, "two"}])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn1, added_meta}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, members, [custom_scope_bc, {group, "two"}])) end
    ),

    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:local_members(custom_scope_bc, {group, "two"}),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn1, added_meta}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [custom_scope_bc, {group, "two"}])) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, local_members, [custom_scope_bc, {group, "two"}])) end
    ),

    2 = syn:group_count(custom_scope_ab),
    2 = syn:group_count(custom_scope_ab, node()),
    0 = syn:group_count(custom_scope_ab, SlaveNode1),
    0 = syn:group_count(custom_scope_ab, SlaveNode2),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:group_count(custom_scope_bc),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:group_count(custom_scope_bc, node()),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:group_count(custom_scope_bc, SlaveNode1),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:group_count(custom_scope_bc, SlaveNode2),
    2 = rpc:call(SlaveNode1, syn, group_count, [custom_scope_ab]),
    2 = rpc:call(SlaveNode1, syn, group_count, [custom_scope_ab, node()]),
    0 = rpc:call(SlaveNode1, syn, group_count, [custom_scope_ab, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, group_count, [custom_scope_ab, SlaveNode2]),
    1 = rpc:call(SlaveNode1, syn, group_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode1, syn, group_count, [custom_scope_bc, node()]),
    1 = rpc:call(SlaveNode1, syn, group_count, [custom_scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, group_count, [custom_scope_bc, SlaveNode2]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, group_count, [custom_scope_ab]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, group_count, [custom_scope_ab, node()]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, group_count, [custom_scope_ab, SlaveNode1]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, group_count, [custom_scope_ab, SlaveNode2]),
    1 = rpc:call(SlaveNode2, syn, group_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode2, syn, group_count, [custom_scope_bc, node()]),
    1 = rpc:call(SlaveNode2, syn, group_count, [custom_scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode2, syn, group_count, [custom_scope_bc, SlaveNode2]),

    %% crash scope process to ensure that monitors get recreated
    exit(whereis(syn_groups_custom_scope_ab), kill),
    syn_test_suite_helper:wait_process_name_ready(syn_groups_custom_scope_ab),

    %% kill process
    syn_test_suite_helper:kill_process(Pid),
    syn_test_suite_helper:kill_process(PidRemoteOn1),
    %% leave
    ok = syn:leave(custom_scope_ab, {group, "one"}, PidWithMeta),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(syn:members(custom_scope_ab, {group, "one"})) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [custom_scope_ab, {group, "one"}])) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, members, [custom_scope_ab, {group, "one"}]),
    false = syn:is_member(custom_scope_ab, {group, "one"}, Pid),
    false = syn:is_member(custom_scope_ab, {group, "one"}, PidWithMeta),
    false = syn:is_member(custom_scope_ab, {group, "one"}, PidRemoteOn1),
    false = rpc:call(SlaveNode1, syn, is_member, [custom_scope_ab, {group, "one"}, Pid]),
    false = rpc:call(SlaveNode1, syn, is_member, [custom_scope_ab, {group, "one"}, PidWithMeta]),
    false = rpc:call(SlaveNode1, syn, is_member, [custom_scope_ab, {group, "one"}, PidRemoteOn1]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, is_member, [custom_scope_ab, {group, "one"}, Pid]),

    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(syn:local_members(custom_scope_ab, {group, "one"})) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [custom_scope_ab, {group, "one"}])) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, local_members, [custom_scope_ab, {group, "one"}]),
    false = syn:is_local_member(custom_scope_ab, {group, "one"}, Pid),
    false = syn:is_local_member(custom_scope_ab, {group, "one"}, PidWithMeta),
    false = syn:is_local_member(custom_scope_ab, {group, "one"}, PidRemoteOn1),
    false = rpc:call(SlaveNode1, syn, is_local_member, [custom_scope_ab, {group, "one"}, Pid]),
    false = rpc:call(SlaveNode1, syn, is_local_member, [custom_scope_ab, {group, "one"}, PidWithMeta]),
    false = rpc:call(SlaveNode1, syn, is_local_member, [custom_scope_ab, {group, "one"}, PidRemoteOn1]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, is_local_member, [custom_scope_ab, {group, "one"}, Pid]),

    syn_test_suite_helper:assert_wait(
        [{PidWithMeta, "with-meta-2"}],
        fun() -> lists:sort(syn:members(custom_scope_ab, {group, "two"})) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidWithMeta, "with-meta-2"}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [custom_scope_ab, {group, "two"}])) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, members, [custom_scope_ab, {group, "two"}]),
    false = syn:is_member(custom_scope_ab, {group, "two"}, Pid),
    true = syn:is_member(custom_scope_ab, {group, "two"}, PidWithMeta),
    false = syn:is_member(custom_scope_ab, {group, "two"}, PidRemoteOn1),
    false = rpc:call(SlaveNode1, syn, is_member, [custom_scope_ab, {group, "two"}, Pid]),
    true = rpc:call(SlaveNode1, syn, is_member, [custom_scope_ab, {group, "two"}, PidWithMeta]),
    false = rpc:call(SlaveNode1, syn, is_member, [custom_scope_ab, {group, "two"}, PidRemoteOn1]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, is_member, [custom_scope_ab, {group, "two"}, Pid]),

    syn_test_suite_helper:assert_wait(
        [{PidWithMeta, "with-meta-2"}],
        fun() -> lists:sort(syn:local_members(custom_scope_ab, {group, "two"})) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [custom_scope_ab, {group, "two"}])) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, local_members, [custom_scope_ab, {group, "two"}]),
    false = syn:is_local_member(custom_scope_ab, {group, "two"}, Pid),
    true = syn:is_local_member(custom_scope_ab, {group, "two"}, PidWithMeta),
    false = syn:is_local_member(custom_scope_ab, {group, "two"}, PidRemoteOn1),
    false = rpc:call(SlaveNode1, syn, is_local_member, [custom_scope_ab, {group, "two"}, Pid]),
    false = rpc:call(SlaveNode1, syn, is_local_member, [custom_scope_ab, {group, "two"}, PidWithMeta]),
    false = rpc:call(SlaveNode1, syn, is_local_member, [custom_scope_ab, {group, "two"}, PidRemoteOn1]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, is_local_member, [custom_scope_ab, {group, "two"}, Pid]),

    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:members(custom_scope_bc, {group, "two"}),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [custom_scope_bc, {group, "two"}])) end
    ),
    syn_test_suite_helper:assert_wait(
        [], fun() -> lists:sort(rpc:call(SlaveNode2, syn, members, [custom_scope_bc, {group, "two"}])) end
    ),

    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:local_members(custom_scope_bc, {group, "two"}),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [custom_scope_bc, {group, "two"}])) end
    ),
    syn_test_suite_helper:assert_wait(
        [], fun() -> lists:sort(rpc:call(SlaveNode2, syn, local_members, [custom_scope_bc, {group, "two"}])) end
    ),

    1 = syn:group_count(custom_scope_ab),
    1 = syn:group_count(custom_scope_ab, node()),
    0 = syn:group_count(custom_scope_ab, SlaveNode1),
    0 = syn:group_count(custom_scope_ab, SlaveNode2),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:group_count(custom_scope_bc),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:group_count(custom_scope_bc, node()),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:group_count(custom_scope_bc, SlaveNode1),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:group_count(custom_scope_bc, SlaveNode2),
    1 = rpc:call(SlaveNode1, syn, group_count, [custom_scope_ab]),
    1 = rpc:call(SlaveNode1, syn, group_count, [custom_scope_ab, node()]),
    0 = rpc:call(SlaveNode1, syn, group_count, [custom_scope_ab, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, group_count, [custom_scope_ab, SlaveNode2]),
    0 = rpc:call(SlaveNode1, syn, group_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode1, syn, group_count, [custom_scope_bc, node()]),
    0 = rpc:call(SlaveNode1, syn, group_count, [custom_scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, group_count, [custom_scope_bc, SlaveNode2]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, group_count, [custom_scope_ab]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, group_count, [custom_scope_ab, node()]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, group_count, [custom_scope_ab, SlaveNode1]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, group_count, [custom_scope_ab, SlaveNode2]),
    0 = rpc:call(SlaveNode2, syn, group_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode2, syn, group_count, [custom_scope_bc, node()]),
    0 = rpc:call(SlaveNode2, syn, group_count, [custom_scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode2, syn, group_count, [custom_scope_bc, SlaveNode2]),

    %% errors
    {error, not_in_group} = syn:leave(custom_scope_ab, {group, "one"}, PidWithMeta).

three_nodes_cluster_changes(Config) ->
    %% get slaves
    SlaveNode1 = proplists:get_value(slave_node_1, Config),
    SlaveNode2 = proplists:get_value(slave_node_2, Config),

    %% disconnect 1 from 2
    rpc:call(SlaveNode1, syn_test_suite_helper, disconnect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node()]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node()]),

    %% start syn on 1 and 2, nodes don't know of each other
    ok = rpc:call(SlaveNode1, syn, start, []),
    ok = rpc:call(SlaveNode2, syn, start, []),

    %% add custom scopes
    ok = rpc:call(SlaveNode1, syn, add_node_to_scopes, [[custom_scope_bc]]),
    ok = rpc:call(SlaveNode2, syn, add_node_to_scopes, [[custom_scope_bc]]),

    %% start processes
    PidRemoteOn1 = syn_test_suite_helper:start_process(SlaveNode1),
    PidRemoteOn2 = syn_test_suite_helper:start_process(SlaveNode2),

    %% join
    ok = rpc:call(SlaveNode1, syn, join, [<<"common-group">>, PidRemoteOn1, "meta-1"]),
    ok = rpc:call(SlaveNode2, syn, join, [<<"common-group">>, PidRemoteOn2, "meta-2"]),
    ok = rpc:call(SlaveNode2, syn, join, [<<"group-2">>, PidRemoteOn2, "other-meta"]),
    ok = rpc:call(SlaveNode1, syn, join, [custom_scope_bc, <<"scoped-on-bc">>, PidRemoteOn1, "scoped-meta-1"]),
    ok = rpc:call(SlaveNode2, syn, join, [custom_scope_bc, <<"scoped-on-bc">>, PidRemoteOn2, "scoped-meta-2"]),

    %% form full cluster
    ok = syn:start(),
    rpc:call(SlaveNode1, syn_test_suite_helper, connect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node(), SlaveNode1]),
    syn_test_suite_helper:wait_process_name_ready(syn_groups_default),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        lists:sort([{PidRemoteOn1, "meta-1"}, {PidRemoteOn2, "meta-2"}]),
        fun() -> lists:sort(syn:members(<<"common-group">>)) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{PidRemoteOn1, "meta-1"}, {PidRemoteOn2, "meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [<<"common-group">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{PidRemoteOn1, "meta-1"}, {PidRemoteOn2, "meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, members, [<<"common-group">>])) end
    ),

    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(syn:local_members(<<"common-group">>)) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn1, "meta-1"}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [<<"common-group">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "meta-2"}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, local_members, [<<"common-group">>])) end
    ),

    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "other-meta"}],
        fun() -> lists:sort(syn:members(<<"group-2">>)) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "other-meta"}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [<<"group-2">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "other-meta"}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, members, [<<"group-2">>])) end
    ),

    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(syn:local_members(<<"group-2">>)) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [<<"group-2">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "other-meta"}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, local_members, [<<"group-2">>])) end
    ),

    2 = syn:group_count(),
    0 = syn:group_count(default, node()),
    1 = syn:group_count(default, SlaveNode1),
    2 = syn:group_count(default, SlaveNode2),
    2 = rpc:call(SlaveNode1, syn, group_count, []),
    0 = rpc:call(SlaveNode1, syn, group_count, [default, node()]),
    1 = rpc:call(SlaveNode1, syn, group_count, [default, SlaveNode1]),
    2 = rpc:call(SlaveNode1, syn, group_count, [default, SlaveNode2]),
    2 = rpc:call(SlaveNode2, syn, group_count, []),
    0 = rpc:call(SlaveNode2, syn, group_count, [default, node()]),
    1 = rpc:call(SlaveNode2, syn, group_count, [default, SlaveNode1]),
    2 = rpc:call(SlaveNode2, syn, group_count, [default, SlaveNode2]),

    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:members(custom_scope_bc, <<"scoped-on-bc">>),
    syn_test_suite_helper:assert_wait(
        lists:sort([{PidRemoteOn1, "scoped-meta-1"}, {PidRemoteOn2, "scoped-meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [custom_scope_bc, <<"scoped-on-bc">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{PidRemoteOn1, "scoped-meta-1"}, {PidRemoteOn2, "scoped-meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, members, [custom_scope_bc, <<"scoped-on-bc">>])) end
    ),

    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:local_members(custom_scope_bc, <<"scoped-on-bc">>),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn1, "scoped-meta-1"}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [custom_scope_bc, <<"scoped-on-bc">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "scoped-meta-2"}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, local_members, [custom_scope_bc, <<"scoped-on-bc">>])) end
    ),

    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:group_count(custom_scope_bc),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:group_count(custom_scope_bc, node()),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:group_count(custom_scope_bc, SlaveNode1),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:group_count(custom_scope_bc, SlaveNode2),
    1 = rpc:call(SlaveNode1, syn, group_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode1, syn, group_count, [custom_scope_bc, node()]),
    1 = rpc:call(SlaveNode1, syn, group_count, [custom_scope_bc, SlaveNode1]),
    1 = rpc:call(SlaveNode1, syn, group_count, [custom_scope_bc, SlaveNode2]),
    1 = rpc:call(SlaveNode2, syn, group_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode2, syn, group_count, [custom_scope_bc, node()]),
    1 = rpc:call(SlaveNode2, syn, group_count, [custom_scope_bc, SlaveNode1]),
    1 = rpc:call(SlaveNode2, syn, group_count, [custom_scope_bc, SlaveNode2]),

    %% partial netsplit (1 cannot see 2)
    rpc:call(SlaveNode1, syn_test_suite_helper, disconnect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node()]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node()]),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        lists:sort([{PidRemoteOn1, "meta-1"}, {PidRemoteOn2, "meta-2"}]),
        fun() -> lists:sort(syn:members(<<"common-group">>)) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn1, "meta-1"}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [<<"common-group">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "meta-2"}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, members, [<<"common-group">>])) end
    ),

    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(syn:local_members(<<"common-group">>)) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn1, "meta-1"}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [<<"common-group">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "meta-2"}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, local_members, [<<"common-group">>])) end
    ),

    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "other-meta"}],
        fun() -> lists:sort(syn:members(<<"group-2">>)) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [<<"group-2">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "other-meta"}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, members, [<<"group-2">>])) end
    ),

    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(syn:local_members(<<"group-2">>)) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [<<"group-2">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "other-meta"}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, local_members, [<<"group-2">>])) end
    ),

    2 = syn:group_count(),
    0 = syn:group_count(default, node()),
    1 = syn:group_count(default, SlaveNode1),
    2 = syn:group_count(default, SlaveNode2),
    1 = rpc:call(SlaveNode1, syn, group_count, []),
    0 = rpc:call(SlaveNode1, syn, group_count, [default, node()]),
    1 = rpc:call(SlaveNode1, syn, group_count, [default, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, group_count, [default, SlaveNode2]),
    2 = rpc:call(SlaveNode2, syn, group_count, []),
    0 = rpc:call(SlaveNode2, syn, group_count, [default, node()]),
    0 = rpc:call(SlaveNode2, syn, group_count, [default, SlaveNode1]),
    2 = rpc:call(SlaveNode2, syn, group_count, [default, SlaveNode2]),

    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:members(custom_scope_bc, <<"scoped-on-bc">>),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn1, "scoped-meta-1"}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [custom_scope_bc, <<"scoped-on-bc">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "scoped-meta-2"}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, members, [custom_scope_bc, <<"scoped-on-bc">>])) end
    ),

    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:local_members(custom_scope_bc, <<"scoped-on-bc">>),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn1, "scoped-meta-1"}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [custom_scope_bc, <<"scoped-on-bc">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "scoped-meta-2"}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, local_members, [custom_scope_bc, <<"scoped-on-bc">>])) end
    ),

    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:group_count(custom_scope_bc),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:group_count(custom_scope_bc, node()),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:group_count(custom_scope_bc, SlaveNode1),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:group_count(custom_scope_bc, SlaveNode2),
    1 = rpc:call(SlaveNode1, syn, group_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode1, syn, group_count, [custom_scope_bc, node()]),
    1 = rpc:call(SlaveNode1, syn, group_count, [custom_scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, group_count, [custom_scope_bc, SlaveNode2]),
    1 = rpc:call(SlaveNode2, syn, group_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode2, syn, group_count, [custom_scope_bc, node()]),
    0 = rpc:call(SlaveNode2, syn, group_count, [custom_scope_bc, SlaveNode1]),
    1 = rpc:call(SlaveNode2, syn, group_count, [custom_scope_bc, SlaveNode2]),

    %% re-join
    rpc:call(SlaveNode1, syn_test_suite_helper, connect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node(), SlaveNode1]),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        lists:sort([{PidRemoteOn1, "meta-1"}, {PidRemoteOn2, "meta-2"}]),
        fun() -> lists:sort(syn:members(<<"common-group">>)) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{PidRemoteOn1, "meta-1"}, {PidRemoteOn2, "meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [<<"common-group">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{PidRemoteOn1, "meta-1"}, {PidRemoteOn2, "meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, members, [<<"common-group">>])) end
    ),

    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(syn:local_members(<<"common-group">>)) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn1, "meta-1"}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [<<"common-group">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "meta-2"}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, local_members, [<<"common-group">>])) end
    ),

    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "other-meta"}],
        fun() -> lists:sort(syn:members(<<"group-2">>)) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "other-meta"}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [<<"group-2">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "other-meta"}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, members, [<<"group-2">>])) end
    ),

    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(syn:local_members(<<"group-2">>)) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [<<"group-2">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "other-meta"}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, local_members, [<<"group-2">>])) end
    ),

    2 = syn:group_count(),
    0 = syn:group_count(default, node()),
    1 = syn:group_count(default, SlaveNode1),
    2 = syn:group_count(default, SlaveNode2),
    2 = rpc:call(SlaveNode1, syn, group_count, []),
    0 = rpc:call(SlaveNode1, syn, group_count, [default, node()]),
    1 = rpc:call(SlaveNode1, syn, group_count, [default, SlaveNode1]),
    2 = rpc:call(SlaveNode1, syn, group_count, [default, SlaveNode2]),
    2 = rpc:call(SlaveNode2, syn, group_count, []),
    0 = rpc:call(SlaveNode2, syn, group_count, [default, node()]),
    1 = rpc:call(SlaveNode2, syn, group_count, [default, SlaveNode1]),
    2 = rpc:call(SlaveNode2, syn, group_count, [default, SlaveNode2]),

    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:members(custom_scope_bc, <<"scoped-on-bc">>),
    syn_test_suite_helper:assert_wait(
        lists:sort([{PidRemoteOn1, "scoped-meta-1"}, {PidRemoteOn2, "scoped-meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [custom_scope_bc, <<"scoped-on-bc">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{PidRemoteOn1, "scoped-meta-1"}, {PidRemoteOn2, "scoped-meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, members, [custom_scope_bc, <<"scoped-on-bc">>])) end
    ),

    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:local_members(custom_scope_bc, <<"scoped-on-bc">>),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn1, "scoped-meta-1"}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [custom_scope_bc, <<"scoped-on-bc">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "scoped-meta-2"}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, local_members, [custom_scope_bc, <<"scoped-on-bc">>])) end
    ),

    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:group_count(custom_scope_bc),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:group_count(custom_scope_bc, node()),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:group_count(custom_scope_bc, SlaveNode1),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:group_count(custom_scope_bc, SlaveNode2),
    1 = rpc:call(SlaveNode1, syn, group_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode1, syn, group_count, [custom_scope_bc, node()]),
    1 = rpc:call(SlaveNode1, syn, group_count, [custom_scope_bc, SlaveNode1]),
    1 = rpc:call(SlaveNode1, syn, group_count, [custom_scope_bc, SlaveNode2]),
    1 = rpc:call(SlaveNode2, syn, group_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode2, syn, group_count, [custom_scope_bc, node()]),
    1 = rpc:call(SlaveNode2, syn, group_count, [custom_scope_bc, SlaveNode1]),
    1 = rpc:call(SlaveNode2, syn, group_count, [custom_scope_bc, SlaveNode2]).

three_nodes_custom_event_handler_joined_left(Config) ->
    %% get slaves
    SlaveNode1 = proplists:get_value(slave_node_1, Config),
    SlaveNode2 = proplists:get_value(slave_node_2, Config),

    %% add custom handler for callbacks
    syn:set_event_handler(syn_test_event_handler_callbacks),
    rpc:call(SlaveNode1, syn, set_event_handler, [syn_test_event_handler_callbacks]),
    rpc:call(SlaveNode2, syn, set_event_handler, [syn_test_event_handler_callbacks]),

    %% start syn on nodes
    ok = syn:start(),
    ok = rpc:call(SlaveNode1, syn, start, []),
    ok = rpc:call(SlaveNode2, syn, start, []),

    %% init
    TestPid = self(),
    CurrentNode = node(),

    %% start process
    Pid = syn_test_suite_helper:start_process(),
    Pid2 = syn_test_suite_helper:start_process(),

    %% ---> on join
    ok = syn:join("my-group", Pid, {recipient, TestPid, <<"meta">>}),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_joined, CurrentNode, default, "my-group", Pid, <<"meta">>, normal},
        {on_process_joined, SlaveNode1, default, "my-group", Pid, <<"meta">>, normal},
        {on_process_joined, SlaveNode2, default, "my-group", Pid, <<"meta">>, normal}
    ]),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% join from another node
    ok = rpc:call(SlaveNode1, syn, join, ["my-group", Pid2, {recipient, self(), <<"meta-for-2">>}]),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_joined, CurrentNode, default, "my-group", Pid2, <<"meta-for-2">>, normal},
        {on_process_joined, SlaveNode1, default, "my-group", Pid2, <<"meta-for-2">>, normal},
        {on_process_joined, SlaveNode2, default, "my-group", Pid2, <<"meta-for-2">>, normal}
    ]),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% ---> on meta update
    ok = syn:join("my-group", Pid, {recipient, self(), <<"new-meta-0">>}),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_group_process_updated, CurrentNode, default, "my-group", Pid, <<"new-meta-0">>, normal},
        {on_group_process_updated, SlaveNode1, default, "my-group", Pid, <<"new-meta-0">>, normal},
        {on_group_process_updated, SlaveNode2, default, "my-group", Pid, <<"new-meta-0">>, normal}
    ]),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% update meta from another node
    ok = rpc:call(SlaveNode1, syn, join, ["my-group", Pid, {recipient, self(), <<"new-meta">>}]),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_group_process_updated, CurrentNode, default, "my-group", Pid, <<"new-meta">>, normal},
        {on_group_process_updated, SlaveNode1, default, "my-group", Pid, <<"new-meta">>, normal},
        {on_group_process_updated, SlaveNode2, default, "my-group", Pid, <<"new-meta">>, normal}
    ]),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% ---> on left
    ok = syn:leave("my-group", Pid),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_left, CurrentNode, default, "my-group", Pid, <<"new-meta">>, normal},
        {on_process_left, SlaveNode1, default, "my-group", Pid, <<"new-meta">>, normal},
        {on_process_left, SlaveNode2, default, "my-group", Pid, <<"new-meta">>, normal}
    ]),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% leave from another node
    ok = rpc:call(SlaveNode1, syn, leave, ["my-group", Pid2]),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_left, CurrentNode, default, "my-group", Pid2, <<"meta-for-2">>, normal},
        {on_process_left, SlaveNode1, default, "my-group", Pid2, <<"meta-for-2">>, normal},
        {on_process_left, SlaveNode2, default, "my-group", Pid2, <<"meta-for-2">>, normal}
    ]),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% clean & check (no callbacks since process has left)
    syn_test_suite_helper:kill_process(Pid),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% ---> after a netsplit
    PidRemoteOn1 = syn_test_suite_helper:start_process(SlaveNode1),
    syn:join(remote_on_1, PidRemoteOn1, {recipient, self(), <<"netsplit">>}),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_joined, CurrentNode, default, remote_on_1, PidRemoteOn1, <<"netsplit">>, normal},
        {on_process_joined, SlaveNode1, default, remote_on_1, PidRemoteOn1, <<"netsplit">>, normal},
        {on_process_joined, SlaveNode2, default, remote_on_1, PidRemoteOn1, <<"netsplit">>, normal}
    ]),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% partial netsplit (1 cannot see 2)
    rpc:call(SlaveNode1, syn_test_suite_helper, disconnect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node()]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node()]),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_left, SlaveNode2, default, remote_on_1, PidRemoteOn1, <<"netsplit">>, {syn_remote_scope_node_down, default, SlaveNode1}}
    ]),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% ---> after a re-join
    %% re-join
    rpc:call(SlaveNode1, syn_test_suite_helper, connect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node(), SlaveNode1]),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_joined, SlaveNode2, default, remote_on_1, PidRemoteOn1, <<"netsplit">>, {syn_remote_scope_node_up, default, SlaveNode1}}
    ]),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% clean
    syn_test_suite_helper:kill_process(PidRemoteOn1),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_left, CurrentNode, default, remote_on_1, PidRemoteOn1, <<"netsplit">>, killed},
        {on_process_left, SlaveNode1, default, remote_on_1, PidRemoteOn1, <<"netsplit">>, killed},
        {on_process_left, SlaveNode2, default, remote_on_1, PidRemoteOn1, <<"netsplit">>, killed}
    ]),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% ---> don't call on monitor rebuild
    %% crash the scope process on local
    syn_test_suite_helper:kill_process(syn_groups_default),

    %% no messages
    syn_test_suite_helper:assert_wait(
        ok,
        fun() -> syn_test_suite_helper:assert_empty_queue(self()) end
    ).

three_nodes_publish_default_scope(Config) ->
    %% get slaves
    SlaveNode1 = proplists:get_value(slave_node_1, Config),
    SlaveNode2 = proplists:get_value(slave_node_2, Config),

    %% start syn on nodes
    ok = syn:start(),
    ok = rpc:call(SlaveNode1, syn, start, []),
    ok = rpc:call(SlaveNode2, syn, start, []),

    %% start processes
    TestMessage = test_message,
    TestPid = self(),
    SubscriberLoop = fun() -> subscriber_loop(TestPid, TestMessage) end,

    Pid = syn_test_suite_helper:start_process(SubscriberLoop),
    OtherPid = syn_test_suite_helper:start_process(SubscriberLoop),
    PidRemoteOn1 = syn_test_suite_helper:start_process(SlaveNode1, SubscriberLoop),
    PidRemoteOn2 = syn_test_suite_helper:start_process(SlaveNode2, SubscriberLoop),

    %% join
    ok = syn:join(<<"subscribers">>, Pid),
    ok = syn:join(<<"ignore">>, OtherPid),
    ok = syn:join(<<"subscribers">>, PidRemoteOn1),
    ok = syn:join(<<"subscribers">>, PidRemoteOn2),

    %% ---> publish
    {ok, 3} = syn:publish(<<"subscribers">>, TestMessage),

    syn_test_suite_helper:assert_received_messages([
        {done, Pid},
        {done, PidRemoteOn1},
        {done, PidRemoteOn2}
    ]),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% non-existant
    {ok, 0} = syn:publish(<<"non-existant">>, TestMessage),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% ---> publish local
    {ok, 1} = syn:local_publish(<<"subscribers">>, test_message),

    syn_test_suite_helper:assert_received_messages([
        {done, Pid}
    ]),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% non-existant
    {ok, 0} = syn:local_publish(<<"non-existant">>, TestMessage),
    syn_test_suite_helper:assert_empty_queue(self()).

three_nodes_publish_custom_scope(Config) ->
    %% get slaves
    SlaveNode1 = proplists:get_value(slave_node_1, Config),
    SlaveNode2 = proplists:get_value(slave_node_2, Config),

    %% start syn on nodes
    ok = syn:start(),
    ok = rpc:call(SlaveNode1, syn, start, []),
    ok = rpc:call(SlaveNode2, syn, start, []),

    %% add custom scopes
    ok = syn:add_node_to_scope(custom_scope_ab),
    ok = rpc:call(SlaveNode1, syn, add_node_to_scopes, [[custom_scope_ab, custom_scope_bc]]),
    ok = rpc:call(SlaveNode2, syn, add_node_to_scopes, [[custom_scope_bc]]),

    %% start processes
    TestMessage = test_message,
    TestPid = self(),
    SubscriberLoop = fun() -> subscriber_loop(TestPid, TestMessage) end,

    Pid = syn_test_suite_helper:start_process(SubscriberLoop),
    Pid2 = syn_test_suite_helper:start_process(SubscriberLoop),
    PidRemoteOn1 = syn_test_suite_helper:start_process(SlaveNode1, SubscriberLoop),
    PidRemoteOn2 = syn_test_suite_helper:start_process(SlaveNode2, SubscriberLoop),

    %% join
    ok = syn:join(custom_scope_ab, <<"subscribers">>, Pid),
    ok = syn:join(custom_scope_ab, <<"subscribers-2">>, Pid2),
    ok = syn:join(custom_scope_ab, <<"subscribers">>, PidRemoteOn1),
    ok = rpc:call(SlaveNode1, syn, join, [custom_scope_bc, <<"subscribers">>, PidRemoteOn1]),
    ok = rpc:call(SlaveNode2, syn, join, [custom_scope_bc, <<"subscribers">>, PidRemoteOn2]),

    %% ---> publish
    {ok, 2} = syn:publish(custom_scope_ab, <<"subscribers">>, TestMessage),

    syn_test_suite_helper:assert_received_messages([
        {done, Pid},
        {done, PidRemoteOn1}
    ]),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% errors
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:publish(custom_scope_bc, <<"subscribers">>, TestMessage),

    %% on other scope
    {ok, 2} = rpc:call(SlaveNode1, syn, publish, [custom_scope_bc, <<"subscribers">>, TestMessage]),

    syn_test_suite_helper:assert_received_messages([
        {done, PidRemoteOn1},
        {done, PidRemoteOn2}
    ]),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% non-existant
    {ok, 0} = syn:publish(custom_scope_ab, <<"non-existant">>, TestMessage),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% ---> publish local
    {ok, 1} = syn:local_publish(custom_scope_ab, <<"subscribers">>, test_message),

    syn_test_suite_helper:assert_received_messages([
        {done, Pid}
    ]),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% non-existant
    {ok, 0} = syn:local_publish(custom_scope_ab, <<"non-existant">>, TestMessage),
    syn_test_suite_helper:assert_empty_queue(self()).

three_nodes_multi_call_default_scope(Config) ->
    %% get slaves
    SlaveNode1 = proplists:get_value(slave_node_1, Config),
    SlaveNode2 = proplists:get_value(slave_node_2, Config),

    %% start syn on nodes
    ok = syn:start(),
    ok = rpc:call(SlaveNode1, syn, start, []),
    ok = rpc:call(SlaveNode2, syn, start, []),

    %% start processes
    RecipientLoopLate = fun() -> timer:sleep(200), recipient_loop() end,

    Pid = syn_test_suite_helper:start_process(fun recipient_loop/0),
    Pid2 = syn_test_suite_helper:start_process(RecipientLoopLate),
    PidRemoteOn1 = syn_test_suite_helper:start_process(SlaveNode1, fun recipient_loop/0),
    PidRemoteOn2 = syn_test_suite_helper:start_process(SlaveNode2, fun recipient_loop/0),

    %% join
    ok = syn:join(<<"recipients">>, Pid, "meta-1"),
    ok = syn:join(<<"recipients">>, Pid2),
    ok = syn:join(<<"recipients">>, PidRemoteOn1, "meta-on-1"),
    ok = syn:join(<<"recipients">>, PidRemoteOn2, "meta-on-2"),

    %% ---> multi_call
    {Replies, BadReplies} = syn:multi_call(default, <<"recipients">>, test_message, 100),

    RepliesSorted = lists:sort(Replies),
    RepliesSorted = lists:sort([
        {{Pid, "meta-1"}, {reply, test_message, Pid, "meta-1"}},
        {{PidRemoteOn1, "meta-on-1"}, {reply, test_message, PidRemoteOn1, "meta-on-1"}},
        {{PidRemoteOn2, "meta-on-2"}, {reply, test_message, PidRemoteOn2, "meta-on-2"}}
    ]),
    BadReplies = [{Pid2, undefined}],

    %% empty
    {[], []} = syn:multi_call(default, <<"non-existant">>, test_message, 100).

three_nodes_multi_call_custom_scope(Config) ->
    %% get slaves
    SlaveNode1 = proplists:get_value(slave_node_1, Config),
    SlaveNode2 = proplists:get_value(slave_node_2, Config),

    %% start syn on nodes
    ok = syn:start(),
    ok = rpc:call(SlaveNode1, syn, start, []),
    ok = rpc:call(SlaveNode2, syn, start, []),

    %% add custom scopes
    ok = syn:add_node_to_scope(custom_scope_ab),
    ok = rpc:call(SlaveNode1, syn, add_node_to_scopes, [[custom_scope_ab, custom_scope_bc]]),
    ok = rpc:call(SlaveNode2, syn, add_node_to_scopes, [[custom_scope_bc]]),

    %% start processes
    RecipientLoopLate = fun() -> timer:sleep(200), recipient_loop() end,

    Pid = syn_test_suite_helper:start_process(fun recipient_loop/0),
    Pid2 = syn_test_suite_helper:start_process(RecipientLoopLate),
    PidRemoteOn1 = syn_test_suite_helper:start_process(SlaveNode1, fun recipient_loop/0),
    PidRemoteOn2 = syn_test_suite_helper:start_process(SlaveNode2, fun recipient_loop/0),

    %% join
    ok = syn:join(custom_scope_ab, <<"recipients">>, Pid, "meta-1"),
    ok = syn:join(custom_scope_ab, <<"recipients">>, Pid2),
    ok = syn:join(custom_scope_ab, <<"recipients">>, PidRemoteOn1, "meta-on-ab-1"),
    ok = rpc:call(SlaveNode1, syn, join, [custom_scope_bc, <<"recipients">>, PidRemoteOn1, "meta-on-bc-1"]),
    ok = rpc:call(SlaveNode2, syn, join, [custom_scope_bc, <<"recipients">>, PidRemoteOn2, "meta-on-bc-2"]),

    %% errors
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:multi_call(custom_scope_bc, <<"recipients">>, test_message, 100),

    %% ---> multi_call
    {RepliesAB, BadRepliesAB} = syn:multi_call(custom_scope_ab, <<"recipients">>, test_message_ab, 100),

    RepliesABSorted = lists:sort(RepliesAB),
    RepliesABSorted = lists:sort([
        {{Pid, "meta-1"}, {reply, test_message_ab, Pid, "meta-1"}},
        {{PidRemoteOn1, "meta-on-ab-1"}, {reply, test_message_ab, PidRemoteOn1, "meta-on-ab-1"}}
    ]),
    BadRepliesAB = [{Pid2, undefined}],

    %% different scope
    {RepliesBC, BadRepliesBC} = rpc:call(SlaveNode1, syn, multi_call, [custom_scope_bc, <<"recipients">>, test_message_bc, 100]),

    RepliesBCSorted = lists:sort(RepliesBC),
    RepliesBCSorted = lists:sort([
        {{PidRemoteOn1, "meta-on-bc-1"}, {reply, test_message_bc, PidRemoteOn1, "meta-on-bc-1"}},
        {{PidRemoteOn2, "meta-on-bc-2"}, {reply, test_message_bc, PidRemoteOn2, "meta-on-bc-2"}}
    ]),
    BadRepliesBC = [].

three_nodes_group_names_default_scope(Config) ->
    %% get slaves
    SlaveNode1 = proplists:get_value(slave_node_1, Config),
    SlaveNode2 = proplists:get_value(slave_node_2, Config),

    %% start syn on nodes
    ok = syn:start(),
    ok = rpc:call(SlaveNode1, syn, start, []),
    ok = rpc:call(SlaveNode2, syn, start, []),

    %% start processes
    Pid = syn_test_suite_helper:start_process(),
    Pid2 = syn_test_suite_helper:start_process(),
    PidRemoteOn1 = syn_test_suite_helper:start_process(SlaveNode1),
    PidRemoteOn2 = syn_test_suite_helper:start_process(SlaveNode2),

    %% join
    ok = syn:join(<<"subscribers">>, Pid),
    ok = syn:join(<<"subscribers">>, Pid2),
    ok = syn:join(<<"subscribers-2">>, Pid),
    ok = syn:join(<<"subscribers-2">>, PidRemoteOn1),
    ok = syn:join(<<"subscribers-2">>, PidRemoteOn2),
    ok = syn:join(<<"subscribers-3">>, PidRemoteOn1),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers">>, <<"subscribers-2">>, <<"subscribers-3">>]),
        fun() -> lists:sort(syn:group_names()) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers">>, <<"subscribers-2">>]),
        fun() -> lists:sort(syn:group_names(default, node())) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers-2">>, <<"subscribers-3">>]),
        fun() -> lists:sort(syn:group_names(default, SlaveNode1)) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers-2">>],
        fun() -> lists:sort(syn:group_names(default, SlaveNode2)) end
    ),

    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers">>, <<"subscribers-2">>, <<"subscribers-3">>]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [])) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers">>, <<"subscribers-2">>]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [default, node()])) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers-2">>, <<"subscribers-3">>]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [default, SlaveNode1])) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers-2">>],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [default, SlaveNode2])) end
    ),

    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers">>, <<"subscribers-2">>, <<"subscribers-3">>]),
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, group_names, [])) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers">>, <<"subscribers-2">>]),
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, group_names, [default, node()])) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers-2">>, <<"subscribers-3">>]),
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, group_names, [default, SlaveNode1])) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers-2">>],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, group_names, [default, SlaveNode2])) end
    ),

    %% leave
    ok = syn:leave(<<"subscribers-2">>, Pid),
    ok = syn:leave(<<"subscribers-2">>, PidRemoteOn1),
    ok = syn:leave(<<"subscribers-2">>, PidRemoteOn2),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers">>, <<"subscribers-3">>]),
        fun() -> lists:sort(syn:group_names()) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers">>],
        fun() -> lists:sort(syn:group_names(default, node())) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers-3">>],
        fun() -> lists:sort(syn:group_names(default, SlaveNode1)) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(syn:group_names(default, SlaveNode2)) end
    ),

    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers">>, <<"subscribers-3">>]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [])) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers">>],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [default, node()])) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers-3">>],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [default, SlaveNode1])) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [default, SlaveNode2])) end
    ),

    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers">>, <<"subscribers-3">>]),
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, group_names, [])) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers">>],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, group_names, [default, node()])) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers-3">>],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, group_names, [default, SlaveNode1])) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, group_names, [default, SlaveNode2])) end
    ),

    %% partial netsplit (1 cannot see 2)
    rpc:call(SlaveNode1, syn_test_suite_helper, disconnect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node()]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node()]),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers">>, <<"subscribers-3">>]),
        fun() -> lists:sort(syn:group_names()) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers">>],
        fun() -> lists:sort(syn:group_names(default, node())) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers-3">>],
        fun() -> lists:sort(syn:group_names(default, SlaveNode1)) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(syn:group_names(default, SlaveNode2)) end
    ),

    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers">>, <<"subscribers-3">>]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [])) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers">>],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [default, node()])) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers-3">>],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [default, SlaveNode1])) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [default, SlaveNode2])) end
    ),

    syn_test_suite_helper:assert_wait(
        [<<"subscribers">>],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, group_names, [])) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers">>],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, group_names, [default, node()])) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, group_names, [default, SlaveNode1])) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, group_names, [default, SlaveNode2])) end
    ),

    %% re-join
    rpc:call(SlaveNode1, syn_test_suite_helper, connect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node(), SlaveNode1]),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers">>, <<"subscribers-3">>]),
        fun() -> lists:sort(syn:group_names()) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers">>],
        fun() -> lists:sort(syn:group_names(default, node())) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers-3">>],
        fun() -> lists:sort(syn:group_names(default, SlaveNode1)) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(syn:group_names(default, SlaveNode2)) end
    ),

    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers">>, <<"subscribers-3">>]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [])) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers">>],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [default, node()])) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers-3">>],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [default, SlaveNode1])) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [default, SlaveNode2])) end
    ),

    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers">>, <<"subscribers-3">>]),
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, group_names, [])) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers">>],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, group_names, [default, node()])) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers-3">>],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, group_names, [default, SlaveNode1])) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, group_names, [default, SlaveNode2])) end
    ).

three_nodes_group_names_custom_scope(Config) ->
    %% get slaves
    SlaveNode1 = proplists:get_value(slave_node_1, Config),
    SlaveNode2 = proplists:get_value(slave_node_2, Config),

    %% start syn on nodes
    ok = syn:start(),
    ok = rpc:call(SlaveNode1, syn, start, []),
    ok = rpc:call(SlaveNode2, syn, start, []),

    %% add custom scopes
    ok = syn:add_node_to_scope(custom_scope_ab),
    ok = rpc:call(SlaveNode1, syn, add_node_to_scopes, [[custom_scope_ab, custom_scope_bc]]),
    ok = rpc:call(SlaveNode2, syn, add_node_to_scopes, [[custom_scope_bc]]),

    %% start processes
    Pid = syn_test_suite_helper:start_process(),
    Pid2 = syn_test_suite_helper:start_process(),
    PidRemoteOn1 = syn_test_suite_helper:start_process(SlaveNode1),
    PidRemoteOn2 = syn_test_suite_helper:start_process(SlaveNode2),

    %% join
    ok = syn:join(custom_scope_ab, <<"subscribers">>, Pid),
    ok = syn:join(custom_scope_ab, <<"subscribers">>, Pid2),
    ok = syn:join(custom_scope_ab, <<"subscribers">>, PidRemoteOn1),
    ok = syn:join(custom_scope_ab, <<"subscribers-2">>, Pid),
    ok = rpc:call(SlaveNode1, syn, join, [custom_scope_bc, <<"subscribers">>, PidRemoteOn1]),
    ok = rpc:call(SlaveNode2, syn, join, [custom_scope_bc, <<"subscribers-2">>, PidRemoteOn2]),

    %% errors
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:group_names(custom_scope_bc),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers">>, <<"subscribers-2">>]),
        fun() -> lists:sort(syn:group_names(custom_scope_ab)) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers">>, <<"subscribers-2">>]),
        fun() -> lists:sort(syn:group_names(custom_scope_ab, node())) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers">>],
        fun() -> lists:sort(syn:group_names(custom_scope_ab, SlaveNode1)) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(syn:group_names(custom_scope_ab, SlaveNode2)) end
    ),

    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers">>, <<"subscribers-2">>]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [custom_scope_ab])) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers">>, <<"subscribers-2">>]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [custom_scope_ab, node()])) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers">>],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [custom_scope_ab, SlaveNode1])) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [custom_scope_ab, SlaveNode2])) end
    ),

    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers">>, <<"subscribers-2">>]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [custom_scope_bc])) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [custom_scope_bc, node()])) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers">>],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [custom_scope_bc, SlaveNode1])) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers-2">>],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [custom_scope_bc, SlaveNode2])) end
    ),

    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers">>, <<"subscribers-2">>]),
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, group_names, [custom_scope_bc])) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, group_names, [custom_scope_bc, node()])) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers">>],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, group_names, [custom_scope_bc, SlaveNode1])) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers-2">>],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, group_names, [custom_scope_bc, SlaveNode2])) end
    ).

%% ===================================================================
%% Internal
%% ===================================================================
subscriber_loop(TestPid, TestMessage) ->
    receive
        TestMessage ->
            TestPid ! {done, self()},
            subscriber_loop(TestPid, TestMessage)
    end.

recipient_loop() ->
    receive
        {syn_multi_call, TestMessage, Caller, Meta} ->
            syn:multi_call_reply(Caller, {reply, TestMessage, self(), Meta}),
            recipient_loop()
    end.
