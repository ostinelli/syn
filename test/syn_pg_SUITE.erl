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
-module(syn_pg_SUITE).

%% callbacks
-export([all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([groups/0, init_per_group/2, end_per_group/2]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% tests
-export([
    three_nodes_discover/1,
    three_nodes_join_leave_and_monitor/1,
    three_nodes_join_filter_unknown_node/1,
    three_nodes_cluster_changes/1,
    three_nodes_custom_event_handler_joined_left/1,
    three_nodes_publish/1,
    three_nodes_multi_call/1,
    three_nodes_group_names/1
]).
-export([
    four_nodes_concurrency/1
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
        {group, three_nodes_pg},
        {group, four_nodes_pg}
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
        {three_nodes_pg, [shuffle], [
            three_nodes_discover,
            three_nodes_join_leave_and_monitor,
            three_nodes_join_filter_unknown_node,
            three_nodes_cluster_changes,
            three_nodes_custom_event_handler_joined_left,
            three_nodes_publish,
            three_nodes_multi_call,
            three_nodes_group_names
        ]},
        {four_nodes_pg, [shuffle], [
            four_nodes_concurrency
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
init_per_group(three_nodes_pg, Config) ->
    case syn_test_suite_helper:init_cluster(3) of
        {error_initializing_cluster, Other} ->
            end_per_group(three_nodes_pg, Config),
            {skip, Other};

        NodesConfig ->
            NodesConfig ++ Config
    end;
init_per_group(four_nodes_pg, Config) ->
    case syn_test_suite_helper:init_cluster(4) of
        {error_initializing_cluster, Other} ->
            end_per_group(four_nodes_pg, Config),
            {skip, Other};

        NodesConfig ->
            NodesConfig ++ Config
    end;

init_per_group(_GroupName, Config) ->
    Config.

%% -------------------------------------------------------------------
%% Function: end_per_group(GroupName, Config0) ->
%%				void() | {save_config,Config1}
%% GroupName = atom()
%% Config0 = Config1 = [tuple()]
%% -------------------------------------------------------------------
end_per_group(three_nodes_pg, Config) ->
    syn_test_suite_helper:end_cluster(3, Config);
end_per_group(four_nodes_pg, Config) ->
    syn_test_suite_helper:end_cluster(4, Config);
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
three_nodes_discover(Config) ->
    %% get slaves
    SlaveNode1 = proplists:get_value(syn_slave_1, Config),
    SlaveNode2 = proplists:get_value(syn_slave_2, Config),

    %% start syn on nodes
    ok = syn:start(),
    ok = rpc:call(SlaveNode1, syn, start, []),
    ok = rpc:call(SlaveNode2, syn, start, []),

    %% add scopes
    ok = syn:add_node_to_scopes([scope_ab]),
    ok = syn:add_node_to_scopes([scope_all]),
    ok = rpc:call(SlaveNode1, syn, add_node_to_scopes, [[scope_ab, scope_bc, scope_all]]),
    ok = rpc:call(SlaveNode2, syn, add_node_to_scopes, [[scope_bc, scope_c, scope_all]]),

    %% subcluster_nodes should return invalid errors
    {'EXIT', {{invalid_scope, custom_abcdef}, _}} = (catch syn_registry:subcluster_nodes(custom_abcdef)),

    %% check
    syn_test_suite_helper:assert_pg_scope_subcluster(node(), scope_ab, [SlaveNode1]),
    syn_test_suite_helper:assert_pg_scope_subcluster(node(), scope_all, [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_pg_scope_subcluster(SlaveNode1, scope_ab, [node()]),
    syn_test_suite_helper:assert_pg_scope_subcluster(SlaveNode1, scope_bc, [SlaveNode2]),
    syn_test_suite_helper:assert_pg_scope_subcluster(SlaveNode1, scope_all, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_pg_scope_subcluster(SlaveNode2, scope_bc, [SlaveNode1]),
    syn_test_suite_helper:assert_pg_scope_subcluster(SlaveNode2, scope_c, []),
    syn_test_suite_helper:assert_pg_scope_subcluster(SlaveNode2, scope_all, [node(), SlaveNode1]),

    %% disconnect node 2 (node 1 can still see node 2)
    syn_test_suite_helper:disconnect_node(SlaveNode2),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node(), SlaveNode2]),

    %% check
    syn_test_suite_helper:assert_pg_scope_subcluster(node(), scope_ab, [SlaveNode1]),
    syn_test_suite_helper:assert_pg_scope_subcluster(node(), scope_all, [SlaveNode1]),
    syn_test_suite_helper:assert_pg_scope_subcluster(SlaveNode1, scope_ab, [node()]),
    syn_test_suite_helper:assert_pg_scope_subcluster(SlaveNode1, scope_bc, [SlaveNode2]),
    syn_test_suite_helper:assert_pg_scope_subcluster(SlaveNode1, scope_all, [node(), SlaveNode2]),

    %% reconnect node 2
    syn_test_suite_helper:connect_node(SlaveNode2),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node(), SlaveNode1]),

    %% check
    syn_test_suite_helper:assert_pg_scope_subcluster(node(), scope_ab, [SlaveNode1]),
    syn_test_suite_helper:assert_pg_scope_subcluster(node(), scope_all, [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_pg_scope_subcluster(SlaveNode1, scope_ab, [node()]),
    syn_test_suite_helper:assert_pg_scope_subcluster(SlaveNode1, scope_bc, [SlaveNode2]),
    syn_test_suite_helper:assert_pg_scope_subcluster(SlaveNode1, scope_all, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_pg_scope_subcluster(SlaveNode2, scope_bc, [SlaveNode1]),
    syn_test_suite_helper:assert_pg_scope_subcluster(SlaveNode2, scope_c, []),
    syn_test_suite_helper:assert_pg_scope_subcluster(SlaveNode2, scope_all, [node(), SlaveNode1]),

    %% crash scope processes
    rpc:call(SlaveNode2, syn_test_suite_helper, kill_process, [syn_registry_scope_bc]),
    rpc:call(SlaveNode2, syn_test_suite_helper, wait_process_name_ready, [syn_registry_scope_bc]),

    %% check
    syn_test_suite_helper:assert_pg_scope_subcluster(node(), scope_ab, [SlaveNode1]),
    syn_test_suite_helper:assert_pg_scope_subcluster(node(), scope_all, [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_pg_scope_subcluster(SlaveNode1, scope_ab, [node()]),
    syn_test_suite_helper:assert_pg_scope_subcluster(SlaveNode1, scope_bc, [SlaveNode2]),
    syn_test_suite_helper:assert_pg_scope_subcluster(SlaveNode1, scope_all, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_pg_scope_subcluster(SlaveNode2, scope_bc, [SlaveNode1]),
    syn_test_suite_helper:assert_pg_scope_subcluster(SlaveNode2, scope_c, []),
    syn_test_suite_helper:assert_pg_scope_subcluster(SlaveNode2, scope_all, [node(), SlaveNode1]),

    %% crash scopes supervisor on local
    syn_test_suite_helper:kill_process(syn_scopes_sup),
    syn_test_suite_helper:wait_process_name_ready(syn_registry_scope_all),

    %% check
    syn_test_suite_helper:assert_pg_scope_subcluster(node(), scope_ab, [SlaveNode1]),
    syn_test_suite_helper:assert_pg_scope_subcluster(node(), scope_all, [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_pg_scope_subcluster(SlaveNode1, scope_ab, [node()]),
    syn_test_suite_helper:assert_pg_scope_subcluster(SlaveNode1, scope_bc, [SlaveNode2]),
    syn_test_suite_helper:assert_pg_scope_subcluster(SlaveNode1, scope_all, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_pg_scope_subcluster(SlaveNode2, scope_bc, [SlaveNode1]),
    syn_test_suite_helper:assert_pg_scope_subcluster(SlaveNode2, scope_c, []),
    syn_test_suite_helper:assert_pg_scope_subcluster(SlaveNode2, scope_all, [node(), SlaveNode1]).

three_nodes_join_leave_and_monitor(Config) ->
    %% get slaves
    SlaveNode1 = proplists:get_value(syn_slave_1, Config),
    SlaveNode2 = proplists:get_value(syn_slave_2, Config),

    %% start syn on nodes
    ok = syn:start(),
    ok = rpc:call(SlaveNode1, syn, start, []),
    ok = rpc:call(SlaveNode2, syn, start, []),

    %% add scopes
    ok = syn:add_node_to_scopes([scope_ab]),
    ok = rpc:call(SlaveNode1, syn, add_node_to_scopes, [[scope_ab, scope_bc]]),
    ok = rpc:call(SlaveNode2, syn, add_node_to_scopes, [[scope_bc]]),

    %% start processes
    Pid = syn_test_suite_helper:start_process(),
    PidWithMeta = syn_test_suite_helper:start_process(),
    PidRemoteOn1 = syn_test_suite_helper:start_process(SlaveNode1),
    PidRemoteOn2 = syn_test_suite_helper:start_process(SlaveNode2),

    %% check
    [] = syn:members(scope_ab, {group, "one"}),
    [] = rpc:call(SlaveNode1, syn, members, [scope_ab, {group, "one"}]),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, members, [scope_ab, {group, "one"}])),
    false = syn:is_member(scope_ab, {group, "one"}, Pid),
    false = syn:is_member(scope_ab, {group, "one"}, PidWithMeta),
    false = syn:is_member(scope_ab, {group, "one"}, PidRemoteOn1),
    false = rpc:call(SlaveNode1, syn, is_member, [scope_ab, {group, "one"}, Pid]),
    false = rpc:call(SlaveNode1, syn, is_member, [scope_ab, {group, "one"}, PidWithMeta]),
    false = rpc:call(SlaveNode1, syn, is_member, [scope_ab, {group, "one"}, PidRemoteOn1]),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, is_member, [scope_ab, {group, "one"}, Pid])),

    [] = syn:local_members(scope_ab, {group, "one"}),
    [] = rpc:call(SlaveNode1, syn, local_members, [scope_ab, {group, "one"}]),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, local_members, [scope_ab, {group, "one"}])),
    false = syn:is_local_member(scope_ab, {group, "one"}, Pid),
    false = syn:is_local_member(scope_ab, {group, "one"}, PidWithMeta),
    false = syn:is_local_member(scope_ab, {group, "one"}, PidRemoteOn1),
    false = rpc:call(SlaveNode1, syn, is_local_member, [scope_ab, {group, "one"}, Pid]),
    false = rpc:call(SlaveNode1, syn, is_local_member, [scope_ab, {group, "one"}, PidWithMeta]),
    false = rpc:call(SlaveNode1, syn, is_local_member, [scope_ab, {group, "one"}, PidRemoteOn1]),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, is_local_member, [scope_ab, {group, "one"}, Pid])),

    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:members(scope_bc, {group, "one"})),
    [] = rpc:call(SlaveNode1, syn, members, [scope_bc, {group, "one"}]),
    [] = rpc:call(SlaveNode2, syn, members, [scope_bc, {group, "one"}]),

    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:local_members(scope_bc, {group, "one"})),
    [] = rpc:call(SlaveNode1, syn, local_members, [scope_bc, {group, "one"}]),
    [] = rpc:call(SlaveNode2, syn, local_members, [scope_bc, {group, "one"}]),

    [] = syn:members(scope_ab, {group, "two"}),
    [] = rpc:call(SlaveNode1, syn, members, [scope_ab, {group, "two"}]),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, members, [scope_ab, {group, "two"}])),
    false = syn:is_member(scope_ab, {group, "two"}, Pid),
    false = syn:is_member(scope_ab, {group, "two"}, PidWithMeta),
    false = syn:is_member(scope_ab, {group, "two"}, PidRemoteOn1),
    false = rpc:call(SlaveNode1, syn, is_member, [scope_ab, {group, "two"}, Pid]),
    false = rpc:call(SlaveNode1, syn, is_member, [scope_ab, {group, "two"}, PidWithMeta]),
    false = rpc:call(SlaveNode1, syn, is_member, [scope_ab, {group, "two"}, PidRemoteOn1]),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, is_member, [scope_ab, {group, "two"}, Pid])),

    [] = syn:local_members(scope_ab, {group, "two"}),
    [] = rpc:call(SlaveNode1, syn, local_members, [scope_ab, {group, "two"}]),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, local_members, [scope_ab, {group, "two"}])),
    false = syn:is_local_member(scope_ab, {group, "two"}, Pid),
    false = syn:is_local_member(scope_ab, {group, "two"}, PidWithMeta),
    false = syn:is_local_member(scope_ab, {group, "two"}, PidRemoteOn1),
    false = rpc:call(SlaveNode1, syn, is_local_member, [scope_ab, {group, "two"}, Pid]),
    false = rpc:call(SlaveNode1, syn, is_local_member, [scope_ab, {group, "two"}, PidWithMeta]),
    false = rpc:call(SlaveNode1, syn, is_local_member, [scope_ab, {group, "two"}, PidRemoteOn1]),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, is_local_member, [scope_ab, {group, "two"}, Pid])),

    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:members(scope_bc, {group, "two"})),
    [] = rpc:call(SlaveNode1, syn, members, [scope_bc, {group, "two"}]),
    [] = rpc:call(SlaveNode2, syn, members, [scope_bc, {group, "two"}]),

    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:local_members(scope_bc, {group, "two"})),
    [] = rpc:call(SlaveNode1, syn, local_members, [scope_bc, {group, "two"}]),
    [] = rpc:call(SlaveNode2, syn, local_members, [scope_bc, {group, "two"}]),

    %% join
    ok = syn:join(scope_ab, {group, "one"}, Pid),
    ok = syn:join(scope_ab, {group, "one"}, PidWithMeta, <<"with meta">>),
    ok = rpc:call(SlaveNode1, syn, join, [scope_bc, {group, "two"}, PidRemoteOn1]),
    ok = syn:join(scope_ab, {group, "two"}, Pid),
    ok = syn:join(scope_ab, {group, "two"}, PidWithMeta, "with-meta-2"),

    %% errors
    {error, not_alive} = syn:join(scope_ab, {"pid not alive"}, list_to_pid("<0.9999.0>")),
    {error, not_in_group} = syn:leave(scope_ab, {group, "three"}, Pid),
    {'EXIT', {{invalid_remote_scope, scope_ab, SlaveNode2}, _}} = (catch syn:join(scope_ab, {group, "one"}, PidRemoteOn2)),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, <<"with meta">>}]),
        fun() -> lists:sort(syn:members(scope_ab, {group, "one"})) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, <<"with meta">>}]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [scope_ab, {group, "one"}])) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, members, [scope_ab, {group, "one"}])),
    true = syn:is_member(scope_ab, {group, "one"}, Pid),
    true = syn:is_member(scope_ab, {group, "one"}, PidWithMeta),
    false = syn:is_member(scope_ab, {group, "one"}, PidRemoteOn1),
    true = rpc:call(SlaveNode1, syn, is_member, [scope_ab, {group, "one"}, Pid]),
    true = rpc:call(SlaveNode1, syn, is_member, [scope_ab, {group, "one"}, PidWithMeta]),
    false = rpc:call(SlaveNode1, syn, is_member, [scope_ab, {group, "one"}, PidRemoteOn1]),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, is_member, [scope_ab, {group, "one"}, Pid])),

    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, <<"with meta">>}]),
        fun() -> lists:sort(syn:local_members(scope_ab, {group, "one"})) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [scope_ab, {group, "one"}])) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, local_members, [scope_ab, {group, "one"}])),
    true = syn:is_local_member(scope_ab, {group, "one"}, Pid),
    true = syn:is_local_member(scope_ab, {group, "one"}, PidWithMeta),
    false = syn:is_local_member(scope_ab, {group, "one"}, PidRemoteOn1),
    false = rpc:call(SlaveNode1, syn, is_local_member, [scope_ab, {group, "one"}, Pid]),
    false = rpc:call(SlaveNode1, syn, is_local_member, [scope_ab, {group, "one"}, PidWithMeta]),
    false = rpc:call(SlaveNode1, syn, is_local_member, [scope_ab, {group, "one"}, PidRemoteOn1]),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, is_local_member, [scope_ab, {group, "one"}, Pid])),

    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, "with-meta-2"}]),
        fun() -> lists:sort(syn:members(scope_ab, {group, "two"})) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, "with-meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [scope_ab, {group, "two"}])) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, members, [scope_ab, {group, "two"}])),
    true = syn:is_member(scope_ab, {group, "two"}, Pid),
    true = syn:is_member(scope_ab, {group, "two"}, PidWithMeta),
    false = syn:is_member(scope_ab, {group, "two"}, PidRemoteOn1),
    true = rpc:call(SlaveNode1, syn, is_member, [scope_ab, {group, "two"}, Pid]),
    true = rpc:call(SlaveNode1, syn, is_member, [scope_ab, {group, "two"}, PidWithMeta]),
    false = rpc:call(SlaveNode1, syn, is_member, [scope_ab, {group, "two"}, PidRemoteOn1]),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, is_member, [scope_ab, {group, "two"}, Pid])),

    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, "with-meta-2"}]),
        fun() -> lists:sort(syn:local_members(scope_ab, {group, "two"})) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [scope_ab, {group, "two"}])) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, local_members, [scope_ab, {group, "two"}])),
    true = syn:is_local_member(scope_ab, {group, "two"}, Pid),
    true = syn:is_local_member(scope_ab, {group, "two"}, PidWithMeta),
    false = syn:is_local_member(scope_ab, {group, "two"}, PidRemoteOn1),
    false = rpc:call(SlaveNode1, syn, is_local_member, [scope_ab, {group, "two"}, Pid]),
    false = rpc:call(SlaveNode1, syn, is_local_member, [scope_ab, {group, "two"}, PidWithMeta]),
    false = rpc:call(SlaveNode1, syn, is_local_member, [scope_ab, {group, "two"}, PidRemoteOn1]),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, is_local_member, [scope_ab, {group, "two"}, Pid])),

    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:members(scope_bc, {group, "two"})),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn1, undefined}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [scope_bc, {group, "two"}])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn1, undefined}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, members, [scope_bc, {group, "two"}])) end
    ),

    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:local_members(scope_bc, {group, "two"})),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn1, undefined}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [scope_bc, {group, "two"}])) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, local_members, [scope_bc, {group, "two"}])) end
    ),

    2 = syn:group_count(scope_ab),
    2 = syn:group_count(scope_ab, node()),
    0 = syn:group_count(scope_ab, SlaveNode1),
    0 = syn:group_count(scope_ab, SlaveNode2),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:group_count(scope_bc)),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:group_count(scope_bc, node())),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:group_count(scope_bc, SlaveNode1)),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:group_count(scope_bc, SlaveNode2)),
    2 = rpc:call(SlaveNode1, syn, group_count, [scope_ab]),
    2 = rpc:call(SlaveNode1, syn, group_count, [scope_ab, node()]),
    0 = rpc:call(SlaveNode1, syn, group_count, [scope_ab, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, group_count, [scope_ab, SlaveNode2]),
    1 = rpc:call(SlaveNode1, syn, group_count, [scope_bc]),
    0 = rpc:call(SlaveNode1, syn, group_count, [scope_bc, node()]),
    1 = rpc:call(SlaveNode1, syn, group_count, [scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, group_count, [scope_bc, SlaveNode2]),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, group_count, [scope_ab])),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, group_count, [scope_ab, node()])),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, group_count, [scope_ab, SlaveNode1])),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, group_count, [scope_ab, SlaveNode2])),
    1 = rpc:call(SlaveNode2, syn, group_count, [scope_bc]),
    0 = rpc:call(SlaveNode2, syn, group_count, [scope_bc, node()]),
    1 = rpc:call(SlaveNode2, syn, group_count, [scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode2, syn, group_count, [scope_bc, SlaveNode2]),

    %% re-join to edit meta
    ok = syn:join(scope_ab, {group, "one"}, PidWithMeta, <<"with updated meta">>),
    ok = rpc:call(SlaveNode2, syn, join, [scope_bc, {group, "two"}, PidRemoteOn1, added_meta]), %% updated on slave 2

    %% retrieve
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, <<"with updated meta">>}]),
        fun() -> lists:sort(syn:members(scope_ab, {group, "one"})) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, <<"with updated meta">>}]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [scope_ab, {group, "one"}])) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, members, [scope_ab, {group, "one"}])),

    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, <<"with updated meta">>}]),
        fun() -> lists:sort(syn:local_members(scope_ab, {group, "one"})) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [scope_ab, {group, "one"}])) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, local_members, [scope_ab, {group, "one"}])),

    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, "with-meta-2"}]),
        fun() -> lists:sort(syn:members(scope_ab, {group, "two"})) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, "with-meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [scope_ab, {group, "two"}])) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, members, [scope_ab, {group, "two"}])),

    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, "with-meta-2"}]),
        fun() -> lists:sort(syn:local_members(scope_ab, {group, "two"})) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [scope_ab, {group, "two"}])) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, local_members, [scope_ab, {group, "two"}])),

    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:members(scope_bc, {group, "two"})),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn1, added_meta}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [scope_bc, {group, "two"}])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn1, added_meta}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, members, [scope_bc, {group, "two"}])) end
    ),

    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:local_members(scope_bc, {group, "two"})),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn1, added_meta}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [scope_bc, {group, "two"}])) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, local_members, [scope_bc, {group, "two"}])) end
    ),

    2 = syn:group_count(scope_ab),
    2 = syn:group_count(scope_ab, node()),
    0 = syn:group_count(scope_ab, SlaveNode1),
    0 = syn:group_count(scope_ab, SlaveNode2),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:group_count(scope_bc)),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:group_count(scope_bc, node())),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:group_count(scope_bc, SlaveNode1)),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:group_count(scope_bc, SlaveNode2)),
    2 = rpc:call(SlaveNode1, syn, group_count, [scope_ab]),
    2 = rpc:call(SlaveNode1, syn, group_count, [scope_ab, node()]),
    0 = rpc:call(SlaveNode1, syn, group_count, [scope_ab, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, group_count, [scope_ab, SlaveNode2]),
    1 = rpc:call(SlaveNode1, syn, group_count, [scope_bc]),
    0 = rpc:call(SlaveNode1, syn, group_count, [scope_bc, node()]),
    1 = rpc:call(SlaveNode1, syn, group_count, [scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, group_count, [scope_bc, SlaveNode2]),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, group_count, [scope_ab])),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, group_count, [scope_ab, node()])),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, group_count, [scope_ab, SlaveNode1])),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, group_count, [scope_ab, SlaveNode2])),
    1 = rpc:call(SlaveNode2, syn, group_count, [scope_bc]),
    0 = rpc:call(SlaveNode2, syn, group_count, [scope_bc, node()]),
    1 = rpc:call(SlaveNode2, syn, group_count, [scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode2, syn, group_count, [scope_bc, SlaveNode2]),

    syn:join(scope_ab, {group, "two"}, PidRemoteOn1),
    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, "with-meta-2"}, {PidRemoteOn1, undefined}]),
        fun() -> lists:sort(syn:members(scope_ab, {group, "two"})) end
    ),

    %% crash scope process to ensure that monitors get recreated
    exit(whereis(syn_pg_scope_ab), kill),
    syn_test_suite_helper:wait_process_name_ready(syn_pg_scope_ab),

    syn_test_suite_helper:assert_wait(
        lists:sort([{Pid, undefined}, {PidWithMeta, "with-meta-2"}, {PidRemoteOn1, undefined}]),
        fun() -> lists:sort(syn:members(scope_ab, {group, "two"})) end
    ),

    %% kill process
    syn_test_suite_helper:kill_process(Pid),
    syn_test_suite_helper:kill_process(PidRemoteOn1),
    %% leave
    ok = syn:leave(scope_ab, {group, "one"}, PidWithMeta),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(syn:members(scope_ab, {group, "one"})) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [scope_ab, {group, "one"}])) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, members, [scope_ab, {group, "one"}])),
    false = syn:is_member(scope_ab, {group, "one"}, Pid),
    false = syn:is_member(scope_ab, {group, "one"}, PidWithMeta),
    false = syn:is_member(scope_ab, {group, "one"}, PidRemoteOn1),
    false = rpc:call(SlaveNode1, syn, is_member, [scope_ab, {group, "one"}, Pid]),
    false = rpc:call(SlaveNode1, syn, is_member, [scope_ab, {group, "one"}, PidWithMeta]),
    false = rpc:call(SlaveNode1, syn, is_member, [scope_ab, {group, "one"}, PidRemoteOn1]),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, is_member, [scope_ab, {group, "one"}, Pid])),

    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(syn:local_members(scope_ab, {group, "one"})) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [scope_ab, {group, "one"}])) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, local_members, [scope_ab, {group, "one"}])),
    false = syn:is_local_member(scope_ab, {group, "one"}, Pid),
    false = syn:is_local_member(scope_ab, {group, "one"}, PidWithMeta),
    false = syn:is_local_member(scope_ab, {group, "one"}, PidRemoteOn1),
    false = rpc:call(SlaveNode1, syn, is_local_member, [scope_ab, {group, "one"}, Pid]),
    false = rpc:call(SlaveNode1, syn, is_local_member, [scope_ab, {group, "one"}, PidWithMeta]),
    false = rpc:call(SlaveNode1, syn, is_local_member, [scope_ab, {group, "one"}, PidRemoteOn1]),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, is_local_member, [scope_ab, {group, "one"}, Pid])),

    syn_test_suite_helper:assert_wait(
        [{PidWithMeta, "with-meta-2"}],
        fun() -> lists:sort(syn:members(scope_ab, {group, "two"})) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidWithMeta, "with-meta-2"}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [scope_ab, {group, "two"}])) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, members, [scope_ab, {group, "two"}])),
    false = syn:is_member(scope_ab, {group, "two"}, Pid),
    true = syn:is_member(scope_ab, {group, "two"}, PidWithMeta),
    false = syn:is_member(scope_ab, {group, "two"}, PidRemoteOn1),
    false = rpc:call(SlaveNode1, syn, is_member, [scope_ab, {group, "two"}, Pid]),
    true = rpc:call(SlaveNode1, syn, is_member, [scope_ab, {group, "two"}, PidWithMeta]),
    false = rpc:call(SlaveNode1, syn, is_member, [scope_ab, {group, "two"}, PidRemoteOn1]),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, is_member, [scope_ab, {group, "two"}, Pid])),

    syn_test_suite_helper:assert_wait(
        [{PidWithMeta, "with-meta-2"}],
        fun() -> lists:sort(syn:local_members(scope_ab, {group, "two"})) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [scope_ab, {group, "two"}])) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, local_members, [scope_ab, {group, "two"}])),
    false = syn:is_local_member(scope_ab, {group, "two"}, Pid),
    true = syn:is_local_member(scope_ab, {group, "two"}, PidWithMeta),
    false = syn:is_local_member(scope_ab, {group, "two"}, PidRemoteOn1),
    false = rpc:call(SlaveNode1, syn, is_local_member, [scope_ab, {group, "two"}, Pid]),
    false = rpc:call(SlaveNode1, syn, is_local_member, [scope_ab, {group, "two"}, PidWithMeta]),
    false = rpc:call(SlaveNode1, syn, is_local_member, [scope_ab, {group, "two"}, PidRemoteOn1]),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, is_local_member, [scope_ab, {group, "two"}, Pid])),

    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:members(scope_bc, {group, "two"})),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [scope_bc, {group, "two"}])) end
    ),
    syn_test_suite_helper:assert_wait(
        [], fun() -> lists:sort(rpc:call(SlaveNode2, syn, members, [scope_bc, {group, "two"}])) end
    ),

    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:local_members(scope_bc, {group, "two"})),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [scope_bc, {group, "two"}])) end
    ),
    syn_test_suite_helper:assert_wait(
        [], fun() -> lists:sort(rpc:call(SlaveNode2, syn, local_members, [scope_bc, {group, "two"}])) end
    ),

    1 = syn:group_count(scope_ab),
    1 = syn:group_count(scope_ab, node()),
    0 = syn:group_count(scope_ab, SlaveNode1),
    0 = syn:group_count(scope_ab, SlaveNode2),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:group_count(scope_bc)),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:group_count(scope_bc, node())),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:group_count(scope_bc, SlaveNode1)),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:group_count(scope_bc, SlaveNode2)),
    1 = rpc:call(SlaveNode1, syn, group_count, [scope_ab]),
    1 = rpc:call(SlaveNode1, syn, group_count, [scope_ab, node()]),
    0 = rpc:call(SlaveNode1, syn, group_count, [scope_ab, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, group_count, [scope_ab, SlaveNode2]),
    0 = rpc:call(SlaveNode1, syn, group_count, [scope_bc]),
    0 = rpc:call(SlaveNode1, syn, group_count, [scope_bc, node()]),
    0 = rpc:call(SlaveNode1, syn, group_count, [scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, group_count, [scope_bc, SlaveNode2]),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, group_count, [scope_ab])),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, group_count, [scope_ab, node()])),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, group_count, [scope_ab, SlaveNode1])),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, group_count, [scope_ab, SlaveNode2])),
    0 = rpc:call(SlaveNode2, syn, group_count, [scope_bc]),
    0 = rpc:call(SlaveNode2, syn, group_count, [scope_bc, node()]),
    0 = rpc:call(SlaveNode2, syn, group_count, [scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode2, syn, group_count, [scope_bc, SlaveNode2]),

    %% errors
    {error, not_in_group} = syn:leave(scope_ab, {group, "one"}, PidWithMeta).

three_nodes_join_filter_unknown_node(Config) ->
    %% get slaves
    SlaveNode1 = proplists:get_value(syn_slave_1, Config),
    SlaveNode2 = proplists:get_value(syn_slave_2, Config),

    %% start syn on 1 and 2
    ok = rpc:call(SlaveNode1, syn, start, []),
    ok = rpc:call(SlaveNode2, syn, start, []),

    %% add scopes
    ok = rpc:call(SlaveNode1, syn, add_node_to_scopes, [[scope_bc]]),
    ok = rpc:call(SlaveNode2, syn, add_node_to_scopes, [[scope_bc]]),

    %% send sync message from out of scope node
    InvalidPid = syn_test_suite_helper:start_process(),
    {syn_pg_scope_bc, SlaveNode1} ! {'3.0', sync_join, <<"group-name">>, InvalidPid, undefined, os:system_time(millisecond), normal},

    %% check
    false = rpc:call(SlaveNode1, syn, is_member, [scope_bc, <<"group-name">>, InvalidPid]).

three_nodes_cluster_changes(Config) ->
    %% get slaves
    SlaveNode1 = proplists:get_value(syn_slave_1, Config),
    SlaveNode2 = proplists:get_value(syn_slave_2, Config),

    %% disconnect 1 from 2
    rpc:call(SlaveNode1, syn_test_suite_helper, disconnect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node()]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node()]),

    %% start syn on 1 and 2, nodes don't know of each other
    ok = rpc:call(SlaveNode1, syn, start, []),
    ok = rpc:call(SlaveNode2, syn, start, []),

    %% add scopes
    ok = rpc:call(SlaveNode1, syn, add_node_to_scopes, [[scope_all, scope_bc]]),
    ok = rpc:call(SlaveNode2, syn, add_node_to_scopes, [[scope_all, scope_bc]]),

    %% start processes
    PidRemoteOn1 = syn_test_suite_helper:start_process(SlaveNode1),
    PidRemoteOn2 = syn_test_suite_helper:start_process(SlaveNode2),

    %% join
    ok = rpc:call(SlaveNode1, syn, join, [scope_all, <<"common-group">>, PidRemoteOn1, "meta-1"]),
    ok = rpc:call(SlaveNode2, syn, join, [scope_all, <<"common-group">>, PidRemoteOn2, "meta-2"]),
    ok = rpc:call(SlaveNode2, syn, join, [scope_all, <<"group-2">>, PidRemoteOn2, "other-meta"]),
    ok = rpc:call(SlaveNode1, syn, join, [scope_bc, <<"scoped-on-bc">>, PidRemoteOn1, "scoped-meta-1"]),
    ok = rpc:call(SlaveNode2, syn, join, [scope_bc, <<"scoped-on-bc">>, PidRemoteOn2, "scoped-meta-2"]),

    %% form full cluster
    ok = syn:start(),
    ok = syn:add_node_to_scopes([scope_all]),

    rpc:call(SlaveNode1, syn_test_suite_helper, connect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node(), SlaveNode1]),
    syn_test_suite_helper:wait_process_name_ready(syn_pg_scope_all),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        lists:sort([{PidRemoteOn1, "meta-1"}, {PidRemoteOn2, "meta-2"}]),
        fun() -> lists:sort(syn:members(scope_all, <<"common-group">>)) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{PidRemoteOn1, "meta-1"}, {PidRemoteOn2, "meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [scope_all, <<"common-group">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{PidRemoteOn1, "meta-1"}, {PidRemoteOn2, "meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, members, [scope_all, <<"common-group">>])) end
    ),

    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(syn:local_members(scope_all, <<"common-group">>)) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn1, "meta-1"}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [scope_all, <<"common-group">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "meta-2"}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, local_members, [scope_all, <<"common-group">>])) end
    ),

    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "other-meta"}],
        fun() -> lists:sort(syn:members(scope_all, <<"group-2">>)) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "other-meta"}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [scope_all, <<"group-2">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "other-meta"}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, members, [scope_all, <<"group-2">>])) end
    ),

    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(syn:local_members(scope_all, <<"group-2">>)) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [scope_all, <<"group-2">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "other-meta"}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, local_members, [scope_all, <<"group-2">>])) end
    ),

    2 = syn:group_count(scope_all),
    0 = syn:group_count(scope_all, node()),
    1 = syn:group_count(scope_all, SlaveNode1),
    2 = syn:group_count(scope_all, SlaveNode2),
    2 = rpc:call(SlaveNode1, syn, group_count, [scope_all]),
    0 = rpc:call(SlaveNode1, syn, group_count, [scope_all, node()]),
    1 = rpc:call(SlaveNode1, syn, group_count, [scope_all, SlaveNode1]),
    2 = rpc:call(SlaveNode1, syn, group_count, [scope_all, SlaveNode2]),
    2 = rpc:call(SlaveNode2, syn, group_count, [scope_all]),
    0 = rpc:call(SlaveNode2, syn, group_count, [scope_all, node()]),
    1 = rpc:call(SlaveNode2, syn, group_count, [scope_all, SlaveNode1]),
    2 = rpc:call(SlaveNode2, syn, group_count, [scope_all, SlaveNode2]),

    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:members(scope_bc, <<"scoped-on-bc">>)),
    syn_test_suite_helper:assert_wait(
        lists:sort([{PidRemoteOn1, "scoped-meta-1"}, {PidRemoteOn2, "scoped-meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [scope_bc, <<"scoped-on-bc">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{PidRemoteOn1, "scoped-meta-1"}, {PidRemoteOn2, "scoped-meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, members, [scope_bc, <<"scoped-on-bc">>])) end
    ),

    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:local_members(scope_bc, <<"scoped-on-bc">>)),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn1, "scoped-meta-1"}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [scope_bc, <<"scoped-on-bc">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "scoped-meta-2"}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, local_members, [scope_bc, <<"scoped-on-bc">>])) end
    ),

    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:group_count(scope_bc)),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:group_count(scope_bc, node())),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:group_count(scope_bc, SlaveNode1)),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:group_count(scope_bc, SlaveNode2)),
    1 = rpc:call(SlaveNode1, syn, group_count, [scope_bc]),
    0 = rpc:call(SlaveNode1, syn, group_count, [scope_bc, node()]),
    1 = rpc:call(SlaveNode1, syn, group_count, [scope_bc, SlaveNode1]),
    1 = rpc:call(SlaveNode1, syn, group_count, [scope_bc, SlaveNode2]),
    1 = rpc:call(SlaveNode2, syn, group_count, [scope_bc]),
    0 = rpc:call(SlaveNode2, syn, group_count, [scope_bc, node()]),
    1 = rpc:call(SlaveNode2, syn, group_count, [scope_bc, SlaveNode1]),
    1 = rpc:call(SlaveNode2, syn, group_count, [scope_bc, SlaveNode2]),

    %% partial netsplit (1 cannot see 2)
    rpc:call(SlaveNode1, syn_test_suite_helper, disconnect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node()]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node()]),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        lists:sort([{PidRemoteOn1, "meta-1"}, {PidRemoteOn2, "meta-2"}]),
        fun() -> lists:sort(syn:members(scope_all, <<"common-group">>)) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn1, "meta-1"}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [scope_all, <<"common-group">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "meta-2"}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, members, [scope_all, <<"common-group">>])) end
    ),

    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(syn:local_members(scope_all, <<"common-group">>)) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn1, "meta-1"}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [scope_all, <<"common-group">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "meta-2"}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, local_members, [scope_all, <<"common-group">>])) end
    ),

    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "other-meta"}],
        fun() -> lists:sort(syn:members(scope_all, <<"group-2">>)) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [scope_all, <<"group-2">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "other-meta"}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, members, [scope_all, <<"group-2">>])) end
    ),

    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(syn:local_members(scope_all, <<"group-2">>)) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [scope_all, <<"group-2">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "other-meta"}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, local_members, [scope_all, <<"group-2">>])) end
    ),

    2 = syn:group_count(scope_all),
    0 = syn:group_count(scope_all, node()),
    1 = syn:group_count(scope_all, SlaveNode1),
    2 = syn:group_count(scope_all, SlaveNode2),
    1 = rpc:call(SlaveNode1, syn, group_count, [scope_all]),
    0 = rpc:call(SlaveNode1, syn, group_count, [scope_all, node()]),
    1 = rpc:call(SlaveNode1, syn, group_count, [scope_all, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, group_count, [scope_all, SlaveNode2]),
    2 = rpc:call(SlaveNode2, syn, group_count, [scope_all]),
    0 = rpc:call(SlaveNode2, syn, group_count, [scope_all, node()]),
    0 = rpc:call(SlaveNode2, syn, group_count, [scope_all, SlaveNode1]),
    2 = rpc:call(SlaveNode2, syn, group_count, [scope_all, SlaveNode2]),

    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:members(scope_bc, <<"scoped-on-bc">>)),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn1, "scoped-meta-1"}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [scope_bc, <<"scoped-on-bc">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "scoped-meta-2"}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, members, [scope_bc, <<"scoped-on-bc">>])) end
    ),

    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:local_members(scope_bc, <<"scoped-on-bc">>)),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn1, "scoped-meta-1"}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [scope_bc, <<"scoped-on-bc">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "scoped-meta-2"}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, local_members, [scope_bc, <<"scoped-on-bc">>])) end
    ),

    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:group_count(scope_bc)),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:group_count(scope_bc, node())),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:group_count(scope_bc, SlaveNode1)),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:group_count(scope_bc, SlaveNode2)),
    1 = rpc:call(SlaveNode1, syn, group_count, [scope_bc]),
    0 = rpc:call(SlaveNode1, syn, group_count, [scope_bc, node()]),
    1 = rpc:call(SlaveNode1, syn, group_count, [scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, group_count, [scope_bc, SlaveNode2]),
    1 = rpc:call(SlaveNode2, syn, group_count, [scope_bc]),
    0 = rpc:call(SlaveNode2, syn, group_count, [scope_bc, node()]),
    0 = rpc:call(SlaveNode2, syn, group_count, [scope_bc, SlaveNode1]),
    1 = rpc:call(SlaveNode2, syn, group_count, [scope_bc, SlaveNode2]),

    %% re-join
    rpc:call(SlaveNode1, syn_test_suite_helper, connect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node(), SlaveNode1]),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        lists:sort([{PidRemoteOn1, "meta-1"}, {PidRemoteOn2, "meta-2"}]),
        fun() -> lists:sort(syn:members(scope_all, <<"common-group">>)) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{PidRemoteOn1, "meta-1"}, {PidRemoteOn2, "meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [scope_all, <<"common-group">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{PidRemoteOn1, "meta-1"}, {PidRemoteOn2, "meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, members, [scope_all, <<"common-group">>])) end
    ),

    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(syn:local_members(scope_all, <<"common-group">>)) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn1, "meta-1"}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [scope_all, <<"common-group">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "meta-2"}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, local_members, [scope_all, <<"common-group">>])) end
    ),

    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "other-meta"}],
        fun() -> lists:sort(syn:members(scope_all, <<"group-2">>)) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "other-meta"}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [scope_all, <<"group-2">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "other-meta"}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, members, [scope_all, <<"group-2">>])) end
    ),

    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(syn:local_members(scope_all, <<"group-2">>)) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [scope_all, <<"group-2">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "other-meta"}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, local_members, [scope_all, <<"group-2">>])) end
    ),

    2 = syn:group_count(scope_all),
    0 = syn:group_count(scope_all, node()),
    1 = syn:group_count(scope_all, SlaveNode1),
    2 = syn:group_count(scope_all, SlaveNode2),
    2 = rpc:call(SlaveNode1, syn, group_count, [scope_all]),
    0 = rpc:call(SlaveNode1, syn, group_count, [scope_all, node()]),
    1 = rpc:call(SlaveNode1, syn, group_count, [scope_all, SlaveNode1]),
    2 = rpc:call(SlaveNode1, syn, group_count, [scope_all, SlaveNode2]),
    2 = rpc:call(SlaveNode2, syn, group_count, [scope_all]),
    0 = rpc:call(SlaveNode2, syn, group_count, [scope_all, node()]),
    1 = rpc:call(SlaveNode2, syn, group_count, [scope_all, SlaveNode1]),
    2 = rpc:call(SlaveNode2, syn, group_count, [scope_all, SlaveNode2]),

    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:members(scope_bc, <<"scoped-on-bc">>)),
    syn_test_suite_helper:assert_wait(
        lists:sort([{PidRemoteOn1, "scoped-meta-1"}, {PidRemoteOn2, "scoped-meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, members, [scope_bc, <<"scoped-on-bc">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([{PidRemoteOn1, "scoped-meta-1"}, {PidRemoteOn2, "scoped-meta-2"}]),
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, members, [scope_bc, <<"scoped-on-bc">>])) end
    ),

    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:local_members(scope_bc, <<"scoped-on-bc">>)),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn1, "scoped-meta-1"}],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, local_members, [scope_bc, <<"scoped-on-bc">>])) end
    ),
    syn_test_suite_helper:assert_wait(
        [{PidRemoteOn2, "scoped-meta-2"}],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, local_members, [scope_bc, <<"scoped-on-bc">>])) end
    ),

    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:group_count(scope_bc)),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:group_count(scope_bc, node())),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:group_count(scope_bc, SlaveNode1)),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:group_count(scope_bc, SlaveNode2)),
    1 = rpc:call(SlaveNode1, syn, group_count, [scope_bc]),
    0 = rpc:call(SlaveNode1, syn, group_count, [scope_bc, node()]),
    1 = rpc:call(SlaveNode1, syn, group_count, [scope_bc, SlaveNode1]),
    1 = rpc:call(SlaveNode1, syn, group_count, [scope_bc, SlaveNode2]),
    1 = rpc:call(SlaveNode2, syn, group_count, [scope_bc]),
    0 = rpc:call(SlaveNode2, syn, group_count, [scope_bc, node()]),
    1 = rpc:call(SlaveNode2, syn, group_count, [scope_bc, SlaveNode1]),
    1 = rpc:call(SlaveNode2, syn, group_count, [scope_bc, SlaveNode2]).

