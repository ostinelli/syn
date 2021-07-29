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
    single_node_join_errors/1,
    single_node_groups_count/1,
    single_node_group_names/1,
    single_node_publish/1,
    single_node_multicall/1,
    single_node_multicall_with_custom_timeout/1,
    single_node_callback_on_process_exit/1,
    single_node_monitor_after_group_crash/1
]).
-export([
    two_nodes_join_monitor_and_unregister/1,
    two_nodes_local_members/1,
    two_nodes_groups_count/1,
    two_nodes_group_names/1,
    two_nodes_publish/1,
    two_nodes_local_publish/1,
    two_nodes_multicall/1,
    two_nodes_groups_full_cluster_sync_on_boot_node_added_later/1,
    two_nodes_groups_full_cluster_sync_on_boot_syn_started_later/1,
    three_nodes_anti_entropy/1,
    three_nodes_anti_entropy_manual/1
]).
-export([
    three_nodes_partial_netsplit_consistency/1,
    three_nodes_full_netsplit_consistency/1
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
        {group, two_nodes_groups},
        {group, three_nodes_groups}
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
            single_node_join_errors,
            single_node_groups_count,
            single_node_group_names,
            single_node_publish,
            single_node_multicall,
            single_node_multicall_with_custom_timeout,
            single_node_callback_on_process_exit,
            single_node_monitor_after_group_crash
        ]},
        {two_nodes_groups, [shuffle], [
            two_nodes_join_monitor_and_unregister,
            two_nodes_local_members,
            two_nodes_groups_count,
            two_nodes_group_names,
            two_nodes_publish,
            two_nodes_local_publish,
            two_nodes_multicall,
            two_nodes_groups_full_cluster_sync_on_boot_node_added_later,
            two_nodes_groups_full_cluster_sync_on_boot_syn_started_later
        ]},
        {three_nodes_groups, [shuffle], [
            three_nodes_partial_netsplit_consistency,
            three_nodes_full_netsplit_consistency,
            three_nodes_anti_entropy,
            three_nodes_anti_entropy_manual
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
    syn_test_suite_helper:clean_after_test(),
    syn_test_suite_helper:stop_slave(syn_slave),
    timer:sleep(1000);
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
single_node_join_and_monitor(_Config) ->
    GroupName = "my group",
    %% start
    ok = syn_test_suite_helper:start_syn(),
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
    ok = syn_test_suite_helper:start_syn(),
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
    false = syn:member(PidWithMeta, GroupName).

single_node_join_errors(_Config) ->
    GroupName = "my group",
    %% start
    ok = syn_test_suite_helper:start_syn(),
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
    {error, not_alive} = syn:join(GroupName, Pid2).

single_node_groups_count(_Config) ->
    %% start
    ok = syn_test_suite_helper:start_syn(),
    %% start processes
    Pid = syn_test_suite_helper:start_process(),
    Pid2 = syn_test_suite_helper:start_process(),
    Pid3 = syn_test_suite_helper:start_process(),
    %% join
    ok = syn:join({"group-1"}, Pid),
    ok = syn:join({"group-1"}, Pid2),
    ok = syn:join({"group-1"}, Pid3),
    ok = syn:join({"group-2"}, Pid2),
    %% count
    2 = syn:groups_count(),
    2 = syn:groups_count(node()),
    %% kill & unregister
    ok = syn:leave({"group-1"}, Pid),
    syn_test_suite_helper:kill_process(Pid2),
    syn_test_suite_helper:kill_process(Pid3),
    timer:sleep(100),
    %% count
    0 = syn:groups_count(),
    0 = syn:groups_count(node()).

single_node_group_names(_Config) ->
    %% start
    ok = syn_test_suite_helper:start_syn(),
    %% start processes
    Pid = syn_test_suite_helper:start_process(),
    Pid2 = syn_test_suite_helper:start_process(),
    Pid3 = syn_test_suite_helper:start_process(),
    %% join
    ok = syn:join({"group-1"}, Pid),
    ok = syn:join({"group-1"}, Pid2),
    ok = syn:join({"group-1"}, Pid3),
    ok = syn:join({"group-2"}, Pid2),
    %% names
    GroupNames = syn:get_group_names(),
    2 = length(GroupNames),
    true = lists:member({"group-1"}, GroupNames),
    true = lists:member({"group-2"}, GroupNames),
    %% kill & unregister
    ok = syn:leave({"group-1"}, Pid),
    syn_test_suite_helper:kill_process(Pid2),
    syn_test_suite_helper:kill_process(Pid3),
    timer:sleep(100),
    %% count
    [] = syn:get_group_names().

single_node_publish(_Config) ->
    GroupName = "my group",
    Message = {test, message},
    %% start
    ok = syn_test_suite_helper:start_syn(),
    %% start processes
    ResultPid = self(),
    F = fun() ->
        receive
            Message -> ResultPid ! {received, self(), Message}
        end
    end,
    Pid = syn_test_suite_helper:start_process(F),
    Pid2 = syn_test_suite_helper:start_process(F),
    _OtherPid = syn_test_suite_helper:start_process(F),
    %% join
    ok = syn:join(GroupName, Pid),
    ok = syn:join(GroupName, Pid2),
    true = syn:member(Pid, GroupName),
    true = syn:member(Pid2, GroupName),
    %% send
    {ok, 2} = syn:publish(GroupName, Message),
    %% check
    receive
        {received, Pid, Message} -> ok
    after 2000 ->
        ok = published_message_was_not_received_by_pid_1
    end,
    receive
        {received, Pid2, Message} -> ok
    after 2000 ->
        ok = published_message_was_not_received_by_pid_2
    end.

single_node_multicall(_Config) ->
    GroupName = <<"my group">>,
    %% start
    ok = syn_test_suite_helper:start_syn(),
    %% start processes
    F = fun() ->
        receive
            {syn_multi_call, RequestorPid, get_pid_name} ->
                syn:multi_call_reply(RequestorPid, {pong, self()})
        end
    end,
    Pid1 = syn_test_suite_helper:start_process(F),
    Pid2 = syn_test_suite_helper:start_process(F),
    PidUnresponsive = syn_test_suite_helper:start_process(),
    %% register
    ok = syn:join(GroupName, Pid1),
    ok = syn:join(GroupName, Pid2),
    ok = syn:join(GroupName, PidUnresponsive),
    %% call
    {Replies, BadPids} = syn:multi_call(GroupName, get_pid_name),
    %% check responses
    true = lists:sort([
        {Pid1, {pong, Pid1}},
        {Pid2, {pong, Pid2}}
    ]) =:= lists:sort(Replies),
    [PidUnresponsive] = BadPids.

single_node_multicall_with_custom_timeout(_Config) ->
    GroupName = <<"my group">>,
    %% start
    ok = syn_test_suite_helper:start_syn(),
    %% start processes
    F1 = fun() ->
        receive
            {syn_multi_call, RequestorPid, get_pid_name} ->
                syn:multi_call_reply(RequestorPid, {pong, self()})
        end
    end,
    Pid1 = syn_test_suite_helper:start_process(F1),
    F2 = fun() ->
        receive
            {syn_multi_call, RequestorPid, get_pid_name} ->
                timer:sleep(5000),
                syn:multi_call_reply(RequestorPid, {pong, self()})
        end
    end,
    PidTakesLong = syn_test_suite_helper:start_process(F2),
    PidUnresponsive = syn_test_suite_helper:start_process(),
    %% register
    ok = syn:join(GroupName, Pid1),
    ok = syn:join(GroupName, PidTakesLong),
    ok = syn:join(GroupName, PidUnresponsive),
    %% call
    {Replies, BadPids} = syn:multi_call(GroupName, get_pid_name, 2000),
    %% check responses
    [{Pid1, {pong, Pid1}}] = Replies,
    true = lists:sort([PidTakesLong, PidUnresponsive]) =:= lists:sort(BadPids).

single_node_callback_on_process_exit(_Config) ->
    %% use custom handler
    syn_test_suite_helper:use_custom_handler(),
    %% start
    ok = syn_test_suite_helper:start_syn(),
    %% start processes
    Pid = syn_test_suite_helper:start_process(),
    Pid2 = syn_test_suite_helper:start_process(),
    %% join
    TestPid = self(),
    ok = syn:join(group_1, Pid, {pid_group_1, TestPid}),
    ok = syn:join(group_2, Pid, {pid_group_2, TestPid}),
    ok = syn:join(group_1, Pid2, {pid2, TestPid}),
    %% kill 1
    syn_test_suite_helper:kill_process(Pid),
    receive
        {received_event_on, pid_group_1} ->
            ok;
        {received_event_on, pid2} ->
            ok = callback_on_process_exit_was_received_by_pid2
    after 1000 ->
        ok = callback_on_process_exit_was_not_received_by_pid
    end,
    receive
        {received_event_on, pid_group_2} ->
            ok;
        {received_event_on, pid2} ->
            ok = callback_on_process_exit_was_received_by_pid2
    after 1000 ->
        ok = callback_on_process_exit_was_not_received_by_pid
    end,
    %% unregister & kill 2
    ok = syn:leave(group_1, Pid2),
    syn_test_suite_helper:kill_process(Pid2),
    receive
        {received_event_on, pid2} ->
            ok = callback_on_process_exit_was_received_by_pid2
    after 1000 ->
        ok
    end.

single_node_monitor_after_group_crash(_Config) ->
    GroupName = "my group",
    %% start
    ok = syn_test_suite_helper:start_syn(),
    %% start processes
    Pid = syn_test_suite_helper:start_process(),
    %% join
    ok = syn:join(GroupName, Pid),
    %% kill groups
    syn_test_suite_helper:kill_sharded(syn_groups),
    timer:sleep(200),
    %% retrieve
    true = syn:member(Pid, GroupName),
    [Pid] = syn:get_members(GroupName),
    %% kill process
    syn_test_suite_helper:kill_process(Pid),
    timer:sleep(200),
    %% retrieve
    false = syn:member(Pid, GroupName),
    [] = syn:get_members(GroupName).

two_nodes_join_monitor_and_unregister(Config) ->
    GroupName = "my group",
    %% get slave
    SlaveNode = proplists:get_value(slave_node, Config),
    %% start
    ok = syn_test_suite_helper:start_syn(),
    ok = rpc:call(SlaveNode, syn_test_suite_helper, start_syn, []),
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
    false = rpc:call(SlaveNode, syn, member, [OtherPid, GroupName]).

two_nodes_local_members(Config) ->
    GroupName = "my group",
    %% get slave
    SlaveNode = proplists:get_value(slave_node, Config),
    %% start
    ok = syn_test_suite_helper:start_syn(),
    ok = rpc:call(SlaveNode, syn_test_suite_helper, start_syn, []),
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
    [] = rpc:call(SlaveNode, syn, get_local_members, [GroupName, with_meta]).

two_nodes_groups_count(Config) ->
    %% get slave
    SlaveNode = proplists:get_value(slave_node, Config),
    %% start
    ok = syn_test_suite_helper:start_syn(),
    ok = rpc:call(SlaveNode, syn_test_suite_helper, start_syn, []),
    timer:sleep(100),
    %% start processes
    LocalPid = syn_test_suite_helper:start_process(),
    RemotePid = syn_test_suite_helper:start_process(SlaveNode),
    RemotePidRegRemote = syn_test_suite_helper:start_process(SlaveNode),
    _PidUnjoined = syn_test_suite_helper:start_process(),
    %% join
    ok = syn:join(<<"local group">>, LocalPid),
    ok = syn:join(<<"remote group">>, RemotePid),
    ok = rpc:call(SlaveNode, syn, join, [<<"remote group join_remote">>, RemotePidRegRemote]),
    timer:sleep(500),
    %% count
    3 = syn:groups_count(),
    1 = syn:groups_count(node()),
    2 = syn:groups_count(SlaveNode),
    %% kill & unregister processes
    syn_test_suite_helper:kill_process(LocalPid),
    ok = syn:leave(<<"remote group">>, RemotePid),
    syn_test_suite_helper:kill_process(RemotePidRegRemote),
    timer:sleep(100),
    %% count
    0 = syn:groups_count(),
    0 = syn:groups_count(node()),
    0 = syn:groups_count(SlaveNode).

two_nodes_group_names(Config) ->
    %% get slave
    SlaveNode = proplists:get_value(slave_node, Config),
    %% start
    ok = syn_test_suite_helper:start_syn(),
    ok = rpc:call(SlaveNode, syn_test_suite_helper, start_syn, []),
    timer:sleep(100),
    %% start processes
    LocalPid = syn_test_suite_helper:start_process(),
    RemotePid = syn_test_suite_helper:start_process(SlaveNode),
    RemotePidRegRemote = syn_test_suite_helper:start_process(SlaveNode),
    _PidUnjoined = syn_test_suite_helper:start_process(),
    %% join
    ok = syn:join(<<"local group">>, LocalPid),
    ok = syn:join(<<"remote group">>, RemotePid),
    ok = rpc:call(SlaveNode, syn, join, [<<"remote group join_remote">>, RemotePidRegRemote]),
    timer:sleep(500),
    %% names
    GroupNames = syn:get_group_names(),
    3 = length(GroupNames),
    true = lists:member(<<"local group">>, GroupNames),
    true = lists:member(<<"remote group">>, GroupNames),
    true = lists:member(<<"remote group join_remote">>, GroupNames),
    %% kill & unregister processes
    syn_test_suite_helper:kill_process(LocalPid),
    ok = syn:leave(<<"remote group">>, RemotePid),
    syn_test_suite_helper:kill_process(RemotePidRegRemote),
    timer:sleep(100),
    %% names
    [] = syn:get_group_names().

two_nodes_publish(Config) ->
    GroupName = "my group",
    Message = {test, message},
    %% get slave
    SlaveNode = proplists:get_value(slave_node, Config),
    %% start
    ok = syn_test_suite_helper:start_syn(),
    ok = rpc:call(SlaveNode, syn_test_suite_helper, start_syn, []),
    timer:sleep(100),
    %% start processes
    ResultPid = self(),
    F = fun() ->
        receive
            Message -> ResultPid ! {received, self(), Message}
        end
    end,
    LocalPid = syn_test_suite_helper:start_process(F),
    LocalPid2 = syn_test_suite_helper:start_process(F),
    RemotePid = syn_test_suite_helper:start_process(SlaveNode, F),
    RemotePid2 = syn_test_suite_helper:start_process(SlaveNode, F),
    OtherPid = syn_test_suite_helper:start_process(F),
    %% join
    ok = syn:join(GroupName, LocalPid),
    ok = syn:join(GroupName, LocalPid2),
    ok = syn:join(GroupName, RemotePid),
    ok = syn:join(GroupName, RemotePid2),
    timer:sleep(200),
    %% send
    {ok, 4} = syn:publish(GroupName, Message),
    %% check
    receive
        {received, LocalPid, Message} -> ok
    after 2000 ->
        ok = published_message_was_not_received_by_local_pid
    end,
    receive
        {received, LocalPid2, Message} -> ok
    after 2000 ->
        ok = published_message_was_not_received_by_local_pid_2
    end,
    receive
        {received, RemotePid, Message} -> ok
    after 2000 ->
        ok = published_message_was_not_received_by_remote_pid
    end,
    receive
        {received, RemotePid2, Message} -> ok
    after 2000 ->
        ok = published_message_was_not_received_by_remote_pid_2
    end,
    receive
        {received, OtherPid, Message} ->
            ok = published_message_was_received_by_other_pid
    after 250 ->
        ok
    end.

two_nodes_local_publish(Config) ->
    GroupName = "my group",
    Message = {test, message},
    %% get slave
    SlaveNode = proplists:get_value(slave_node, Config),
    %% start
    ok = syn_test_suite_helper:start_syn(),
    ok = rpc:call(SlaveNode, syn_test_suite_helper, start_syn, []),
    timer:sleep(100),
    %% start processes
    ResultPid = self(),
    F = fun() ->
        receive
            Message -> ResultPid ! {received, self(), Message}
        end
    end,
    LocalPid = syn_test_suite_helper:start_process(F),
    LocalPid2 = syn_test_suite_helper:start_process(F),
    RemotePid = syn_test_suite_helper:start_process(SlaveNode, F),
    RemotePid2 = syn_test_suite_helper:start_process(SlaveNode, F),
    OtherPid = syn_test_suite_helper:start_process(F),
    %% join
    ok = syn:join(GroupName, LocalPid),
    ok = syn:join(GroupName, LocalPid2),
    ok = syn:join(GroupName, RemotePid),
    ok = syn:join(GroupName, RemotePid2),
    timer:sleep(200),
    %% send
    {ok, 2} = syn:publish_to_local(GroupName, Message),
    %% check
    receive
        {received, LocalPid, Message} -> ok
    after 2000 ->
        ok = published_message_was_not_received_by_local_pid
    end,
    receive
        {received, LocalPid2, Message} -> ok
    after 2000 ->
        ok = published_message_was_not_received_by_local_pid_2
    end,
    receive
        {received, RemotePid, Message} ->
            ok = published_message_was_received_by_remote_pid
    after 250 ->
        ok
    end,
    receive
        {received, RemotePid, Message} ->
            ok = published_message_was_received_by_remote_pid_2
    after 250 ->
        ok
    end,
    receive
        {received, OtherPid, Message} ->
            ok = published_message_was_received_by_other_pid
    after 250 ->
        ok
    end.

two_nodes_multicall(Config) ->
    GroupName = <<"my group">>,
    %% get slave
    SlaveNode = proplists:get_value(slave_node, Config),
    %% start
    ok = syn_test_suite_helper:start_syn(),
    ok = rpc:call(SlaveNode, syn_test_suite_helper, start_syn, []),
    timer:sleep(100),
    %% start processes
    F = fun() ->
        receive
            {syn_multi_call, RequestorPid, get_pid_name} ->
                syn:multi_call_reply(RequestorPid, {pong, self()})
        end
    end,
    Pid1 = syn_test_suite_helper:start_process(F),
    Pid2 = syn_test_suite_helper:start_process(SlaveNode, F),
    PidUnresponsive = syn_test_suite_helper:start_process(),
    %% register
    ok = syn:join(GroupName, Pid1),
    ok = syn:join(GroupName, Pid2),
    ok = syn:join(GroupName, PidUnresponsive),
    timer:sleep(500),
    %% call
    {Replies, BadPids} = syn:multi_call(GroupName, get_pid_name),
    %% check responses
    true = lists:sort([
        {Pid1, {pong, Pid1}},
        {Pid2, {pong, Pid2}}
    ]) =:= lists:sort(Replies),
    [PidUnresponsive] = BadPids.

two_nodes_groups_full_cluster_sync_on_boot_node_added_later(_Config) ->
    %% stop slave
    syn_test_suite_helper:stop_slave(syn_slave),
    %% start syn on local node
    ok = syn_test_suite_helper:start_syn(),
    %% start process
    Pid = syn_test_suite_helper:start_process(),
    %% register
    ok = syn:join(<<"group">>, Pid),
    %% start remote node and syn
    {ok, SlaveNode} = syn_test_suite_helper:start_slave(syn_slave),
    ok = rpc:call(SlaveNode, syn_test_suite_helper, start_syn, []),
    timer:sleep(1000),
    %% check
    [Pid] = syn:get_members(<<"group">>),
    [Pid] = rpc:call(SlaveNode, syn, get_members, [<<"group">>]).

two_nodes_groups_full_cluster_sync_on_boot_syn_started_later(Config) ->
    %% get slaves
    SlaveNode = proplists:get_value(slave_node, Config),
    %% start syn on local node
    ok = syn_test_suite_helper:start_syn(),
    %% start process
    Pid = syn_test_suite_helper:start_process(),
    %% register
    ok = syn:join(<<"group">>, Pid),
    %% start ib remote syn
    ok = rpc:call(SlaveNode, syn_test_suite_helper, start_syn, []),
    timer:sleep(500),
    %% check
    [Pid] = syn:get_members(<<"group">>),
    [Pid] = rpc:call(SlaveNode, syn, get_members, [<<"group">>]).

three_nodes_partial_netsplit_consistency(Config) ->
    GroupName = "my group",
    %% get slaves
    SlaveNode1 = proplists:get_value(slave_node_1, Config),
    SlaveNode2 = proplists:get_value(slave_node_2, Config),
    %% start syn on nodes
    ok = syn_test_suite_helper:start_syn(),
    ok = rpc:call(SlaveNode1, syn_test_suite_helper, start_syn, []),
    ok = rpc:call(SlaveNode2, syn_test_suite_helper, start_syn, []),
    timer:sleep(100),
    %% start processes
    Pid0 = syn_test_suite_helper:start_process(),
    Pid0Changed = syn_test_suite_helper:start_process(),
    Pid1 = syn_test_suite_helper:start_process(SlaveNode1),
    Pid2 = syn_test_suite_helper:start_process(SlaveNode2),
    OtherPid = syn_test_suite_helper:start_process(),
    timer:sleep(100),
    %% retrieve local
    [] = syn:get_members("group-1"),
    [] = syn:get_members(GroupName),
    [] = syn:get_members(GroupName, with_meta),
    false = syn:member(Pid0, GroupName),
    false = syn:member(Pid0Changed, GroupName),
    false = syn:member(Pid1, GroupName),
    false = syn:member(Pid2, GroupName),
    %% retrieve slave 1
    [] = rpc:call(SlaveNode1, syn, get_members, [GroupName]),
    [] = rpc:call(SlaveNode1, syn, get_members, [GroupName, with_meta]),
    false = rpc:call(SlaveNode1, syn, member, [Pid0, GroupName]),
    false = rpc:call(SlaveNode1, syn, member, [Pid0Changed, GroupName]),
    false = rpc:call(SlaveNode1, syn, member, [Pid1, GroupName]),
    false = rpc:call(SlaveNode1, syn, member, [Pid2, GroupName]),
    %% retrieve slave 2
    [] = rpc:call(SlaveNode2, syn, get_members, [GroupName]),
    [] = rpc:call(SlaveNode2, syn, get_members, [GroupName, with_meta]),
    false = rpc:call(SlaveNode2, syn, member, [Pid0, GroupName]),
    false = rpc:call(SlaveNode2, syn, member, [Pid0Changed, GroupName]),
    false = rpc:call(SlaveNode2, syn, member, [Pid1, GroupName]),
    false = rpc:call(SlaveNode2, syn, member, [Pid2, GroupName]),
    %% join
    ok = syn:join(GroupName, Pid0),
    ok = syn:join(GroupName, Pid0Changed, {meta, changed}),
    ok = rpc:call(SlaveNode1, syn, join, [GroupName, Pid1]),
    ok = rpc:call(SlaveNode2, syn, join, [GroupName, Pid2, {meta, 2}]),
    ok = syn:join("other-group", OtherPid),
    timer:sleep(200),
    %% retrieve local
    true = lists:sort([Pid0, Pid0Changed, Pid1, Pid2]) =:= lists:sort(syn:get_members(GroupName)),
    true = lists:sort([
        {Pid0, undefined},
        {Pid0Changed, {meta, changed}},
        {Pid1, undefined},
        {Pid2, {meta, 2}}
    ]) =:= lists:sort(syn:get_members(GroupName, with_meta)),
    true = syn:member(Pid0, GroupName),
    true = syn:member(Pid0Changed, GroupName),
    true = syn:member(Pid1, GroupName),
    true = syn:member(Pid2, GroupName),
    false = syn:member(OtherPid, GroupName),
    %% retrieve slave 1
    true = lists:sort([Pid0, Pid0Changed, Pid1, Pid2])
        =:= lists:sort(rpc:call(SlaveNode1, syn, get_members, [GroupName])),
    true = lists:sort([
        {Pid0, undefined},
        {Pid0Changed, {meta, changed}},
        {Pid1, undefined},
        {Pid2, {meta, 2}}
    ]) =:= lists:sort(rpc:call(SlaveNode1, syn, get_members, [GroupName, with_meta])),
    true = rpc:call(SlaveNode1, syn, member, [Pid0, GroupName]),
    true = rpc:call(SlaveNode1, syn, member, [Pid0Changed, GroupName]),
    true = rpc:call(SlaveNode1, syn, member, [Pid1, GroupName]),
    true = rpc:call(SlaveNode1, syn, member, [Pid2, GroupName]),
    false = rpc:call(SlaveNode1, syn, member, [OtherPid, GroupName]),
    %% retrieve slave 2
    true = lists:sort([Pid0, Pid0Changed, Pid1, Pid2])
        =:= lists:sort(rpc:call(SlaveNode2, syn, get_members, [GroupName])),
    true = lists:sort([
        {Pid0, undefined},
        {Pid0Changed, {meta, changed}},
        {Pid1, undefined},
        {Pid2, {meta, 2}}
    ]) =:= lists:sort(rpc:call(SlaveNode2, syn, get_members, [GroupName, with_meta])),
    true = rpc:call(SlaveNode2, syn, member, [Pid0, GroupName]),
    true = rpc:call(SlaveNode2, syn, member, [Pid0Changed, GroupName]),
    true = rpc:call(SlaveNode2, syn, member, [Pid1, GroupName]),
    true = rpc:call(SlaveNode2, syn, member, [Pid2, GroupName]),
    false = rpc:call(SlaveNode2, syn, member, [OtherPid, GroupName]),
    %% disconnect slave 2 from main (slave 1 can still see slave 2)
    syn_test_suite_helper:disconnect_node(SlaveNode2),
    timer:sleep(500),
    %% retrieve local
    true = lists:sort([Pid0, Pid0Changed, Pid1]) =:= lists:sort(syn:get_members(GroupName)),
    true = lists:sort([
        {Pid0, undefined},
        {Pid0Changed, {meta, changed}},
        {Pid1, undefined}
    ]) =:= lists:sort(syn:get_members(GroupName, with_meta)),
    true = syn:member(Pid0, GroupName),
    true = syn:member(Pid0Changed, GroupName),
    true = syn:member(Pid1, GroupName),
    false = syn:member(Pid2, GroupName),
    false = syn:member(OtherPid, GroupName),
    %% retrieve slave 1
    true = lists:sort([Pid0, Pid0Changed, Pid1, Pid2])
        =:= lists:sort(rpc:call(SlaveNode1, syn, get_members, [GroupName])),
    true = lists:sort([
        {Pid0, undefined},
        {Pid0Changed, {meta, changed}},
        {Pid1, undefined},
        {Pid2, {meta, 2}}
    ]) =:= lists:sort(rpc:call(SlaveNode1, syn, get_members, [GroupName, with_meta])),
    true = rpc:call(SlaveNode1, syn, member, [Pid0, GroupName]),
    true = rpc:call(SlaveNode1, syn, member, [Pid0Changed, GroupName]),
    true = rpc:call(SlaveNode1, syn, member, [Pid1, GroupName]),
    true = rpc:call(SlaveNode1, syn, member, [Pid2, GroupName]),
    false = rpc:call(SlaveNode1, syn, member, [OtherPid, GroupName]),
    %% disconnect slave 1
    syn_test_suite_helper:disconnect_node(SlaveNode1),
    timer:sleep(500),
    %% leave 0Changed
    ok = syn:leave(GroupName, Pid0Changed),
    %% retrieve local
    true = lists:sort([Pid0]) =:= lists:sort(syn:get_members(GroupName)),
    true = lists:sort([
        {Pid0, undefined}
    ]) =:= lists:sort(syn:get_members(GroupName, with_meta)),
    true = syn:member(Pid0, GroupName),
    false = syn:member(Pid0Changed, GroupName),
    false = syn:member(Pid1, GroupName),
    false = syn:member(Pid2, GroupName),
    false = syn:member(OtherPid, GroupName),
    %% reconnect all
    syn_test_suite_helper:connect_node(SlaveNode1),
    syn_test_suite_helper:connect_node(SlaveNode2),
    timer:sleep(5000),
    %% retrieve local
    true = lists:sort([Pid0, Pid1, Pid2]) =:= lists:sort(syn:get_members(GroupName)),
    true = lists:sort([
        {Pid0, undefined},
        {Pid1, undefined},
        {Pid2, {meta, 2}}
    ]) =:= lists:sort(syn:get_members(GroupName, with_meta)),
    true = syn:member(Pid0, GroupName),
    false = syn:member(Pid0Changed, GroupName),
    true = syn:member(Pid1, GroupName),
    true = syn:member(Pid2, GroupName),
    false = syn:member(OtherPid, GroupName),
    %% retrieve slave 1
    true = lists:sort([Pid0, Pid1, Pid2])
        =:= lists:sort(rpc:call(SlaveNode1, syn, get_members, [GroupName])),
    true = lists:sort([
        {Pid0, undefined},
        {Pid1, undefined},
        {Pid2, {meta, 2}}
    ]) =:= lists:sort(rpc:call(SlaveNode1, syn, get_members, [GroupName, with_meta])),
    true = rpc:call(SlaveNode1, syn, member, [Pid0, GroupName]),
    false = rpc:call(SlaveNode1, syn, member, [Pid0Changed, GroupName]),
    true = rpc:call(SlaveNode1, syn, member, [Pid1, GroupName]),
    true = rpc:call(SlaveNode1, syn, member, [Pid2, GroupName]),
    false = rpc:call(SlaveNode1, syn, member, [OtherPid, GroupName]),
    %% retrieve slave 2
    true = lists:sort([Pid0, Pid1, Pid2])
        =:= lists:sort(rpc:call(SlaveNode2, syn, get_members, [GroupName])),
    true = lists:sort([
        {Pid0, undefined},
        {Pid1, undefined},
        {Pid2, {meta, 2}}
    ]) =:= lists:sort(rpc:call(SlaveNode2, syn, get_members, [GroupName, with_meta])),
    true = rpc:call(SlaveNode2, syn, member, [Pid0, GroupName]),
    false = rpc:call(SlaveNode2, syn, member, [Pid0Changed, GroupName]),
    true = rpc:call(SlaveNode2, syn, member, [Pid1, GroupName]),
    true = rpc:call(SlaveNode2, syn, member, [Pid2, GroupName]),
    false = rpc:call(SlaveNode2, syn, member, [OtherPid, GroupName]).

three_nodes_full_netsplit_consistency(Config) ->
    GroupName = "my group",
    %% get slaves
    SlaveNode1 = proplists:get_value(slave_node_1, Config),
    SlaveNode2 = proplists:get_value(slave_node_2, Config),
    %% start syn on nodes
    ok = syn_test_suite_helper:start_syn(),
    ok = rpc:call(SlaveNode1, syn_test_suite_helper, start_syn, []),
    ok = rpc:call(SlaveNode2, syn_test_suite_helper, start_syn, []),
    timer:sleep(100),
    %% start processes
    Pid0 = syn_test_suite_helper:start_process(),
    Pid0Changed = syn_test_suite_helper:start_process(),
    Pid1 = syn_test_suite_helper:start_process(SlaveNode1),
    Pid2 = syn_test_suite_helper:start_process(SlaveNode2),
    OtherPid = syn_test_suite_helper:start_process(),
    timer:sleep(100),
    %% retrieve local
    [] = syn:get_members("group-1"),
    [] = syn:get_members(GroupName),
    [] = syn:get_members(GroupName, with_meta),
    false = syn:member(Pid0, GroupName),
    false = syn:member(Pid0Changed, GroupName),
    false = syn:member(Pid1, GroupName),
    false = syn:member(Pid2, GroupName),
    %% retrieve slave 1
    [] = rpc:call(SlaveNode1, syn, get_members, [GroupName]),
    [] = rpc:call(SlaveNode1, syn, get_members, [GroupName, with_meta]),
    false = rpc:call(SlaveNode1, syn, member, [Pid0, GroupName]),
    false = rpc:call(SlaveNode1, syn, member, [Pid0Changed, GroupName]),
    false = rpc:call(SlaveNode1, syn, member, [Pid1, GroupName]),
    false = rpc:call(SlaveNode1, syn, member, [Pid2, GroupName]),
    %% retrieve slave 2
    [] = rpc:call(SlaveNode2, syn, get_members, [GroupName]),
    [] = rpc:call(SlaveNode2, syn, get_members, [GroupName, with_meta]),
    false = rpc:call(SlaveNode2, syn, member, [Pid0, GroupName]),
    false = rpc:call(SlaveNode2, syn, member, [Pid0Changed, GroupName]),
    false = rpc:call(SlaveNode2, syn, member, [Pid1, GroupName]),
    false = rpc:call(SlaveNode2, syn, member, [Pid2, GroupName]),
    %% join
    ok = syn:join(GroupName, Pid0),
    ok = syn:join(GroupName, Pid0Changed, {meta, changed}),
    ok = rpc:call(SlaveNode1, syn, join, [GroupName, Pid1]),
    ok = rpc:call(SlaveNode2, syn, join, [GroupName, Pid2, {meta, 2}]),
    ok = syn:join("other-group", OtherPid),
    timer:sleep(200),
    %% retrieve local
    true = lists:sort([Pid0, Pid0Changed, Pid1, Pid2]) =:= lists:sort(syn:get_members(GroupName)),
    true = lists:sort([
        {Pid0, undefined},
        {Pid0Changed, {meta, changed}},
        {Pid1, undefined},
        {Pid2, {meta, 2}}
    ]) =:= lists:sort(syn:get_members(GroupName, with_meta)),
    true = syn:member(Pid0, GroupName),
    true = syn:member(Pid0Changed, GroupName),
    true = syn:member(Pid1, GroupName),
    true = syn:member(Pid2, GroupName),
    false = syn:member(OtherPid, GroupName),
    %% retrieve slave 1
    true = lists:sort([Pid0, Pid0Changed, Pid1, Pid2])
        =:= lists:sort(rpc:call(SlaveNode1, syn, get_members, [GroupName])),
    true = lists:sort([
        {Pid0, undefined},
        {Pid0Changed, {meta, changed}},
        {Pid1, undefined},
        {Pid2, {meta, 2}}
    ]) =:= lists:sort(rpc:call(SlaveNode1, syn, get_members, [GroupName, with_meta])),
    true = rpc:call(SlaveNode1, syn, member, [Pid0, GroupName]),
    true = rpc:call(SlaveNode1, syn, member, [Pid0Changed, GroupName]),
    true = rpc:call(SlaveNode1, syn, member, [Pid1, GroupName]),
    true = rpc:call(SlaveNode1, syn, member, [Pid2, GroupName]),
    false = rpc:call(SlaveNode1, syn, member, [OtherPid, GroupName]),
    %% retrieve slave 2
    true = lists:sort([Pid0, Pid0Changed, Pid1, Pid2])
        =:= lists:sort(rpc:call(SlaveNode2, syn, get_members, [GroupName])),
    true = lists:sort([
        {Pid0, undefined},
        {Pid0Changed, {meta, changed}},
        {Pid1, undefined},
        {Pid2, {meta, 2}}
    ]) =:= lists:sort(rpc:call(SlaveNode2, syn, get_members, [GroupName, with_meta])),
    true = rpc:call(SlaveNode2, syn, member, [Pid0, GroupName]),
    true = rpc:call(SlaveNode2, syn, member, [Pid0Changed, GroupName]),
    true = rpc:call(SlaveNode2, syn, member, [Pid1, GroupName]),
    true = rpc:call(SlaveNode2, syn, member, [Pid2, GroupName]),
    false = rpc:call(SlaveNode2, syn, member, [OtherPid, GroupName]),
    %% disconnect everyone
    rpc:call(SlaveNode1, syn_test_suite_helper, disconnect_node, [SlaveNode2]),
    syn_test_suite_helper:disconnect_node(SlaveNode1),
    syn_test_suite_helper:disconnect_node(SlaveNode2),
    timer:sleep(2000),
    %% leave 0Changed
    ok = syn:leave(GroupName, Pid0Changed),
    timer:sleep(500),
    %% retrieve local
    true = lists:sort([Pid0]) =:= lists:sort(syn:get_members(GroupName)),
    true = lists:sort([
        {Pid0, undefined}
    ]) =:= lists:sort(syn:get_members(GroupName, with_meta)),
    true = syn:member(Pid0, GroupName),
    false = syn:member(Pid0Changed, GroupName),
    false = syn:member(Pid1, GroupName),
    false = syn:member(Pid2, GroupName),
    false = syn:member(OtherPid, GroupName),
    %% reconnect all
    syn_test_suite_helper:connect_node(SlaveNode1),
    syn_test_suite_helper:connect_node(SlaveNode2),
    rpc:call(SlaveNode1, syn_test_suite_helper, connect_node, [SlaveNode2]),
    timer:sleep(1500),
    %% retrieve local
    true = lists:sort([Pid0, Pid1, Pid2]) =:= lists:sort(syn:get_members(GroupName)),
    true = lists:sort([
        {Pid0, undefined},
        {Pid1, undefined},
        {Pid2, {meta, 2}}
    ]) =:= lists:sort(syn:get_members(GroupName, with_meta)),
    true = syn:member(Pid0, GroupName),
    false = syn:member(Pid0Changed, GroupName),
    true = syn:member(Pid1, GroupName),
    true = syn:member(Pid2, GroupName),
    false = syn:member(OtherPid, GroupName),
    %% retrieve slave 1
    true = lists:sort([Pid0, Pid1, Pid2])
        =:= lists:sort(rpc:call(SlaveNode1, syn, get_members, [GroupName])),
    true = lists:sort([
        {Pid0, undefined},
        {Pid1, undefined},
        {Pid2, {meta, 2}}
    ]) =:= lists:sort(rpc:call(SlaveNode1, syn, get_members, [GroupName, with_meta])),
    true = rpc:call(SlaveNode1, syn, member, [Pid0, GroupName]),
    false = rpc:call(SlaveNode1, syn, member, [Pid0Changed, GroupName]),
    true = rpc:call(SlaveNode1, syn, member, [Pid1, GroupName]),
    true = rpc:call(SlaveNode1, syn, member, [Pid2, GroupName]),
    false = rpc:call(SlaveNode1, syn, member, [OtherPid, GroupName]),
    %% retrieve slave 2
    true = lists:sort([Pid0, Pid1, Pid2])
        =:= lists:sort(rpc:call(SlaveNode2, syn, get_members, [GroupName])),
    true = lists:sort([
        {Pid0, undefined},
        {Pid1, undefined},
        {Pid2, {meta, 2}}
    ]) =:= lists:sort(rpc:call(SlaveNode2, syn, get_members, [GroupName, with_meta])),
    true = rpc:call(SlaveNode2, syn, member, [Pid0, GroupName]),
    false = rpc:call(SlaveNode2, syn, member, [Pid0Changed, GroupName]),
    true = rpc:call(SlaveNode2, syn, member, [Pid1, GroupName]),
    true = rpc:call(SlaveNode2, syn, member, [Pid2, GroupName]),
    false = rpc:call(SlaveNode2, syn, member, [OtherPid, GroupName]).

three_nodes_anti_entropy(Config) ->
    %% get slaves
    SlaveNode1 = proplists:get_value(slave_node_1, Config),
    SlaveNode2 = proplists:get_value(slave_node_2, Config),
    %% set anti-entropy with a very low interval (0.25 second)
    syn_test_suite_helper:use_anti_entropy(groups, 0.25),
    rpc:call(SlaveNode1, syn_test_suite_helper, use_anti_entropy, [groups, 0.25]),
    rpc:call(SlaveNode2, syn_test_suite_helper, use_anti_entropy, [groups, 0.25]),
    %% start syn on nodes
    ok = syn_test_suite_helper:start_syn(),
    ok = rpc:call(SlaveNode1, syn_test_suite_helper, start_syn, []),
    ok = rpc:call(SlaveNode2, syn_test_suite_helper, start_syn, []),
    timer:sleep(100),
    %% start processes
    Pid0 = syn_test_suite_helper:start_process(),
    Pid1 = syn_test_suite_helper:start_process(SlaveNode1),
    Pid2 = syn_test_suite_helper:start_process(SlaveNode2),
    Pid2Isolated = syn_test_suite_helper:start_process(SlaveNode2),
    timer:sleep(100),
    %% inject data to simulate latent conflicts
    ok = syn_groups:add_to_local_table("my-group", Pid0, node(), undefined),
    ok = rpc:call(SlaveNode1, syn_groups, add_to_local_table, ["my-group", Pid1, SlaveNode1, undefined]),
    ok = rpc:call(SlaveNode2, syn_groups, add_to_local_table, ["my-group", Pid2, SlaveNode2, undefined]),
    ok = rpc:call(SlaveNode2, syn_groups, add_to_local_table, ["my-group-isolated", Pid2Isolated, SlaveNode2, undefined]),
    timer:sleep(5000),
    %% check
    Members = lists:sort([
        {Pid0, node()},
        {Pid1, SlaveNode1},
        {Pid2, SlaveNode2}
    ]),
    Members = syn:get_members("my-group", with_meta),
    Members = rpc:call(SlaveNode1, syn, get_members, ["my-group", with_meta]),
    Members = rpc:call(SlaveNode2, syn, get_members, ["my-group", with_meta]),
    [{Pid2Isolated, SlaveNode2}] = syn:get_members("my-group-isolated", with_meta),
    [{Pid2Isolated, SlaveNode2}] = rpc:call(SlaveNode1, syn, get_members, ["my-group-isolated", with_meta]),
    [{Pid2Isolated, SlaveNode2}] = rpc:call(SlaveNode2, syn, get_members, ["my-group-isolated", with_meta]).

three_nodes_anti_entropy_manual(Config) ->
    %% get slaves
    SlaveNode1 = proplists:get_value(slave_node_1, Config),
    SlaveNode2 = proplists:get_value(slave_node_2, Config),
    %% start syn on nodes
    ok = syn_test_suite_helper:start_syn(),
    ok = rpc:call(SlaveNode1, syn_test_suite_helper, start_syn, []),
    ok = rpc:call(SlaveNode2, syn_test_suite_helper, start_syn, []),
    timer:sleep(100),
    %% start processes
    Pid0 = syn_test_suite_helper:start_process(),
    Pid1 = syn_test_suite_helper:start_process(SlaveNode1),
    Pid2 = syn_test_suite_helper:start_process(SlaveNode2),
    Pid2Isolated = syn_test_suite_helper:start_process(SlaveNode2),
    timer:sleep(100),
    %% inject data to simulate latent conflicts
    ok = syn_groups:add_to_local_table("my-group", Pid0, node(), undefined),
    ok = rpc:call(SlaveNode1, syn_groups, add_to_local_table, ["my-group", Pid1, SlaveNode1, undefined]),
    ok = rpc:call(SlaveNode2, syn_groups, add_to_local_table, ["my-group", Pid2, SlaveNode2, undefined]),
    ok = rpc:call(SlaveNode2, syn_groups, add_to_local_table, ["my-group-isolated", Pid2Isolated, SlaveNode2, undefined]),
    %% call anti entropy
    ok = syn:force_cluster_sync(groups),
    timer:sleep(5000),
    %% check
    Members = lists:sort([
        {Pid0, node()},
        {Pid1, SlaveNode1},
        {Pid2, SlaveNode2}
    ]),
    Members = syn:get_members("my-group", with_meta),
    Members = rpc:call(SlaveNode1, syn, get_members, ["my-group", with_meta]),
    Members = rpc:call(SlaveNode2, syn, get_members, ["my-group", with_meta]),
    [{Pid2Isolated, SlaveNode2}] = syn:get_members("my-group-isolated", with_meta),
    [{Pid2Isolated, SlaveNode2}] = rpc:call(SlaveNode1, syn, get_members, ["my-group-isolated", with_meta]),
    [{Pid2Isolated, SlaveNode2}] = rpc:call(SlaveNode2, syn, get_members, ["my-group-isolated", with_meta]).
