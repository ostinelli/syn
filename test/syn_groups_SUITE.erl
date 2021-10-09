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
    three_nodes_custom_event_handler_joined_left/1
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
%%            three_nodes_discover_default_scope,
%%            three_nodes_discover_custom_scope,
%%            three_nodes_join_leave_and_monitor_default_scope,
%%            three_nodes_join_leave_and_monitor_custom_scope,
%%            three_nodes_cluster_changes,
            three_nodes_custom_event_handler_joined_left
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
    [] = syn:get_members({group, "one"}),
    [] = rpc:call(SlaveNode1, syn, get_members, [{group, "one"}]),
    [] = rpc:call(SlaveNode2, syn, get_members, [{group, "one"}]),
    [] = syn:get_members({group, "two"}),
    [] = rpc:call(SlaveNode1, syn, get_members, [{group, "two"}]),
    [] = rpc:call(SlaveNode2, syn, get_members, [{group, "two"}]),
    0 = syn:groups_count(default),
    0 = syn:groups_count(default, node()),
    0 = syn:groups_count(default, SlaveNode1),
    0 = syn:groups_count(default, SlaveNode2),

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
        fun() -> lists:sort(syn:get_members({group, "one"})) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, <<"with meta">>}, {PidRemoteOn1, undefined}]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, get_members, [{group, "one"}])) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, <<"with meta">>}, {PidRemoteOn1, undefined}]),
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, get_members, [{group, "one"}])) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, "with-meta-2"}]),
        fun() -> lists:sort(syn:get_members({group, "two"})) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, "with-meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, get_members, [{group, "two"}])) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, "with-meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, get_members, [{group, "two"}])) end
    ),
    2 = syn:groups_count(default),
    2 = syn:groups_count(default, node()),
    1 = syn:groups_count(default, SlaveNode1),
    0 = syn:groups_count(default, SlaveNode2),

    %% re-join to edit meta
    ok = syn:join({group, "one"}, PidWithMeta, <<"with updated meta">>),
    ok = rpc:call(SlaveNode2, syn, join, [{group, "one"}, PidRemoteOn1, added_meta]), %% updated on slave 2

    %% retrieve
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, <<"with updated meta">>}, {PidRemoteOn1, added_meta}]),
        fun() -> lists:sort(syn:get_members({group, "one"})) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, <<"with updated meta">>}, {PidRemoteOn1, added_meta}]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, get_members, [{group, "one"}])) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, <<"with updated meta">>}, {PidRemoteOn1, added_meta}]),
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, get_members, [{group, "one"}])) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, "with-meta-2"}]),
        fun() -> lists:sort(syn:get_members({group, "two"})) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, "with-meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, get_members, [{group, "two"}])) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, "with-meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, get_members, [{group, "two"}])) end
    ),
    2 = syn:groups_count(default),
    2 = syn:groups_count(default, node()),
    1 = syn:groups_count(default, SlaveNode1),
    0 = syn:groups_count(default, SlaveNode2),

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
        fun() -> lists:sort(syn:get_members({group, "one"})) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, get_members, [{group, "one"}])) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, get_members, [{group, "one"}])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidWithMeta, "with-meta-2"}],
        fun() -> lists:sort(syn:get_members({group, "two"})) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidWithMeta, "with-meta-2"}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, get_members, [{group, "two"}])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidWithMeta, "with-meta-2"}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, get_members, [{group, "two"}])) end
    ),
    1 = syn:groups_count(default),
    1 = syn:groups_count(default, node()),
    0 = syn:groups_count(default, SlaveNode1),
    0 = syn:groups_count(default, SlaveNode2),

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
    [] = syn:get_members(custom_scope_ab, {group, "one"}),
    [] = rpc:call(SlaveNode1, syn, get_members, [custom_scope_ab, {group, "one"}]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, get_members, [custom_scope_ab, {group, "one"}]),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:get_members(custom_scope_bc, {group, "one"}),
    [] = rpc:call(SlaveNode1, syn, get_members, [custom_scope_bc, {group, "one"}]),
    [] = rpc:call(SlaveNode2, syn, get_members, [custom_scope_bc, {group, "one"}]),
    [] = syn:get_members(custom_scope_ab, {group, "two"}),
    [] = rpc:call(SlaveNode1, syn, get_members, [custom_scope_ab, {group, "two"}]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, get_members, [custom_scope_ab, {group, "two"}]),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:get_members(custom_scope_bc, {group, "two"}),
    [] = rpc:call(SlaveNode1, syn, get_members, [custom_scope_bc, {group, "two"}]),
    [] = rpc:call(SlaveNode2, syn, get_members, [custom_scope_bc, {group, "two"}]),

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
        fun() -> lists:sort(syn:get_members(custom_scope_ab, {group, "one"})) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, <<"with meta">>}]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, get_members, [custom_scope_ab, {group, "one"}])) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, get_members, [custom_scope_ab, {group, "one"}]),
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, "with-meta-2"}]),
        fun() -> lists:sort(syn:get_members(custom_scope_ab, {group, "two"})) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, "with-meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, get_members, [custom_scope_ab, {group, "two"}])) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, get_members, [custom_scope_ab, {group, "two"}]),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:get_members(custom_scope_bc, {group, "two"}),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn1, undefined}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, get_members, [custom_scope_bc, {group, "two"}])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn1, undefined}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, get_members, [custom_scope_bc, {group, "two"}])) end
    ),
    2 = syn:groups_count(custom_scope_ab),
    2 = syn:groups_count(custom_scope_ab, node()),
    0 = syn:groups_count(custom_scope_ab, SlaveNode1),
    0 = syn:groups_count(custom_scope_ab, SlaveNode2),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:groups_count(custom_scope_bc),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:groups_count(custom_scope_bc, node()),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:groups_count(custom_scope_bc, SlaveNode1),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:groups_count(custom_scope_bc, SlaveNode2),
    2 = rpc:call(SlaveNode1, syn, groups_count, [custom_scope_ab]),
    2 = rpc:call(SlaveNode1, syn, groups_count, [custom_scope_ab, node()]),
    0 = rpc:call(SlaveNode1, syn, groups_count, [custom_scope_ab, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, groups_count, [custom_scope_ab, SlaveNode2]),
    1 = rpc:call(SlaveNode1, syn, groups_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode1, syn, groups_count, [custom_scope_bc, node()]),
    1 = rpc:call(SlaveNode1, syn, groups_count, [custom_scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, groups_count, [custom_scope_bc, SlaveNode2]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, groups_count, [custom_scope_ab]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, groups_count, [custom_scope_ab, node()]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, groups_count, [custom_scope_ab, SlaveNode1]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, groups_count, [custom_scope_ab, SlaveNode2]),
    1 = rpc:call(SlaveNode2, syn, groups_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode2, syn, groups_count, [custom_scope_bc, node()]),
    1 = rpc:call(SlaveNode2, syn, groups_count, [custom_scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode2, syn, groups_count, [custom_scope_bc, SlaveNode2]),

    %% re-join to edit meta
    ok = syn:join(custom_scope_ab, {group, "one"}, PidWithMeta, <<"with updated meta">>),
    ok = rpc:call(SlaveNode2, syn, join, [custom_scope_bc, {group, "two"}, PidRemoteOn1, added_meta]), %% updated on slave 2

    %% retrieve
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, <<"with updated meta">>}]),
        fun() -> lists:sort(syn:get_members(custom_scope_ab, {group, "one"})) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, <<"with updated meta">>}]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, get_members, [custom_scope_ab, {group, "one"}])) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, get_members, [custom_scope_ab, {group, "one"}]),
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, "with-meta-2"}]),
        fun() -> lists:sort(syn:get_members(custom_scope_ab, {group, "two"})) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, "with-meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, get_members, [custom_scope_ab, {group, "two"}])) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, get_members, [custom_scope_ab, {group, "two"}]),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:get_members(custom_scope_bc, {group, "two"}),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn1, added_meta}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, get_members, [custom_scope_bc, {group, "two"}])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn1, added_meta}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, get_members, [custom_scope_bc, {group, "two"}])) end
    ),
    2 = syn:groups_count(custom_scope_ab),
    2 = syn:groups_count(custom_scope_ab, node()),
    0 = syn:groups_count(custom_scope_ab, SlaveNode1),
    0 = syn:groups_count(custom_scope_ab, SlaveNode2),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:groups_count(custom_scope_bc),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:groups_count(custom_scope_bc, node()),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:groups_count(custom_scope_bc, SlaveNode1),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:groups_count(custom_scope_bc, SlaveNode2),
    2 = rpc:call(SlaveNode1, syn, groups_count, [custom_scope_ab]),
    2 = rpc:call(SlaveNode1, syn, groups_count, [custom_scope_ab, node()]),
    0 = rpc:call(SlaveNode1, syn, groups_count, [custom_scope_ab, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, groups_count, [custom_scope_ab, SlaveNode2]),
    1 = rpc:call(SlaveNode1, syn, groups_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode1, syn, groups_count, [custom_scope_bc, node()]),
    1 = rpc:call(SlaveNode1, syn, groups_count, [custom_scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, groups_count, [custom_scope_bc, SlaveNode2]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, groups_count, [custom_scope_ab]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, groups_count, [custom_scope_ab, node()]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, groups_count, [custom_scope_ab, SlaveNode1]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, groups_count, [custom_scope_ab, SlaveNode2]),
    1 = rpc:call(SlaveNode2, syn, groups_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode2, syn, groups_count, [custom_scope_bc, node()]),
    1 = rpc:call(SlaveNode2, syn, groups_count, [custom_scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode2, syn, groups_count, [custom_scope_bc, SlaveNode2]),

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
        fun() -> lists:sort(syn:get_members(custom_scope_ab, {group, "one"})) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, get_members, [custom_scope_ab, {group, "one"}])) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, get_members, [custom_scope_ab, {group, "one"}]),
    syn_test_suite_helper:assert_wait(
        [{PidWithMeta, "with-meta-2"}],
        fun() -> lists:sort(syn:get_members(custom_scope_ab, {group, "two"})) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidWithMeta, "with-meta-2"}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, get_members, [custom_scope_ab, {group, "two"}])) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, get_members, [custom_scope_ab, {group, "two"}]),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:get_members(custom_scope_bc, {group, "two"}),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, get_members, [custom_scope_bc, {group, "two"}])) end
    ),
    syn_test_suite_helper:assert_wait(
        [], fun() -> lists:sort(rpc:call(SlaveNode2, syn, get_members, [custom_scope_bc, {group, "two"}])) end
    ),
    1 = syn:groups_count(custom_scope_ab),
    1 = syn:groups_count(custom_scope_ab, node()),
    0 = syn:groups_count(custom_scope_ab, SlaveNode1),
    0 = syn:groups_count(custom_scope_ab, SlaveNode2),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:groups_count(custom_scope_bc),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:groups_count(custom_scope_bc, node()),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:groups_count(custom_scope_bc, SlaveNode1),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:groups_count(custom_scope_bc, SlaveNode2),
    1 = rpc:call(SlaveNode1, syn, groups_count, [custom_scope_ab]),
    1 = rpc:call(SlaveNode1, syn, groups_count, [custom_scope_ab, node()]),
    0 = rpc:call(SlaveNode1, syn, groups_count, [custom_scope_ab, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, groups_count, [custom_scope_ab, SlaveNode2]),
    0 = rpc:call(SlaveNode1, syn, groups_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode1, syn, groups_count, [custom_scope_bc, node()]),
    0 = rpc:call(SlaveNode1, syn, groups_count, [custom_scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, groups_count, [custom_scope_bc, SlaveNode2]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, groups_count, [custom_scope_ab]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, groups_count, [custom_scope_ab, node()]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, groups_count, [custom_scope_ab, SlaveNode1]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, groups_count, [custom_scope_ab, SlaveNode2]),
    0 = rpc:call(SlaveNode2, syn, groups_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode2, syn, groups_count, [custom_scope_bc, node()]),
    0 = rpc:call(SlaveNode2, syn, groups_count, [custom_scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode2, syn, groups_count, [custom_scope_bc, SlaveNode2]),

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
        fun() -> lists:sort(syn:get_members(<<"common-group">>)) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{PidRemoteOn1, "meta-1"}, {PidRemoteOn2, "meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, get_members, [<<"common-group">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{PidRemoteOn1, "meta-1"}, {PidRemoteOn2, "meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, get_members, [<<"common-group">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "other-meta"}],
        fun() -> lists:sort(syn:get_members(<<"group-2">>)) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "other-meta"}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, get_members, [<<"group-2">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "other-meta"}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, get_members, [<<"group-2">>])) end
    ),
    2 = syn:groups_count(default),
    0 = syn:groups_count(default, node()),
    1 = syn:groups_count(default, SlaveNode1),
    2 = syn:groups_count(default, SlaveNode2),
    2 = rpc:call(SlaveNode1, syn, groups_count, [default]),
    0 = rpc:call(SlaveNode1, syn, groups_count, [default, node()]),
    1 = rpc:call(SlaveNode1, syn, groups_count, [default, SlaveNode1]),
    2 = rpc:call(SlaveNode1, syn, groups_count, [default, SlaveNode2]),
    2 = rpc:call(SlaveNode2, syn, groups_count, [default]),
    0 = rpc:call(SlaveNode2, syn, groups_count, [default, node()]),
    1 = rpc:call(SlaveNode2, syn, groups_count, [default, SlaveNode1]),
    2 = rpc:call(SlaveNode2, syn, groups_count, [default, SlaveNode2]),

    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:groups_count(custom_scope_bc),
    syn_test_suite_helper:assert_wait(
        lists:sort([{PidRemoteOn1, "scoped-meta-1"}, {PidRemoteOn2, "scoped-meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, get_members, [custom_scope_bc, <<"scoped-on-bc">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{PidRemoteOn1, "scoped-meta-1"}, {PidRemoteOn2, "scoped-meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, get_members, [custom_scope_bc, <<"scoped-on-bc">>])) end
    ),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:groups_count(custom_scope_bc),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:groups_count(custom_scope_bc, node()),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:groups_count(custom_scope_bc, SlaveNode1),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:groups_count(custom_scope_bc, SlaveNode2),
    1 = rpc:call(SlaveNode1, syn, groups_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode1, syn, groups_count, [custom_scope_bc, node()]),
    1 = rpc:call(SlaveNode1, syn, groups_count, [custom_scope_bc, SlaveNode1]),
    1 = rpc:call(SlaveNode1, syn, groups_count, [custom_scope_bc, SlaveNode2]),
    1 = rpc:call(SlaveNode2, syn, groups_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode2, syn, groups_count, [custom_scope_bc, node()]),
    1 = rpc:call(SlaveNode2, syn, groups_count, [custom_scope_bc, SlaveNode1]),
    1 = rpc:call(SlaveNode2, syn, groups_count, [custom_scope_bc, SlaveNode2]),

    %% partial netsplit (1 cannot see 2)
    rpc:call(SlaveNode1, syn_test_suite_helper, disconnect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node()]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node()]),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        lists:sort([{PidRemoteOn1, "meta-1"}, {PidRemoteOn2, "meta-2"}]),
        fun() -> lists:sort(syn:get_members(<<"common-group">>)) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn1, "meta-1"}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, get_members, [<<"common-group">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "meta-2"}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, get_members, [<<"common-group">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "other-meta"}],
        fun() -> lists:sort(syn:get_members(<<"group-2">>)) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, get_members, [<<"group-2">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "other-meta"}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, get_members, [<<"group-2">>])) end
    ),
    2 = syn:groups_count(default),
    0 = syn:groups_count(default, node()),
    1 = syn:groups_count(default, SlaveNode1),
    2 = syn:groups_count(default, SlaveNode2),
    1 = rpc:call(SlaveNode1, syn, groups_count, [default]),
    0 = rpc:call(SlaveNode1, syn, groups_count, [default, node()]),
    1 = rpc:call(SlaveNode1, syn, groups_count, [default, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, groups_count, [default, SlaveNode2]),
    2 = rpc:call(SlaveNode2, syn, groups_count, [default]),
    0 = rpc:call(SlaveNode2, syn, groups_count, [default, node()]),
    0 = rpc:call(SlaveNode2, syn, groups_count, [default, SlaveNode1]),
    2 = rpc:call(SlaveNode2, syn, groups_count, [default, SlaveNode2]),

    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:groups_count(custom_scope_bc),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn1, "scoped-meta-1"}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, get_members, [custom_scope_bc, <<"scoped-on-bc">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "scoped-meta-2"}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, get_members, [custom_scope_bc, <<"scoped-on-bc">>])) end
    ),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:groups_count(custom_scope_bc),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:groups_count(custom_scope_bc, node()),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:groups_count(custom_scope_bc, SlaveNode1),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:groups_count(custom_scope_bc, SlaveNode2),
    1 = rpc:call(SlaveNode1, syn, groups_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode1, syn, groups_count, [custom_scope_bc, node()]),
    1 = rpc:call(SlaveNode1, syn, groups_count, [custom_scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, groups_count, [custom_scope_bc, SlaveNode2]),
    1 = rpc:call(SlaveNode2, syn, groups_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode2, syn, groups_count, [custom_scope_bc, node()]),
    0 = rpc:call(SlaveNode2, syn, groups_count, [custom_scope_bc, SlaveNode1]),
    1 = rpc:call(SlaveNode2, syn, groups_count, [custom_scope_bc, SlaveNode2]),

    %% re-join
    rpc:call(SlaveNode1, syn_test_suite_helper, connect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node(), SlaveNode1]),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        lists:sort([{PidRemoteOn1, "meta-1"}, {PidRemoteOn2, "meta-2"}]),
        fun() -> lists:sort(syn:get_members(<<"common-group">>)) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{PidRemoteOn1, "meta-1"}, {PidRemoteOn2, "meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, get_members, [<<"common-group">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{PidRemoteOn1, "meta-1"}, {PidRemoteOn2, "meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, get_members, [<<"common-group">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "other-meta"}],
        fun() -> lists:sort(syn:get_members(<<"group-2">>)) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "other-meta"}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, get_members, [<<"group-2">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "other-meta"}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, get_members, [<<"group-2">>])) end
    ),
    2 = syn:groups_count(default),
    0 = syn:groups_count(default, node()),
    1 = syn:groups_count(default, SlaveNode1),
    2 = syn:groups_count(default, SlaveNode2),
    2 = rpc:call(SlaveNode1, syn, groups_count, [default]),
    0 = rpc:call(SlaveNode1, syn, groups_count, [default, node()]),
    1 = rpc:call(SlaveNode1, syn, groups_count, [default, SlaveNode1]),
    2 = rpc:call(SlaveNode1, syn, groups_count, [default, SlaveNode2]),
    2 = rpc:call(SlaveNode2, syn, groups_count, [default]),
    0 = rpc:call(SlaveNode2, syn, groups_count, [default, node()]),
    1 = rpc:call(SlaveNode2, syn, groups_count, [default, SlaveNode1]),
    2 = rpc:call(SlaveNode2, syn, groups_count, [default, SlaveNode2]),

    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:groups_count(custom_scope_bc),
    syn_test_suite_helper:assert_wait(
        lists:sort([{PidRemoteOn1, "scoped-meta-1"}, {PidRemoteOn2, "scoped-meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, get_members, [custom_scope_bc, <<"scoped-on-bc">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{PidRemoteOn1, "scoped-meta-1"}, {PidRemoteOn2, "scoped-meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, get_members, [custom_scope_bc, <<"scoped-on-bc">>])) end
    ),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:groups_count(custom_scope_bc),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:groups_count(custom_scope_bc, node()),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:groups_count(custom_scope_bc, SlaveNode1),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:groups_count(custom_scope_bc, SlaveNode2),
    1 = rpc:call(SlaveNode1, syn, groups_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode1, syn, groups_count, [custom_scope_bc, node()]),
    1 = rpc:call(SlaveNode1, syn, groups_count, [custom_scope_bc, SlaveNode1]),
    1 = rpc:call(SlaveNode1, syn, groups_count, [custom_scope_bc, SlaveNode2]),
    1 = rpc:call(SlaveNode2, syn, groups_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode2, syn, groups_count, [custom_scope_bc, node()]),
    1 = rpc:call(SlaveNode2, syn, groups_count, [custom_scope_bc, SlaveNode1]),
    1 = rpc:call(SlaveNode2, syn, groups_count, [custom_scope_bc, SlaveNode2]).

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
    CurrentNode = node(),

    %% start process
    Pid = syn_test_suite_helper:start_process(),

    %% ---> on join
    ok = syn:join("my-group", Pid, {recipient, self(), <<"meta">>}),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_joined, CurrentNode, default, "my-group", Pid, <<"meta">>},
        {on_process_joined, SlaveNode1, default, "my-group", Pid, <<"meta">>},
        {on_process_joined, SlaveNode2, default, "my-group", Pid, <<"meta">>}
    ]),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% ---> on meta update
    ok = syn:join("my-group", Pid, {recipient, self(), <<"new-meta">>}),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_joined, CurrentNode, default, "my-group", Pid, <<"new-meta">>},
        {on_process_joined, SlaveNode1, default, "my-group", Pid, <<"new-meta">>},
        {on_process_joined, SlaveNode2, default, "my-group", Pid, <<"new-meta">>}
    ]),
    syn_test_suite_helper:assert_empty_queue(self()).