three_nodes_custom_event_handler_joined_left(Config) ->
    %% get slaves
    SlaveNode1 = proplists:get_value(syn_slave_1, Config),
    SlaveNode2 = proplists:get_value(syn_slave_2, Config),

    %% add custom handler for callbacks
    syn:set_event_handler(syn_test_event_handler_callbacks),
    rpc:call(SlaveNode1, syn, set_event_handler, [syn_test_event_handler_callbacks]),
    rpc:call(SlaveNode2, syn, set_event_handler, [syn_test_event_handler_callbacks]),

    %% start syn on nodes
    ok = syn:start(),
    ok = rpc:call(SlaveNode1, syn, start, []),
    ok = rpc:call(SlaveNode2, syn, start, []),

    %% add scopes
    ok = syn:add_node_to_scopes([scope_all]),
    ok = rpc:call(SlaveNode1, syn, add_node_to_scopes, [[scope_all]]),
    ok = rpc:call(SlaveNode2, syn, add_node_to_scopes, [[scope_all]]),

    %% init
    TestPid = self(),
    LocalNode = node(),

    %% start process
    Pid = syn_test_suite_helper:start_process(),
    Pid2 = syn_test_suite_helper:start_process(),

    %% ---> on join
    ok = syn:join(scope_all, "my-group", Pid, {recipient, TestPid, <<"meta">>}),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_joined, LocalNode, scope_all, "my-group", Pid, <<"meta">>, normal},
        {on_process_joined, SlaveNode1, scope_all, "my-group", Pid, <<"meta">>, normal},
        {on_process_joined, SlaveNode2, scope_all, "my-group", Pid, <<"meta">>, normal}
    ]),

    %% join from another node
    ok = rpc:call(SlaveNode1, syn, join, [scope_all, "my-group", Pid2, {recipient, self(), <<"meta-for-2">>}]),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_joined, LocalNode, scope_all, "my-group", Pid2, <<"meta-for-2">>, normal},
        {on_process_joined, SlaveNode1, scope_all, "my-group", Pid2, <<"meta-for-2">>, normal},
        {on_process_joined, SlaveNode2, scope_all, "my-group", Pid2, <<"meta-for-2">>, normal}
    ]),

    %% ---> on meta update
    ok = syn:join(scope_all, "my-group", Pid, {recipient, self(), <<"new-meta-0">>}),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_group_process_updated, LocalNode, scope_all, "my-group", Pid, <<"new-meta-0">>, normal},
        {on_group_process_updated, SlaveNode1, scope_all, "my-group", Pid, <<"new-meta-0">>, normal},
        {on_group_process_updated, SlaveNode2, scope_all, "my-group", Pid, <<"new-meta-0">>, normal}
    ]),

    %% update meta from another node
    ok = rpc:call(SlaveNode1, syn, join, [scope_all, "my-group", Pid, {recipient, self(), <<"new-meta">>}]),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_group_process_updated, LocalNode, scope_all, "my-group", Pid, <<"new-meta">>, normal},
        {on_group_process_updated, SlaveNode1, scope_all, "my-group", Pid, <<"new-meta">>, normal},
        {on_group_process_updated, SlaveNode2, scope_all, "my-group", Pid, <<"new-meta">>, normal}
    ]),

    %% ---> on left
    ok = syn:leave(scope_all, "my-group", Pid),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_left, LocalNode, scope_all, "my-group", Pid, <<"new-meta">>, normal},
        {on_process_left, SlaveNode1, scope_all, "my-group", Pid, <<"new-meta">>, normal},
        {on_process_left, SlaveNode2, scope_all, "my-group", Pid, <<"new-meta">>, normal}
    ]),

    %% leave from another node
    ok = rpc:call(SlaveNode1, syn, leave, [scope_all, "my-group", Pid2]),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_left, LocalNode, scope_all, "my-group", Pid2, <<"meta-for-2">>, normal},
        {on_process_left, SlaveNode1, scope_all, "my-group", Pid2, <<"meta-for-2">>, normal},
        {on_process_left, SlaveNode2, scope_all, "my-group", Pid2, <<"meta-for-2">>, normal}
    ]),

    %% clean & check (no callbacks since process has left)
    syn_test_suite_helper:kill_process(Pid),
    syn_test_suite_helper:assert_empty_queue(),

    %% ---> after a netsplit
    PidRemoteOn1 = syn_test_suite_helper:start_process(SlaveNode1),
    syn:join(scope_all, remote_on_1, PidRemoteOn1, {recipient, self(), <<"netsplit">>}),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_joined, LocalNode, scope_all, remote_on_1, PidRemoteOn1, <<"netsplit">>, normal},
        {on_process_joined, SlaveNode1, scope_all, remote_on_1, PidRemoteOn1, <<"netsplit">>, normal},
        {on_process_joined, SlaveNode2, scope_all, remote_on_1, PidRemoteOn1, <<"netsplit">>, normal}
    ]),

    %% partial netsplit (1 cannot see 2)
    rpc:call(SlaveNode1, syn_test_suite_helper, disconnect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node()]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node()]),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_left, SlaveNode2, scope_all, remote_on_1, PidRemoteOn1, <<"netsplit">>, {syn_remote_scope_node_down, scope_all, SlaveNode1}}
    ]),

    %% ---> after a re-join
    %% re-join
    rpc:call(SlaveNode1, syn_test_suite_helper, connect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node(), SlaveNode1]),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_joined, SlaveNode2, scope_all, remote_on_1, PidRemoteOn1, <<"netsplit">>, {syn_remote_scope_node_up, scope_all, SlaveNode1}}
    ]),

    %% clean
    syn_test_suite_helper:kill_process(PidRemoteOn1),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_left, LocalNode, scope_all, remote_on_1, PidRemoteOn1, <<"netsplit">>, killed},
        {on_process_left, SlaveNode1, scope_all, remote_on_1, PidRemoteOn1, <<"netsplit">>, killed},
        {on_process_left, SlaveNode2, scope_all, remote_on_1, PidRemoteOn1, <<"netsplit">>, killed}
    ]),

    %% ---> don't call on monitor rebuild
    %% crash the scope process on local
    syn_test_suite_helper:kill_process(syn_pg_scope_all),
    syn_test_suite_helper:wait_process_name_ready(syn_pg_scope_all),

    %% no messages
    syn_test_suite_helper:assert_empty_queue(),

    %% ---> call if process died during the scope process crash
    TransientPid = syn_test_suite_helper:start_process(),
    syn:join(scope_all, "transient-group", TransientPid, {recipient, self(), "transient-meta"}),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_joined, LocalNode, scope_all, "transient-group", TransientPid, "transient-meta", normal},
        {on_process_joined, SlaveNode1, scope_all, "transient-group", TransientPid, "transient-meta", normal},
        {on_process_joined, SlaveNode2, scope_all, "transient-group", TransientPid, "transient-meta", normal}
    ]),

    %% crash the scope process & fake a died process on local
    InvalidPid = list_to_pid("<0.9999.0>"),
    add_to_local_table(scope_all, "invalid-group", InvalidPid, {recipient, self(), "invalid-meta"}, 0, undefined),
    syn_test_suite_helper:kill_process(syn_pg_scope_all),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_left, LocalNode, scope_all, "invalid-group", InvalidPid, "invalid-meta", undefined},
        {on_process_left, SlaveNode1, scope_all, "transient-group", TransientPid, "transient-meta", {syn_remote_scope_node_down, scope_all, LocalNode}},
        {on_process_left, SlaveNode2, scope_all, "transient-group", TransientPid, "transient-meta", {syn_remote_scope_node_down, scope_all, LocalNode}},
        {on_process_joined, SlaveNode1, scope_all, "transient-group", TransientPid, "transient-meta", {syn_remote_scope_node_up, scope_all, LocalNode}},
        {on_process_joined, SlaveNode2, scope_all, "transient-group", TransientPid, "transient-meta", {syn_remote_scope_node_up, scope_all, LocalNode}}
    ]).

