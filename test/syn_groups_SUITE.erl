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
-module(syn_groups_SUITE).

%% callbacks
-export([all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([groups/0, init_per_group/2, end_per_group/2]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% tests
-export([
    single_node_join_and_monitor/1,
    single_node_join_and_leave/1,
    single_node_join_errors/1
]).
-export([
    two_nodes_join_monitor_and_unregister/1,
    two_nodes_local_members/1
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
%% Reason = any()
%% -------------------------------------------------------------------
all() ->
    [
        {group, single_node_groups},
        {group, two_nodes_groups}
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
        {single_node_groups, [shuffle], [
            single_node_join_and_monitor,
            single_node_join_and_leave,
            single_node_join_errors
        ]},
        {two_nodes_groups, [shuffle], [
            two_nodes_join_monitor_and_unregister,
            two_nodes_local_members
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
init_per_group(two_nodes_groups, Config) ->
    %% start slave
    {ok, SlaveNode} = syn_test_suite_helper:start_slave(syn_slave),
    %% config
    [{slave_node, SlaveNode} | Config];
init_per_group(three_nodes_groups, Config) ->
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
end_per_group(two_nodes_groups, Config) ->
    SlaveNode = proplists:get_value(slave_node, Config),
    syn_test_suite_helper:connect_node(SlaveNode),
    syn_test_suite_helper:stop_slave(syn_slave),
    timer:sleep(1000);
end_per_group(three_nodes_groups, Config) ->
    SlaveNode1 = proplists:get_value(slave_node_1, Config),
    syn_test_suite_helper:connect_node(SlaveNode1),
    SlaveNode2 = proplists:get_value(slave_node_2, Config),
    syn_test_suite_helper:connect_node(SlaveNode2),
    syn_test_suite_helper:stop_slave(syn_slave_1),
    syn_test_suite_helper:stop_slave(syn_slave_2),
    timer:sleep(1000);
end_per_group(_GroupName, _Config) ->
    ok.

%% -------------------------------------------------------------------
%% Function: init_per_testcase(TestCase, Config0) ->
%%				Config1 | {skip,Reason} | {skip_and_save,Reason,Config1}
%% TestCase = atom()
%% Config0 = Config1 = [tuple()]
%% Reason = any()
%% -------------------------------------------------------------------
init_per_testcase(_TestCase, Config) ->
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
single_node_join_and_monitor(_Config) ->
    GroupName = "my group",
    %% start
    ok = syn:start(),
    %% start processes
    Pid = syn_test_suite_helper:start_process(),
    PidWithMeta = syn_test_suite_helper:start_process(),
    PidOther = syn_test_suite_helper:start_process(),
    %% retrieve
    [] = syn:get_members(GroupName),
    [] = syn:get_members(GroupName, with_meta),
    false = syn:member(Pid, GroupName),
    false = syn:member(PidWithMeta, GroupName),
    false = syn:member(PidOther, GroupName),
    %% join
    ok = syn:join(GroupName, Pid),
    ok = syn:join(GroupName, PidWithMeta, {with, meta}),
    ok = syn:join("other-group", PidOther),
    %% retrieve
    true = syn:member(Pid, GroupName),
    true = syn:member(PidWithMeta, GroupName),
    false = syn:member(PidOther, GroupName),
    true = lists:sort([Pid, PidWithMeta]) =:= lists:sort(syn:get_members(GroupName)),
    true = lists:sort([{Pid, undefined}, {PidWithMeta, {with, meta}}])
        =:= lists:sort(syn:get_members(GroupName, with_meta)),
    %% re-join
    ok = syn:join(GroupName, PidWithMeta, {with2, meta2}),
    true = lists:sort([{Pid, undefined}, {PidWithMeta, {with2, meta2}}])
        =:= lists:sort(syn:get_members(GroupName, with_meta)),
    %% kill process
    syn_test_suite_helper:kill_process(Pid),
    syn_test_suite_helper:kill_process(PidWithMeta),
    syn_test_suite_helper:kill_process(PidOther),
    timer:sleep(100),
    %% retrieve
    [] = syn:get_members(GroupName),
    [] = syn:get_members(GroupName, with_meta),
    false = syn:member(Pid, GroupName),
    false = syn:member(PidWithMeta, GroupName).

single_node_join_and_leave(_Config) ->
    GroupName = "my group",
    %% start
    ok = syn:start(),
    %% start processes
    Pid = syn_test_suite_helper:start_process(),
    PidWithMeta = syn_test_suite_helper:start_process(),
    %% retrieve
    [] = syn:get_members(GroupName),
    [] = syn:get_members(GroupName, with_meta),
    false = syn:member(Pid, GroupName),
    false = syn:member(PidWithMeta, GroupName),
    %% join
    ok = syn:join(GroupName, Pid),
    ok = syn:join(GroupName, PidWithMeta, {with, meta}),
    %% retrieve
    true = syn:member(Pid, GroupName),
    true = syn:member(PidWithMeta, GroupName),
    true = lists:sort([Pid, PidWithMeta]) =:= lists:sort(syn:get_members(GroupName)),
    true = lists:sort([{Pid, undefined}, {PidWithMeta, {with, meta}}])
        =:= lists:sort(syn:get_members(GroupName, with_meta)),
    %% leave
    ok = syn:leave(GroupName, Pid),
    ok = syn:leave(GroupName, PidWithMeta),
    timer:sleep(100),
    %% retrieve
    [] = syn:get_members(GroupName),
    [] = syn:get_members(GroupName, with_meta),
    false = syn:member(Pid, GroupName),
    false = syn:member(PidWithMeta, GroupName),
    %% kill processes
    syn_test_suite_helper:kill_process(Pid),
    syn_test_suite_helper:kill_process(PidWithMeta).

single_node_join_errors(_Config) ->
    GroupName = "my group",
    %% start
    ok = syn:start(),
    %% start processes
    Pid = syn_test_suite_helper:start_process(),
    Pid2 = syn_test_suite_helper:start_process(),
    %% join
    ok = syn:join(GroupName, Pid),
    ok = syn:join(GroupName, Pid2),
    true = syn:member(Pid, GroupName),
    true = syn:member(Pid2, GroupName),
    %% leave
    ok = syn:leave(GroupName, Pid),
    {error, not_in_group} = syn:leave(GroupName, Pid),
    %% kill
    syn_test_suite_helper:kill_process(Pid2),
    timer:sleep(200),
    {error, not_in_group} = syn:leave(GroupName, Pid2),
    {error, not_alive} = syn:join(GroupName, Pid2),
    %% kill processes
    syn_test_suite_helper:kill_process(Pid).

two_nodes_join_monitor_and_unregister(Config) ->
    GroupName = "my group",
    %% get slave
    SlaveNode = proplists:get_value(slave_node, Config),
    %% start
    ok = syn:start(),
    ok = rpc:call(SlaveNode, syn, start, []),
    timer:sleep(100),
    %% start processes
    LocalPid = syn_test_suite_helper:start_process(),
    RemotePid = syn_test_suite_helper:start_process(SlaveNode),
    RemotePidJoinRemote = syn_test_suite_helper:start_process(SlaveNode),
    OtherPid = syn_test_suite_helper:start_process(),
    %% retrieve
    [] = syn:get_members("group-1"),
    [] = syn:get_members(GroupName),
    [] = syn:get_members(GroupName, with_meta),
    false = syn:member(LocalPid, GroupName),
    false = syn:member(RemotePid, GroupName),
    false = syn:member(RemotePidJoinRemote, GroupName),
    false = syn:member(OtherPid, GroupName),
    [] = rpc:call(SlaveNode, syn, get_members, [GroupName]),
    [] = rpc:call(SlaveNode, syn, get_members, [GroupName, with_meta]),
    false = rpc:call(SlaveNode, syn, member, [LocalPid, GroupName]),
    false = rpc:call(SlaveNode, syn, member, [RemotePid, GroupName]),
    false = rpc:call(SlaveNode, syn, member, [RemotePidJoinRemote, GroupName]),
    false = rpc:call(SlaveNode, syn, member, [OtherPid, GroupName]),
    %% join
    ok = syn:join(GroupName, LocalPid),
    ok = syn:join(GroupName, RemotePid, {with_meta}),
    ok = rpc:call(SlaveNode, syn, join, [GroupName, RemotePidJoinRemote]),
    ok = syn:join("other-group", OtherPid),
    timer:sleep(200),
    %% retrieve local
    true = lists:sort([LocalPid, RemotePid, RemotePidJoinRemote]) =:= lists:sort(syn:get_members(GroupName)),
    true = lists:sort([{LocalPid, undefined}, {RemotePid, {with_meta}}, {RemotePidJoinRemote, undefined}])
        =:= lists:sort(syn:get_members(GroupName, with_meta)),
    true = syn:member(LocalPid, GroupName),
    true = syn:member(RemotePid, GroupName),
    true = syn:member(RemotePidJoinRemote, GroupName),
    false = syn:member(OtherPid, GroupName),
    %% retrieve remote
    true = lists:sort([LocalPid, RemotePid, RemotePidJoinRemote])
        =:= lists:sort(rpc:call(SlaveNode, syn, get_members, [GroupName])),
    true = lists:sort([{LocalPid, undefined}, {RemotePid, {with_meta}}, {RemotePidJoinRemote, undefined}])
        =:= lists:sort(rpc:call(SlaveNode, syn, get_members, [GroupName, with_meta])),
    true = rpc:call(SlaveNode, syn, member, [LocalPid, GroupName]),
    true = rpc:call(SlaveNode, syn, member, [RemotePid, GroupName]),
    true = rpc:call(SlaveNode, syn, member, [RemotePidJoinRemote, GroupName]),
    false = rpc:call(SlaveNode, syn, member, [OtherPid, GroupName]),
    %% leave & kill
    ok = rpc:call(SlaveNode, syn, leave, [GroupName, LocalPid]),
    ok = syn:leave(GroupName, RemotePid),
    syn_test_suite_helper:kill_process(RemotePidJoinRemote),
    syn_test_suite_helper:kill_process(OtherPid),
    timer:sleep(200),
    %% retrieve
    [] = syn:get_members("group-1"),
    [] = syn:get_members(GroupName),
    [] = syn:get_members(GroupName, with_meta),
    false = syn:member(LocalPid, GroupName),
    false = syn:member(RemotePid, GroupName),
    false = syn:member(RemotePidJoinRemote, GroupName),
    false = syn:member(OtherPid, GroupName),
    [] = rpc:call(SlaveNode, syn, get_members, [GroupName]),
    [] = rpc:call(SlaveNode, syn, get_members, [GroupName, with_meta]),
    false = rpc:call(SlaveNode, syn, member, [LocalPid, GroupName]),
    false = rpc:call(SlaveNode, syn, member, [RemotePid, GroupName]),
    false = rpc:call(SlaveNode, syn, member, [RemotePidJoinRemote, GroupName]),
    false = rpc:call(SlaveNode, syn, member, [OtherPid, GroupName]),
    %% kill processes
    syn_test_suite_helper:kill_process(LocalPid),
    syn_test_suite_helper:kill_process(RemotePid).

two_nodes_local_members(Config) ->
    GroupName = "my group",
    %% get slave
    SlaveNode = proplists:get_value(slave_node, Config),
    %% start
    ok = syn:start(),
    ok = rpc:call(SlaveNode, syn, start, []),
    timer:sleep(100),
    %% start processes
    LocalPid = syn_test_suite_helper:start_process(),
    RemotePid = syn_test_suite_helper:start_process(SlaveNode),
    RemotePidJoinRemote = syn_test_suite_helper:start_process(SlaveNode),
    OtherPid = syn_test_suite_helper:start_process(),
    %% local members
    [] = syn:get_local_members(GroupName),
    [] = syn:get_local_members(GroupName, with_meta),
    false = syn:local_member(LocalPid, GroupName),
    false = syn:local_member(RemotePid, GroupName),
    false = syn:local_member(RemotePidJoinRemote, GroupName),
    false = syn:local_member(OtherPid, GroupName),
    %% remote members
    [] = rpc:call(SlaveNode, syn, get_local_members, [GroupName]),
    [] = rpc:call(SlaveNode, syn, get_local_members, [GroupName, with_meta]),
    false = rpc:call(SlaveNode, syn, local_member, [LocalPid, GroupName]),
    false = rpc:call(SlaveNode, syn, local_member, [RemotePid, GroupName]),
    false = rpc:call(SlaveNode, syn, local_member, [RemotePidJoinRemote, GroupName]),
    false = rpc:call(SlaveNode, syn, local_member, [OtherPid, GroupName]),
    %% join
    ok = syn:join(GroupName, LocalPid),
    ok = syn:join(GroupName, RemotePid, {meta, 2}),
    ok = rpc:call(SlaveNode, syn, join, [GroupName, RemotePidJoinRemote]),
    ok = syn:join({"other-group"}, OtherPid),
    timer:sleep(200),
    %% local members
    [LocalPid] = syn:get_local_members(GroupName),
    [{LocalPid, undefined}] = syn:get_local_members(GroupName, with_meta),
    [OtherPid] = syn:get_local_members({"other-group"}),
    true = syn:local_member(LocalPid, GroupName),
    false = syn:local_member(RemotePid, GroupName),
    false = syn:local_member(RemotePidJoinRemote, GroupName),
    false = syn:local_member(OtherPid, GroupName),
    true = syn:local_member(OtherPid, {"other-group"}),
    %% remote members
    true = lists:sort([RemotePid, RemotePidJoinRemote])
        =:= lists:sort(rpc:call(SlaveNode, syn, get_local_members, [GroupName])),
    true = lists:sort([{RemotePid, {meta, 2}}, {RemotePidJoinRemote, undefined}])
        =:= lists:sort(rpc:call(SlaveNode, syn, get_local_members, [GroupName, with_meta])),
    false = rpc:call(SlaveNode, syn, local_member, [LocalPid, GroupName]),
    true = rpc:call(SlaveNode, syn, local_member, [RemotePid, GroupName]),
    true = rpc:call(SlaveNode, syn, local_member, [RemotePidJoinRemote, GroupName]),
    false = rpc:call(SlaveNode, syn, local_member, [OtherPid, GroupName]),
    %% leave & kill
    ok = rpc:call(SlaveNode, syn, leave, [GroupName, LocalPid]),
    ok = syn:leave(GroupName, RemotePid),
    syn_test_suite_helper:kill_process(RemotePidJoinRemote),
    syn_test_suite_helper:kill_process(OtherPid),
    timer:sleep(200),
    %% local members
    [] = syn:get_local_members(GroupName),
    [] = syn:get_local_members(GroupName, with_meta),
    %% remote members
    [] = rpc:call(SlaveNode, syn, get_local_members, [GroupName]),
    [] = rpc:call(SlaveNode, syn, get_local_members, [GroupName, with_meta]),
    %% kill processes
    syn_test_suite_helper:kill_process(LocalPid),
    syn_test_suite_helper:kill_process(RemotePid).