three_nodes_publish(Config) ->
    %% get slaves
    SlaveNode1 = proplists:get_value(syn_slave_1, Config),
    SlaveNode2 = proplists:get_value(syn_slave_2, Config),

    %% start syn on nodes
    ok = syn:start(),
    ok = rpc:call(SlaveNode1, syn, start, []),
    ok = rpc:call(SlaveNode2, syn, start, []),

    %% add scopes
    ok = syn:add_node_to_scopes([scope_ab]),
    ok = rpc:call(SlaveNode1, syn, add_node_to_scopes, [[scope_ab, scope_bc]]),
    ok = rpc:call(SlaveNode2, syn, add_node_to_scopes, [[scope_bc]]),

    %% start processes
    TestMessage = test_message,
    TestPid = self(),
    SubscriberLoop = fun() -> subscriber_loop(TestPid, TestMessage) end,

    Pid = syn_test_suite_helper:start_process(SubscriberLoop),
    Pid2 = syn_test_suite_helper:start_process(SubscriberLoop),
    PidRemoteOn1 = syn_test_suite_helper:start_process(SlaveNode1, SubscriberLoop),
    PidRemoteOn2 = syn_test_suite_helper:start_process(SlaveNode2, SubscriberLoop),

    %% join
    ok = syn:join(scope_ab, <<"subscribers">>, Pid),
    ok = syn:join(scope_ab, <<"subscribers-2">>, Pid2),
    ok = syn:join(scope_ab, <<"subscribers">>, PidRemoteOn1),
    ok = rpc:call(SlaveNode1, syn, join, [scope_bc, <<"subscribers">>, PidRemoteOn1]),
    ok = rpc:call(SlaveNode2, syn, join, [scope_bc, <<"subscribers">>, PidRemoteOn2]),

    %% ---> publish
    {ok, 2} = syn:publish(scope_ab, <<"subscribers">>, TestMessage),

    syn_test_suite_helper:assert_received_messages([
        {done, Pid},
        {done, PidRemoteOn1}
    ]),

    %% errors
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:publish(scope_bc, <<"subscribers">>, TestMessage)),

    %% on other scope
    {ok, 2} = rpc:call(SlaveNode1, syn, publish, [scope_bc, <<"subscribers">>, TestMessage]),

    syn_test_suite_helper:assert_received_messages([
        {done, PidRemoteOn1},
        {done, PidRemoteOn2}
    ]),

    %% non-existant
    {ok, 0} = syn:publish(scope_ab, <<"non-existant">>, TestMessage),
    %% no messages
    syn_test_suite_helper:assert_empty_queue(),

    %% ---> publish local
    {ok, 1} = syn:local_publish(scope_ab, <<"subscribers">>, test_message),

    syn_test_suite_helper:assert_received_messages([
        {done, Pid}
    ]),

    %% non-existant
    {ok, 0} = syn:local_publish(scope_ab, <<"non-existant">>, TestMessage),
    %% no messages
    syn_test_suite_helper:assert_empty_queue().

three_nodes_multi_call(Config) ->
    %% get slaves
    SlaveNode1 = proplists:get_value(syn_slave_1, Config),
    SlaveNode2 = proplists:get_value(syn_slave_2, Config),

    %% start syn on nodes
    ok = syn:start(),
    ok = rpc:call(SlaveNode1, syn, start, []),
    ok = rpc:call(SlaveNode2, syn, start, []),

    %% add scopes
    ok = syn:add_node_to_scopes([scope_ab]),
    ok = rpc:call(SlaveNode1, syn, add_node_to_scopes, [[scope_ab, scope_bc]]),
    ok = rpc:call(SlaveNode2, syn, add_node_to_scopes, [[scope_bc]]),

    %% start processes
    RecipientLoopLate = fun() -> timer:sleep(200), recipient_loop() end,

    Pid = syn_test_suite_helper:start_process(fun recipient_loop/0),
    Pid2 = syn_test_suite_helper:start_process(RecipientLoopLate),
    PidRemoteOn1 = syn_test_suite_helper:start_process(SlaveNode1, fun recipient_loop/0),
    PidRemoteOn2 = syn_test_suite_helper:start_process(SlaveNode2, fun recipient_loop/0),

    %% join
    ok = syn:join(scope_ab, <<"recipients">>, Pid, "meta-1"),
    ok = syn:join(scope_ab, <<"recipients">>, Pid2),
    ok = syn:join(scope_ab, <<"recipients">>, PidRemoteOn1, "meta-on-ab-1"),
    ok = rpc:call(SlaveNode1, syn, join, [scope_bc, <<"recipients">>, PidRemoteOn1, "meta-on-bc-1"]),
    ok = rpc:call(SlaveNode2, syn, join, [scope_bc, <<"recipients">>, PidRemoteOn2, "meta-on-bc-2"]),

    %% errors
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:multi_call(scope_bc, <<"recipients">>, test_message, 100)),

    %% ---> multi_call
    {RepliesAB, BadRepliesAB} = syn:multi_call(scope_ab, <<"recipients">>, test_message_ab, 100),

    RepliesABSorted = lists:sort(RepliesAB),
    RepliesABSorted = lists:sort([
        {{Pid, "meta-1"}, {reply, test_message_ab, Pid, "meta-1"}},
        {{PidRemoteOn1, "meta-on-ab-1"}, {reply, test_message_ab, PidRemoteOn1, "meta-on-ab-1"}}
    ]),
    BadRepliesAB = [{Pid2, undefined}],

    %% different scope
    {RepliesBC, BadRepliesBC} = rpc:call(SlaveNode1, syn, multi_call, [scope_bc, <<"recipients">>, test_message_bc, 100]),

    RepliesBCSorted = lists:sort(RepliesBC),
    RepliesBCSorted = lists:sort([
        {{PidRemoteOn1, "meta-on-bc-1"}, {reply, test_message_bc, PidRemoteOn1, "meta-on-bc-1"}},
        {{PidRemoteOn2, "meta-on-bc-2"}, {reply, test_message_bc, PidRemoteOn2, "meta-on-bc-2"}}
    ]),
    BadRepliesBC = [].

three_nodes_group_names(Config) ->
    %% get slaves
    SlaveNode1 = proplists:get_value(syn_slave_1, Config),
    SlaveNode2 = proplists:get_value(syn_slave_2, Config),

    %% start syn on nodes
    ok = syn:start(),
    ok = rpc:call(SlaveNode1, syn, start, []),
    ok = rpc:call(SlaveNode2, syn, start, []),

    %% add scopes
    ok = syn:add_node_to_scopes([scope_all]),
    ok = rpc:call(SlaveNode1, syn, add_node_to_scopes, [[scope_all]]),
    ok = rpc:call(SlaveNode2, syn, add_node_to_scopes, [[scope_all]]),

    %% start processes
    Pid = syn_test_suite_helper:start_process(),
    Pid2 = syn_test_suite_helper:start_process(),
    PidRemoteOn1 = syn_test_suite_helper:start_process(SlaveNode1),
    PidRemoteOn2 = syn_test_suite_helper:start_process(SlaveNode2),

    %% join
    ok = syn:join(scope_all, <<"subscribers">>, Pid),
    ok = syn:join(scope_all, <<"subscribers">>, Pid2),
    ok = syn:join(scope_all, <<"subscribers-2">>, Pid),
    ok = syn:join(scope_all, <<"subscribers-2">>, PidRemoteOn1),
    ok = syn:join(scope_all, <<"subscribers-2">>, PidRemoteOn2),
    ok = syn:join(scope_all, <<"subscribers-3">>, PidRemoteOn1),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers">>, <<"subscribers-2">>, <<"subscribers-3">>]),
        fun() -> lists:sort(syn:group_names(scope_all)) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers">>, <<"subscribers-2">>]),
        fun() -> lists:sort(syn:group_names(scope_all, node())) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers-2">>, <<"subscribers-3">>]),
        fun() -> lists:sort(syn:group_names(scope_all, SlaveNode1)) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers-2">>],
        fun() -> lists:sort(syn:group_names(scope_all, SlaveNode2)) end
    ),

    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers">>, <<"subscribers-2">>, <<"subscribers-3">>]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [scope_all])) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers">>, <<"subscribers-2">>]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [scope_all, node()])) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers-2">>, <<"subscribers-3">>]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [scope_all, SlaveNode1])) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers-2">>],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [scope_all, SlaveNode2])) end
    ),

    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers">>, <<"subscribers-2">>, <<"subscribers-3">>]),
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, group_names, [scope_all])) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers">>, <<"subscribers-2">>]),
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, group_names, [scope_all, node()])) end
    ),
    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers-2">>, <<"subscribers-3">>]),
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, group_names, [scope_all, SlaveNode1])) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers-2">>],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, group_names, [scope_all, SlaveNode2])) end
    ),

    %% leave
    ok = syn:leave(scope_all, <<"subscribers-2">>, Pid),
    ok = syn:leave(scope_all, <<"subscribers-2">>, PidRemoteOn1),
    ok = syn:leave(scope_all, <<"subscribers-2">>, PidRemoteOn2),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers">>, <<"subscribers-3">>]),
        fun() -> lists:sort(syn:group_names(scope_all)) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers">>],
        fun() -> lists:sort(syn:group_names(scope_all, node())) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers-3">>],
        fun() -> lists:sort(syn:group_names(scope_all, SlaveNode1)) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(syn:group_names(scope_all, SlaveNode2)) end
    ),

    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers">>, <<"subscribers-3">>]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [scope_all])) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers">>],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [scope_all, node()])) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers-3">>],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [scope_all, SlaveNode1])) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [scope_all, SlaveNode2])) end
    ),

    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers">>, <<"subscribers-3">>]),
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, group_names, [scope_all])) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers">>],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, group_names, [scope_all, node()])) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers-3">>],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, group_names, [scope_all, SlaveNode1])) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, group_names, [scope_all, SlaveNode2])) end
    ),

    %% partial netsplit (1 cannot see 2)
    rpc:call(SlaveNode1, syn_test_suite_helper, disconnect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node()]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node()]),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers">>, <<"subscribers-3">>]),
        fun() -> lists:sort(syn:group_names(scope_all)) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers">>],
        fun() -> lists:sort(syn:group_names(scope_all, node())) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers-3">>],
        fun() -> lists:sort(syn:group_names(scope_all, SlaveNode1)) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(syn:group_names(scope_all, SlaveNode2)) end
    ),

    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers">>, <<"subscribers-3">>]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [scope_all])) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers">>],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [scope_all, node()])) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers-3">>],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [scope_all, SlaveNode1])) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [scope_all, SlaveNode2])) end
    ),

    syn_test_suite_helper:assert_wait(
        [<<"subscribers">>],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, group_names, [scope_all])) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers">>],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, group_names, [scope_all, node()])) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, group_names, [scope_all, SlaveNode1])) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, group_names, [scope_all, SlaveNode2])) end
    ),

    %% re-join
    rpc:call(SlaveNode1, syn_test_suite_helper, connect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node(), SlaveNode1]),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers">>, <<"subscribers-3">>]),
        fun() -> lists:sort(syn:group_names(scope_all)) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers">>],
        fun() -> lists:sort(syn:group_names(scope_all, node())) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers-3">>],
        fun() -> lists:sort(syn:group_names(scope_all, SlaveNode1)) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(syn:group_names(scope_all, SlaveNode2)) end
    ),

    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers">>, <<"subscribers-3">>]),
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [scope_all])) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers">>],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [scope_all, node()])) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers-3">>],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [scope_all, SlaveNode1])) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode1, syn, group_names, [scope_all, SlaveNode2])) end
    ),

    syn_test_suite_helper:assert_wait(
        lists:sort([<<"subscribers">>, <<"subscribers-3">>]),
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, group_names, [scope_all])) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers">>],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, group_names, [scope_all, node()])) end
    ),
    syn_test_suite_helper:assert_wait(
        [<<"subscribers-3">>],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, group_names, [scope_all, SlaveNode1])) end
    ),
    syn_test_suite_helper:assert_wait(
        [],
        fun() -> lists:sort(rpc:call(SlaveNode2, syn, group_names, [scope_all, SlaveNode2])) end
    ).

four_nodes_concurrency(Config) ->
    %% get slaves
    SlaveNode1 = proplists:get_value(syn_slave_1, Config),
    SlaveNode2 = proplists:get_value(syn_slave_2, Config),
    SlaveNode3 = proplists:get_value(syn_slave_3, Config),

    %% start syn on nodes
    ok = syn:start(),
    ok = rpc:call(SlaveNode1, syn, start, []),
    ok = rpc:call(SlaveNode2, syn, start, []),
    ok = rpc:call(SlaveNode3, syn, start, []),

    %% add scopes
    ok = syn:add_node_to_scopes([scope_all]),
    ok = rpc:call(SlaveNode1, syn, add_node_to_scopes, [[scope_all]]),
    ok = rpc:call(SlaveNode2, syn, add_node_to_scopes, [[scope_all]]),
    ok = rpc:call(SlaveNode3, syn, add_node_to_scopes, [[scope_all]]),

    %% ref
    TestPid = self(),
    Iterations = 250,

    %% pids
    PidLocal = syn_test_suite_helper:start_process(),
    PidOn1 = syn_test_suite_helper:start_process(SlaveNode1),
    PidOn2 = syn_test_suite_helper:start_process(SlaveNode2),
    PidOn3 = syn_test_suite_helper:start_process(SlaveNode3),

    LocalNode = node(),
    PidMap = #{
        LocalNode => PidLocal,
        SlaveNode1 => PidOn1,
        SlaveNode2 => PidOn2,
        SlaveNode3 => PidOn3
    },

    %% concurrent test
    WorkerFun = fun() ->
        Pid = maps:get(node(), PidMap),
        lists:foreach(fun(_) ->
            %% loop
            RandomMeta = rand:uniform(99999),
            ok = syn:join(scope_all, <<"concurrent-scope">>, Pid, RandomMeta),
            %% random leave
            case rand:uniform(5) of
                1 -> syn:leave(scope_all, <<"concurrent-scope">>, Pid);
                _ -> ok
            end,
            %% random sleep
            RndTime = rand:uniform(30),
            timer:sleep(RndTime)
        end, lists:seq(1, Iterations)),
        TestPid ! {done, node()}
    end,

    %% spawn concurrent
    spawn(LocalNode, WorkerFun),
    spawn(SlaveNode1, WorkerFun),
    spawn(SlaveNode2, WorkerFun),
    spawn(SlaveNode3, WorkerFun),

    %% wait for workers done
    syn_test_suite_helper:assert_received_messages([
        {done, LocalNode},
        {done, SlaveNode1},
        {done, SlaveNode2},
        {done, SlaveNode3}
    ]),

    %% check results are same across network
    syn_test_suite_helper:assert_wait(
        1,
        fun() ->
            ResultPidLocal = lists:sort(syn:members(scope_all, <<"concurrent-scope">>)),
            ResultPidOn1 = lists:sort(rpc:call(SlaveNode1, syn, members, [scope_all, <<"concurrent-scope">>])),
            ResultPidOn2 = lists:sort(rpc:call(SlaveNode2, syn, members, [scope_all, <<"concurrent-scope">>])),
            ResultPidOn3 = lists:sort(rpc:call(SlaveNode3, syn, members, [scope_all, <<"concurrent-scope">>])),

            %% if unique set is of 1 element then they all contain the same result
            Ordset = ordsets:from_list([ResultPidLocal, ResultPidOn1, ResultPidOn2, ResultPidOn3]),
            ordsets:size(Ordset)
        end
    ).

%% ===================================================================
%% Internal
%% ===================================================================
add_to_local_table(Scope, GroupName, Pid, Meta, Time, MRef) ->
    TableByName = syn_backbone:get_table_name(syn_pg_by_name, Scope),
    TableByPid = syn_backbone:get_table_name(syn_pg_by_pid, Scope),
    syn_pg:add_to_local_table(GroupName, Pid, Meta, Time, MRef, TableByName, TableByPid).

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
