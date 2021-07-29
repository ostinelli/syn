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
    single_node_register_unregister_and_kill_process/1,
    single_node_registration_errors/1,
    single_node_registry_count/1,
    single_node_register_gen_server/1,
    single_node_callback_on_process_exit/1,
    single_node_ensure_callback_process_exit_is_called_if_process_killed/1,
    single_node_monitor_after_registry_crash/1
]).
-export([
    two_nodes_register_monitor_and_unregister/1,
    two_nodes_registry_count/1,
    two_nodes_registration_race_condition_conflict_resolution_keep_more_recent_remote/1,
    two_nodes_registration_race_condition_conflict_resolution_keep_more_recent_local/1,
    two_nodes_registration_race_condition_conflict_resolution_keep_remote_with_custom_handler/1,
    two_nodes_registration_race_condition_conflict_resolution_keep_local_with_custom_handler/1,
    two_nodes_registration_race_condition_conflict_resolution_when_process_died/1,
    two_nodes_registry_full_cluster_sync_on_boot_node_added_later/1,
    two_nodes_registry_full_cluster_sync_on_boot_syn_started_later/1,
    two_nodes_unregister_and_register/1
]).
-export([
    three_nodes_partial_netsplit_consistency/1,
    three_nodes_full_netsplit_consistency/1,
    three_nodes_start_syn_before_connecting_cluster_with_conflict_keep_more_recent/1,
    three_nodes_start_syn_before_connecting_cluster_with_custom_conflict_resolution_keep_remote/1,
    three_nodes_registration_race_condition_custom_conflict_resolution/1,
    three_nodes_anti_entropy/1,
    three_nodes_anti_entropy_manual/1,
    three_nodes_concurrent_registration_unregistration/1,
    three_nodes_resolve_conflict_on_all_nodes/1
]).

%% support
-export([
    start_syn_delayed_and_register_local_process/3,
    start_syn_delayed_with_custom_handler_register_local_process/4,
    seq_unregister_register/3
]).

%% include
-include_lib("common_test/include/ct.hrl").
-include_lib("../src/syn.hrl").

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
        {group, single_node_process_registration},
        {group, two_nodes_process_registration},
        {group, three_nodes_process_registration}
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
        {single_node_process_registration, [shuffle], [
            single_node_register_and_monitor,
            single_node_register_and_unregister,
            single_node_register_unregister_and_kill_process,
            single_node_registration_errors,
            single_node_registry_count,
            single_node_register_gen_server,
            single_node_callback_on_process_exit,
            single_node_ensure_callback_process_exit_is_called_if_process_killed,
            single_node_monitor_after_registry_crash
        ]},
        {two_nodes_process_registration, [shuffle], [
            two_nodes_register_monitor_and_unregister,
            two_nodes_registry_count,
            two_nodes_registration_race_condition_conflict_resolution_keep_more_recent_remote,
            two_nodes_registration_race_condition_conflict_resolution_keep_more_recent_local,
            two_nodes_registration_race_condition_conflict_resolution_keep_remote_with_custom_handler,
            two_nodes_registration_race_condition_conflict_resolution_keep_local_with_custom_handler,
            two_nodes_registration_race_condition_conflict_resolution_when_process_died,
            two_nodes_registry_full_cluster_sync_on_boot_node_added_later,
            two_nodes_registry_full_cluster_sync_on_boot_syn_started_later,
            two_nodes_unregister_and_register
        ]},
        {three_nodes_process_registration, [shuffle], [
            three_nodes_partial_netsplit_consistency,
            three_nodes_full_netsplit_consistency,
            three_nodes_start_syn_before_connecting_cluster_with_conflict_keep_more_recent,
            three_nodes_start_syn_before_connecting_cluster_with_custom_conflict_resolution_keep_remote,
            three_nodes_registration_race_condition_custom_conflict_resolution,
            three_nodes_anti_entropy,
            three_nodes_anti_entropy_manual,
            three_nodes_concurrent_registration_unregistration,
            three_nodes_resolve_conflict_on_all_nodes
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
    syn_test_suite_helper:clean_after_test(),
    syn_test_suite_helper:stop_slave(syn_slave),
    timer:sleep(1000);
end_per_group(three_nodes_process_registration, Config) ->
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
single_node_register_and_monitor(_Config) ->
    %% start
    ok = syn_test_suite_helper:start_syn(),
    %% start processes
    Pid = syn_test_suite_helper:start_process(),
    PidWithMeta = syn_test_suite_helper:start_process(),
    %% retrieve
    undefined = syn:whereis(<<"my proc">>),
    %% register
    ok = syn:register(<<"my proc">>, Pid),
    ok = syn:register({"my proc 2"}, Pid),
    ok = syn:register(<<"my proc with meta">>, PidWithMeta, {meta, <<"meta">>}),
    %% retrieve
    Pid = syn:whereis(<<"my proc">>),
    Pid = syn:whereis({"my proc 2"}),
    {PidWithMeta, {meta, <<"meta">>}} = syn:whereis(<<"my proc with meta">>, with_meta),
    %% re-register
    ok = syn:register(<<"my proc with meta">>, PidWithMeta, {meta2, <<"meta2">>}),
    {PidWithMeta, {meta2, <<"meta2">>}} = syn:whereis(<<"my proc with meta">>, with_meta),
    %% kill process
    syn_test_suite_helper:kill_process(Pid),
    syn_test_suite_helper:kill_process(PidWithMeta),
    timer:sleep(100),
    %% retrieve
    undefined = syn:whereis(<<"my proc">>),
    undefined = syn:whereis({"my proc 2"}),
    undefined = syn:whereis(<<"my proc with meta">>).

single_node_register_and_unregister(_Config) ->
    %% start
    ok = syn_test_suite_helper:start_syn(),
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
    undefined = syn:whereis(<<"my proc 2">>).

single_node_register_unregister_and_kill_process(_Config) ->
    %% start
    ok = syn_test_suite_helper:start_syn(),
    %% start process
    Pid = syn_test_suite_helper:start_process(),
    %% register
    ok = syn:register(<<"synonym_to_unregister">>, Pid),
    ok = syn:register(<<"synonym_to_keep">>, Pid),
    %% unregister
    ok = syn:unregister(<<"synonym_to_unregister">>),
    %% retrieve
    undefined = syn:whereis(<<"synonym_to_unregister">>),
    Pid = syn:whereis(<<"synonym_to_keep">>),
    %% kill process
    true = syn_test_suite_helper:kill_process(Pid),
    timer:sleep(100),
    %% retrieve
    undefined = syn:whereis(<<"synonym_to_keep">>).

single_node_registration_errors(_Config) ->
    %% start
    ok = syn_test_suite_helper:start_syn(),
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
    ok = syn_test_suite_helper:start_syn(),
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

single_node_register_gen_server(_Config) ->
    %% start
    ok = syn_test_suite_helper:start_syn(),
    %% start gen server via syn
    {ok, Pid} = syn_test_gen_server:start_link(),
    %% retrieve
    Pid = syn:whereis(syn_test_gen_server),
    %% call
    pong = syn_test_gen_server:ping(),
    %% send via syn
    syn:send(syn_test_gen_server, {self(), send_ping}),
    receive
        send_pong -> ok
    after 1000 ->
        ok = did_not_receive_gen_server_pong
    end,
    %% stop server
    syn_test_gen_server:stop(),
    timer:sleep(200),
    %% retrieve
    undefined = syn:whereis(syn_test_gen_server),
    %% send via syn
    {badarg, {syn_test_gen_server, anything}} = (catch syn:send(syn_test_gen_server, anything)).

single_node_callback_on_process_exit(_Config) ->
    %% use custom handler
    syn_test_suite_helper:use_custom_handler(),
    %% start
    ok = syn_test_suite_helper:start_syn(),
    %% start process
    Pid = syn_test_suite_helper:start_process(),
    Pid2 = syn_test_suite_helper:start_process(),
    %% register
    TestPid = self(),
    ok = syn:register(<<"my proc">>, Pid, {pid, TestPid}),
    ok = syn:register(<<"my proc - alternate">>, Pid, {pid_alternate, TestPid}),
    ok = syn:register(<<"my proc 2">>, Pid2, {pid2, TestPid}),
    %% kill 1
    syn_test_suite_helper:kill_process(Pid),
    receive
        {received_event_on, pid} ->
            ok;
        {received_event_on, pid2} ->
            ok = callback_on_process_exit_was_received_by_pid2
    after 1000 ->
        ok = callback_on_process_exit_was_not_received_by_pid
    end,
    receive
        {received_event_on, pid_alternate} ->
            ok;
        {received_event_on, pid2} ->
            ok = callback_on_process_exit_was_received_by_pid2
    after 1000 ->
        ok = callback_on_process_exit_was_not_received_by_pid
    end,
    %% unregister & kill 2
    ok = syn:unregister(<<"my proc 2">>),
    syn_test_suite_helper:kill_process(Pid2),
    receive
        {received_event_on, pid2} ->
            ok = callback_on_process_exit_was_received_by_pid2
    after 1000 ->
        ok
    end.

single_node_ensure_callback_process_exit_is_called_if_process_killed(_Config) ->
    Name = <<"my proc">>,
    %% use custom handler
    syn_test_suite_helper:use_custom_handler(),
    %% start
    ok = syn_test_suite_helper:start_syn(),
    %% start process
    Pid = syn_test_suite_helper:start_process(),
    %% register
    TestPid = self(),
    ok = syn:register(Name, Pid, {some_meta, TestPid}),
    %% remove from table to simulate conflict resolution
    syn_registry:remove_from_local_table(Name, TestPid),
    %% kill
    exit(Pid, {syn_resolve_kill, Name, {some_meta, TestPid}}),
    receive
        {received_event_on, some_meta} ->
            ok
    after 1000 ->
        ok = callback_on_process_exit_was_not_received_by_pid
    end.

single_node_monitor_after_registry_crash(_Config) ->
    %% start
    ok = syn_test_suite_helper:start_syn(),
    %% start processes
    Pid = syn_test_suite_helper:start_process(),
    %% register
    ok = syn:register(<<"my proc">>, Pid),
    %% kill registry
    syn_test_suite_helper:kill_sharded(syn_registry),
    timer:sleep(200),
    %% retrieve
    Pid = syn:whereis(<<"my proc">>),
    %% kill process
    syn_test_suite_helper:kill_process(Pid),
    timer:sleep(200),
    %% retrieve
    undefined = syn:whereis(<<"my proc 2">>).

two_nodes_register_monitor_and_unregister(Config) ->
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
    undefined = rpc:call(SlaveNode, syn, whereis, [<<"remote proc reg_remote">>]).

two_nodes_registry_count(Config) ->
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
    _PidUnregistered = syn_test_suite_helper:start_process(),
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
    0 = syn:registry_count(SlaveNode).

two_nodes_registration_race_condition_conflict_resolution_keep_more_recent_remote(Config) ->
    ConflictingName = "COMMON",
    %% get slaves
    SlaveNode = proplists:get_value(slave_node, Config),
    %% start syn on nodes
    ok = syn_test_suite_helper:start_syn(),
    ok = rpc:call(SlaveNode, syn_test_suite_helper, start_syn, []),
    timer:sleep(1000),
    %% start processes
    Pid0 = syn_test_suite_helper:start_process(),
    Pid1 = syn_test_suite_helper:start_process(SlaveNode),
    %% inject into syn to simulate concurrent registration
    ok = syn_registry:add_to_local_table(ConflictingName, Pid0, node(), erlang:system_time() - 1000000000, undefined),
    %% register on slave node to trigger conflict resolution on master node
    ok = rpc:call(SlaveNode, syn, register, [ConflictingName, Pid1, SlaveNode]),
    timer:sleep(1000),
    %% check metadata, resolution happens on master node
    {Pid1, SlaveNode} = syn:whereis(ConflictingName, with_meta),
    {Pid1, SlaveNode} = rpc:call(SlaveNode, syn, whereis, [ConflictingName, with_meta]),
    %% check that other processes are not alive because syn killed them
    false = is_process_alive(Pid0),
    true = rpc:call(SlaveNode, erlang, is_process_alive, [Pid1]).

two_nodes_registration_race_condition_conflict_resolution_keep_more_recent_local(Config) ->
    ConflictingName = "COMMON",
    %% get slaves
    SlaveNode = proplists:get_value(slave_node, Config),
    %% start syn on nodes
    ok = syn_test_suite_helper:start_syn(),
    ok = rpc:call(SlaveNode, syn_test_suite_helper, start_syn, []),
    timer:sleep(1000),
    %% start processes
    Pid0 = syn_test_suite_helper:start_process(),
    Pid1 = syn_test_suite_helper:start_process(SlaveNode),
    %% inject into syn to simulate concurrent registration
    ok = syn_registry:add_to_local_table(ConflictingName, Pid0, node(), erlang:system_time() + 1000000000, undefined),
    %% register on slave node to trigger conflict resolution on master node
    ok = rpc:call(SlaveNode, syn, register, [ConflictingName, Pid1, SlaveNode]),
    timer:sleep(1000),
    %% check metadata, resolution happens on master node
    Node = node(),
    {Pid0, Node} = syn:whereis(ConflictingName, with_meta),
    {Pid0, Node} = rpc:call(SlaveNode, syn, whereis, [ConflictingName, with_meta]),
    %% check that other processes are not alive because syn killed them
    true = is_process_alive(Pid0),
    false = rpc:call(SlaveNode, erlang, is_process_alive, [Pid1]).

two_nodes_registration_race_condition_conflict_resolution_keep_remote_with_custom_handler(Config) ->
    ConflictingName = "COMMON",
    %% get slaves
    SlaveNode = proplists:get_value(slave_node, Config),
    %% use customer handler
    syn_test_suite_helper:use_custom_handler(),
    rpc:call(SlaveNode, syn_test_suite_helper, use_custom_handler, []),
    %% start syn on nodes
    ok = syn_test_suite_helper:start_syn(),
    ok = rpc:call(SlaveNode, syn_test_suite_helper, start_syn, []),
    timer:sleep(1000),
    %% start processes
    Pid0 = syn_test_suite_helper:start_process(),
    Pid1 = syn_test_suite_helper:start_process(SlaveNode),
    %% register
    ok = syn:register(ConflictingName, Pid0, node()),
    %% trigger conflict resolution on master node with something less recent (which would be discarded without a custom handler)
    ok = syn_registry:sync_register(node(), ConflictingName, Pid1, keep_this_one, erlang:system_time() - 1000000000, false),
    timer:sleep(1000),
    %% check metadata, resolution happens on master node
    {Pid1, keep_this_one} = syn:whereis(ConflictingName, with_meta),
    %% check that other processes are not alive because syn killed them
    true = is_process_alive(Pid0),
    true = rpc:call(SlaveNode, erlang, is_process_alive, [Pid1]),
    %% check that discarded process is not monitored
    {monitored_by, []} = erlang:process_info(Pid0, monitored_by).

two_nodes_registration_race_condition_conflict_resolution_keep_local_with_custom_handler(Config) ->
    ConflictingName = "COMMON",
    %% get slaves
    SlaveNode = proplists:get_value(slave_node, Config),
    %% use customer handler
    syn_test_suite_helper:use_custom_handler(),
    rpc:call(SlaveNode, syn_test_suite_helper, use_custom_handler, []),
    %% start syn on nodes
    ok = syn_test_suite_helper:start_syn(),
    ok = rpc:call(SlaveNode, syn_test_suite_helper, start_syn, []),
    timer:sleep(1000),
    %% start processes
    Pid0 = syn_test_suite_helper:start_process(),
    Pid1 = syn_test_suite_helper:start_process(SlaveNode),
    %% inject into syn to simulate concurrent registration with something more recent (which would be picked without a custom handler)
    ok = syn_registry:add_to_local_table(ConflictingName, Pid0, keep_this_one, undefined, erlang:system_time() + 1000000000),
    %% register on slave node to trigger conflict resolution on master node
    ok = rpc:call(SlaveNode, syn, register, [ConflictingName, Pid1, SlaveNode]),
    timer:sleep(1000),
    %% check metadata, resolution happens on master node
    {Pid0, keep_this_one} = syn:whereis(ConflictingName, with_meta),
    {Pid0, keep_this_one} = rpc:call(SlaveNode, syn, whereis, [ConflictingName, with_meta]),
    %% check that other processes are not alive because syn killed them
    true = is_process_alive(Pid0),
    true = rpc:call(SlaveNode, erlang, is_process_alive, [Pid1]),
    %% check that discarded process is not monitored
    {monitored_by, []} = rpc:call(SlaveNode, erlang, process_info, [Pid1, monitored_by]).

two_nodes_registration_race_condition_conflict_resolution_when_process_died(Config) ->
    ConflictingName = "COMMON",
    %% get slaves
    SlaveNode = proplists:get_value(slave_node, Config),
    %% use customer handler
    syn_test_suite_helper:use_custom_handler(),
    rpc:call(SlaveNode, syn_test_suite_helper, use_custom_handler, []),
    %% start syn on nodes
    ok = syn_test_suite_helper:start_syn(),
    ok = rpc:call(SlaveNode, syn_test_suite_helper, start_syn, []),
    timer:sleep(1000),
    %% start processes
    Pid0 = syn_test_suite_helper:start_process(),
    Pid1 = syn_test_suite_helper:start_process(SlaveNode),
    %% inject into syn to simulate concurrent registration
    syn_registry:add_to_local_table(ConflictingName, Pid0, keep_this_one, 0, undefined),
    timer:sleep(250),
    %% kill process
    syn_test_suite_helper:kill_process(Pid0),
    %% register to trigger conflict resolution
    timer:sleep(250),
    ok = rpc:call(SlaveNode, syn, register, [ConflictingName, Pid1, SlaveNode]),
    timer:sleep(250),
    %% check
    {Pid1, SlaveNode} = syn:whereis(ConflictingName, with_meta),
    {Pid1, SlaveNode} = rpc:call(SlaveNode, syn, whereis, [ConflictingName, with_meta]),
    %% check that process is alive
    true = rpc:call(SlaveNode, erlang, is_process_alive, [Pid1]).

two_nodes_registry_full_cluster_sync_on_boot_node_added_later(_Config) ->
    %% stop slave
    syn_test_suite_helper:stop_slave(syn_slave),
    %% start syn on local node
    ok = syn_test_suite_helper:start_syn(),
    %% start process
    Pid = syn_test_suite_helper:start_process(),
    %% register
    ok = syn:register(<<"proc">>, Pid),
    %% start remote node and syn
    {ok, SlaveNode} = syn_test_suite_helper:start_slave(syn_slave),
    ok = rpc:call(SlaveNode, syn_test_suite_helper, start_syn, []),
    timer:sleep(1000),
    %% check
    Pid = syn:whereis(<<"proc">>),
    Pid = rpc:call(SlaveNode, syn, whereis, [<<"proc">>]).

two_nodes_registry_full_cluster_sync_on_boot_syn_started_later(Config) ->
    %% get slaves
    SlaveNode = proplists:get_value(slave_node, Config),
    %% start syn on local node
    ok = syn_test_suite_helper:start_syn(),
    %% start process
    Pid = syn_test_suite_helper:start_process(),
    %% register
    ok = syn:register(<<"proc">>, Pid),
    %% start ib remote syn
    ok = rpc:call(SlaveNode, syn_test_suite_helper, start_syn, []),
    timer:sleep(500),
    %% check
    Pid = syn:whereis(<<"proc">>),
    Pid = rpc:call(SlaveNode, syn, whereis, [<<"proc">>]).

two_nodes_unregister_and_register(Config) ->
    Name = "common name",
    %% get slave
    SlaveNode = proplists:get_value(slave_node, Config),
    %% use custom handler
    syn_test_suite_helper:use_custom_handler(),
    rpc:call(SlaveNode, syn_test_suite_helper, use_custom_handler, []),
    %% start
    ok = syn_test_suite_helper:start_syn(),
    ok = rpc:call(SlaveNode, syn_test_suite_helper, start_syn, []),
    timer:sleep(100),
    %% start processes
    PidLocal = syn_test_suite_helper:start_process(),
    PidLocal2 = syn_test_suite_helper:start_process(),
    PidRemote = syn_test_suite_helper:start_process(SlaveNode),
    %% register
    ok = rpc:call(SlaveNode, syn, register, [Name, PidRemote, SlaveNode]),
    timer:sleep(250),
    {PidRemote, SlaveNode} = syn:whereis(Name, with_meta),
    {PidRemote, SlaveNode} = rpc:call(SlaveNode, syn, whereis, [Name, with_meta]),
    %% un/register local over remote
    Node = node(),
    ok = syn:unregister_and_register(Name, PidLocal, Node),
    timer:sleep(1000),
    {PidLocal, Node} = syn:whereis(Name, with_meta),
    {PidLocal, Node} = rpc:call(SlaveNode, syn, whereis, [Name, with_meta]),
    ok = rpc:call(SlaveNode, syn, unregister_and_register, [Name, PidRemote, {SlaveNode, 2}]),
    timer:sleep(1000),
    {PidRemote, {SlaveNode, 2}} = syn:whereis(Name, with_meta),
    {PidRemote, {SlaveNode, 2}} = rpc:call(SlaveNode, syn, whereis, [Name, with_meta]),
    %% check that overwritten process is not monitored
    {monitored_by, []} = erlang:process_info(PidLocal, monitored_by),
    %% register local
    ok = syn:unregister_and_register(Name, PidLocal, Node),
    %% check a monitor exists
    {monitored_by, [_MonitoringPid]} = erlang:process_info(PidLocal, monitored_by),
    %% un/register local over local
    ok = syn:unregister_and_register(Name, PidLocal2, {Node, 2}),
    timer:sleep(1000),
    {PidLocal2, {Node, 2}} = syn:whereis(Name, with_meta),
    {PidLocal2, {Node, 2}} = rpc:call(SlaveNode, syn, whereis, [Name, with_meta]),
    %% check that overwritten process is not monitored
    {monitored_by, []} = erlang:process_info(PidLocal, monitored_by).

three_nodes_partial_netsplit_consistency(Config) ->
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
    timer:sleep(100),
    %% retrieve
    undefined = syn:whereis(<<"proc0">>),
    undefined = syn:whereis(<<"proc0-changed">>),
    undefined = syn:whereis(<<"proc1">>),
    undefined = syn:whereis(<<"proc2">>),
    undefined = rpc:call(SlaveNode1, syn, whereis, [<<"proc0">>]),
    undefined = rpc:call(SlaveNode1, syn, whereis, [<<"proc0-changed">>]),
    undefined = rpc:call(SlaveNode1, syn, whereis, [<<"proc1">>]),
    undefined = rpc:call(SlaveNode1, syn, whereis, [<<"proc2">>]),
    undefined = rpc:call(SlaveNode2, syn, whereis, [<<"proc0">>]),
    undefined = rpc:call(SlaveNode2, syn, whereis, [<<"proc0-changed">>]),
    undefined = rpc:call(SlaveNode2, syn, whereis, [<<"proc1">>]),
    undefined = rpc:call(SlaveNode2, syn, whereis, [<<"proc2">>]),
    %% register (mix nodes)
    ok = rpc:call(SlaveNode2, syn, register, [<<"proc0">>, Pid0]),
    ok = syn:register(<<"proc1">>, Pid1),
    ok = rpc:call(SlaveNode1, syn, register, [<<"proc2">>, Pid2]),
    ok = rpc:call(SlaveNode1, syn, register, [<<"proc0-changed">>, Pid0Changed]),
    timer:sleep(200),
    %% retrieve
    Pid0 = syn:whereis(<<"proc0">>),
    Pid0Changed = syn:whereis(<<"proc0-changed">>),
    Pid1 = syn:whereis(<<"proc1">>),
    Pid2 = syn:whereis(<<"proc2">>),
    Pid0 = rpc:call(SlaveNode1, syn, whereis, [<<"proc0">>]),
    Pid0Changed = rpc:call(SlaveNode1, syn, whereis, [<<"proc0-changed">>]),
    Pid1 = rpc:call(SlaveNode1, syn, whereis, [<<"proc1">>]),
    Pid2 = rpc:call(SlaveNode1, syn, whereis, [<<"proc2">>]),
    Pid0 = rpc:call(SlaveNode2, syn, whereis, [<<"proc0">>]),
    Pid0Changed = rpc:call(SlaveNode2, syn, whereis, [<<"proc0-changed">>]),
    Pid1 = rpc:call(SlaveNode2, syn, whereis, [<<"proc1">>]),
    Pid2 = rpc:call(SlaveNode2, syn, whereis, [<<"proc2">>]),
    %% disconnect slave 2 from main (slave 1 can still see slave 2)
    syn_test_suite_helper:disconnect_node(SlaveNode2),
    timer:sleep(1000),
    %% retrieve
    Pid0 = syn:whereis(<<"proc0">>),
    Pid0Changed = syn:whereis(<<"proc0-changed">>),
    Pid1 = syn:whereis(<<"proc1">>),
    undefined = syn:whereis(<<"proc2">>), %% main has lost slave 2 so 'proc2' is removed
    Pid0 = rpc:call(SlaveNode1, syn, whereis, [<<"proc0">>]),
    Pid0Changed = rpc:call(SlaveNode1, syn, whereis, [<<"proc0-changed">>]),
    Pid1 = rpc:call(SlaveNode1, syn, whereis, [<<"proc1">>]),
    Pid2 = rpc:call(SlaveNode1, syn, whereis, [<<"proc2">>]), %% slave 1 still has slave 2 so 'proc2' is still there
    %% disconnect slave 1
    syn_test_suite_helper:disconnect_node(SlaveNode1),
    timer:sleep(500),
    %% unregister proc0-changed
    ok = syn:unregister(<<"proc0-changed">>),
    %% retrieve
    Pid0 = syn:whereis(<<"proc0">>),
    undefined = syn:whereis(<<"proc0-changed">>),
    undefined = syn:whereis(<<"proc1">>),
    undefined = syn:whereis(<<"proc2">>),
    %% reconnect all
    syn_test_suite_helper:connect_node(SlaveNode1),
    syn_test_suite_helper:connect_node(SlaveNode2),
    timer:sleep(5000),
    %% retrieve
    Pid0 = syn:whereis(<<"proc0">>),
    undefined = syn:whereis(<<"proc0-changed">>),
    Pid1 = syn:whereis(<<"proc1">>),
    Pid2 = syn:whereis(<<"proc2">>),
    Pid0 = rpc:call(SlaveNode1, syn, whereis, [<<"proc0">>]),
    undefined = rpc:call(SlaveNode1, syn, whereis, [<<"proc0-changed">>]),
    Pid1 = rpc:call(SlaveNode1, syn, whereis, [<<"proc1">>]),
    Pid2 = rpc:call(SlaveNode1, syn, whereis, [<<"proc2">>]),
    Pid0 = rpc:call(SlaveNode2, syn, whereis, [<<"proc0">>]),
    undefined = rpc:call(SlaveNode2, syn, whereis, [<<"proc0-changed">>]),
    Pid1 = rpc:call(SlaveNode2, syn, whereis, [<<"proc1">>]),
    Pid2 = rpc:call(SlaveNode2, syn, whereis, [<<"proc2">>]).

three_nodes_full_netsplit_consistency(Config) ->
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
    timer:sleep(100),
    %% retrieve
    undefined = syn:whereis(<<"proc0">>),
    undefined = syn:whereis(<<"proc0-changed">>),
    undefined = syn:whereis(<<"proc1">>),
    undefined = syn:whereis(<<"proc2">>),
    undefined = rpc:call(SlaveNode1, syn, whereis, [<<"proc0">>]),
    undefined = rpc:call(SlaveNode1, syn, whereis, [<<"proc0-changed">>]),
    undefined = rpc:call(SlaveNode1, syn, whereis, [<<"proc1">>]),
    undefined = rpc:call(SlaveNode1, syn, whereis, [<<"proc2">>]),
    undefined = rpc:call(SlaveNode2, syn, whereis, [<<"proc0">>]),
    undefined = rpc:call(SlaveNode2, syn, whereis, [<<"proc0-changed">>]),
    undefined = rpc:call(SlaveNode2, syn, whereis, [<<"proc1">>]),
    undefined = rpc:call(SlaveNode2, syn, whereis, [<<"proc2">>]),
    %% register (mix nodes)
    ok = rpc:call(SlaveNode2, syn, register, [<<"proc0">>, Pid0]),
    ok = rpc:call(SlaveNode2, syn, register, [<<"proc0-changed">>, Pid0Changed]),
    ok = syn:register(<<"proc1">>, Pid1),
    ok = rpc:call(SlaveNode1, syn, register, [<<"proc2">>, Pid2]),
    timer:sleep(200),
    %% retrieve
    Pid0 = syn:whereis(<<"proc0">>),
    Pid0Changed = syn:whereis(<<"proc0-changed">>),
    Pid1 = syn:whereis(<<"proc1">>),
    Pid2 = syn:whereis(<<"proc2">>),
    Pid0 = rpc:call(SlaveNode1, syn, whereis, [<<"proc0">>]),
    Pid0Changed = rpc:call(SlaveNode1, syn, whereis, [<<"proc0-changed">>]),
    Pid1 = rpc:call(SlaveNode1, syn, whereis, [<<"proc1">>]),
    Pid2 = rpc:call(SlaveNode1, syn, whereis, [<<"proc2">>]),
    Pid0 = rpc:call(SlaveNode2, syn, whereis, [<<"proc0">>]),
    Pid0Changed = rpc:call(SlaveNode2, syn, whereis, [<<"proc0-changed">>]),
    Pid1 = rpc:call(SlaveNode2, syn, whereis, [<<"proc1">>]),
    Pid2 = rpc:call(SlaveNode2, syn, whereis, [<<"proc2">>]),
    %% disconnect slave 2 from main (slave 1 can still see slave 2)
    syn_test_suite_helper:disconnect_node(SlaveNode2),
    timer:sleep(1000),
    %% retrieve
    Pid0 = syn:whereis(<<"proc0">>),
    Pid0Changed = syn:whereis(<<"proc0-changed">>),
    Pid1 = syn:whereis(<<"proc1">>),
    undefined = syn:whereis(<<"proc2">>), %% main has lost slave 2 so 'proc2' is removed
    Pid0 = rpc:call(SlaveNode1, syn, whereis, [<<"proc0">>]),
    Pid0Changed = rpc:call(SlaveNode1, syn, whereis, [<<"proc0-changed">>]),
    Pid1 = rpc:call(SlaveNode1, syn, whereis, [<<"proc1">>]),
    Pid2 = rpc:call(SlaveNode1, syn, whereis, [<<"proc2">>]), %% slave 1 still has slave 2 so 'proc2' is still there
    %% disconnect slave 2 from slave 1
    rpc:call(SlaveNode1, syn_test_suite_helper, disconnect_node, [SlaveNode2]),
    timer:sleep(500),
    %% retrieve
    Pid0 = syn:whereis(<<"proc0">>),
    Pid0Changed = syn:whereis(<<"proc0-changed">>),
    Pid1 = syn:whereis(<<"proc1">>),
    undefined = syn:whereis(<<"proc2">>), %% main has lost slave 2 so 'proc2' is removed
    undefined = syn:whereis(<<"proc2">>, with_meta),
    Pid0 = rpc:call(SlaveNode1, syn, whereis, [<<"proc0">>]),
    Pid0Changed = rpc:call(SlaveNode1, syn, whereis, [<<"proc0-changed">>]),
    Pid1 = rpc:call(SlaveNode1, syn, whereis, [<<"proc1">>]),
    undefined = rpc:call(SlaveNode1, syn, whereis, [<<"proc2">>]),
    %% disconnect slave 1
    syn_test_suite_helper:disconnect_node(SlaveNode1),
    timer:sleep(500),
    %% unregister
    ok = syn:unregister(<<"proc0-changed">>),
    %% retrieve
    Pid0 = syn:whereis(<<"proc0">>),
    undefined = syn:whereis(<<"proc0-changed">>),
    undefined = syn:whereis(<<"proc1">>),
    undefined = syn:whereis(<<"proc2">>),
    %% reconnect all
    syn_test_suite_helper:connect_node(SlaveNode1),
    syn_test_suite_helper:connect_node(SlaveNode2),
    rpc:call(SlaveNode1, syn_test_suite_helper, connect_node, [SlaveNode2]),
    timer:sleep(1500),
    %% retrieve
    Pid0 = syn:whereis(<<"proc0">>),
    undefined = syn:whereis(<<"proc0-changed">>),
    Pid1 = syn:whereis(<<"proc1">>),
    Pid2 = syn:whereis(<<"proc2">>),
    Pid0 = rpc:call(SlaveNode1, syn, whereis, [<<"proc0">>]),
    undefined = rpc:call(SlaveNode1, syn, whereis, [<<"proc0-changed">>]),
    Pid1 = rpc:call(SlaveNode1, syn, whereis, [<<"proc1">>]),
    Pid2 = rpc:call(SlaveNode1, syn, whereis, [<<"proc2">>]),
    Pid0 = rpc:call(SlaveNode2, syn, whereis, [<<"proc0">>]),
    undefined = rpc:call(SlaveNode2, syn, whereis, [<<"proc0-changed">>]),
    Pid1 = rpc:call(SlaveNode2, syn, whereis, [<<"proc1">>]),
    Pid2 = rpc:call(SlaveNode2, syn, whereis, [<<"proc2">>]).

three_nodes_start_syn_before_connecting_cluster_with_conflict_keep_more_recent(Config) ->
    ConflictingName = "COMMON",
    %% get slaves
    SlaveNode1 = proplists:get_value(slave_node_1, Config),
    SlaveNode2 = proplists:get_value(slave_node_2, Config),
    %% start processes
    Pid0 = syn_test_suite_helper:start_process(),
    Pid1 = syn_test_suite_helper:start_process(SlaveNode1),
    Pid2 = syn_test_suite_helper:start_process(SlaveNode2),
    %% start delayed
    start_syn_delayed_and_register_local_process(ConflictingName, Pid0, 2000),
    timer:sleep(250),
    rpc:cast(SlaveNode1, ?MODULE, start_syn_delayed_and_register_local_process, [ConflictingName, Pid1, 2000]),
    timer:sleep(250),
    rpc:cast(SlaveNode2, ?MODULE, start_syn_delayed_and_register_local_process, [ConflictingName, Pid2, 2000]),
    timer:sleep(1000),
    %% disconnect all
    rpc:call(SlaveNode1, syn_test_suite_helper, disconnect_node, [SlaveNode2]),
    syn_test_suite_helper:disconnect_node(SlaveNode1),
    syn_test_suite_helper:disconnect_node(SlaveNode2),
    timer:sleep(3000),
    [] = nodes(),
    %% reconnect all
    syn_test_suite_helper:connect_node(SlaveNode1),
    syn_test_suite_helper:connect_node(SlaveNode2),
    rpc:call(SlaveNode1, syn_test_suite_helper, connect_node, [SlaveNode2]),
    timer:sleep(2500),
    %% count
    1 = syn:registry_count(),
    1 = rpc:call(SlaveNode1, syn, registry_count, []),
    1 = rpc:call(SlaveNode2, syn, registry_count, []),
    %% retrieve
    true = lists:member(syn:whereis(ConflictingName), [Pid0, Pid1, Pid2]),
    true = lists:member(rpc:call(SlaveNode1, syn, whereis, [ConflictingName]), [Pid0, Pid1, Pid2]),
    true = lists:member(rpc:call(SlaveNode2, syn, whereis, [ConflictingName]), [Pid0, Pid1, Pid2]),
    %% check metadata
    {Pid2, SlaveNode2} = syn:whereis(ConflictingName, with_meta),
    {Pid2, SlaveNode2} = rpc:call(SlaveNode1, syn, whereis, [ConflictingName, with_meta]),
    {Pid2, SlaveNode2} = rpc:call(SlaveNode2, syn, whereis, [ConflictingName, with_meta]),
    %% check that other processes are not alive because syn killed them
    false = is_process_alive(Pid0),
    false = rpc:call(SlaveNode1, erlang, is_process_alive, [Pid1]),
    true = rpc:call(SlaveNode2, erlang, is_process_alive, [Pid2]).

three_nodes_start_syn_before_connecting_cluster_with_custom_conflict_resolution_keep_remote(Config) ->
    ConflictingName = "COMMON",
    %% get slaves
    SlaveNode1 = proplists:get_value(slave_node_1, Config),
    SlaveNode2 = proplists:get_value(slave_node_2, Config),
    %% start processes
    Pid0 = syn_test_suite_helper:start_process(),
    Pid1 = syn_test_suite_helper:start_process(SlaveNode1),
    Pid2 = syn_test_suite_helper:start_process(SlaveNode2),
    %% start delayed
    start_syn_delayed_with_custom_handler_register_local_process(ConflictingName, Pid0, {node, node()}, 1500),
    rpc:cast(
        SlaveNode1,
        ?MODULE,
        start_syn_delayed_with_custom_handler_register_local_process,
        [ConflictingName, Pid1, keep_this_one, 1500])
    ,
    rpc:cast(
        SlaveNode2,
        ?MODULE,
        start_syn_delayed_with_custom_handler_register_local_process,
        [ConflictingName, Pid2, {node, SlaveNode2}, 1500]
    ),
    timer:sleep(500),
    %% disconnect all
    rpc:call(SlaveNode1, syn_test_suite_helper, disconnect_node, [SlaveNode2]),
    syn_test_suite_helper:disconnect_node(SlaveNode1),
    syn_test_suite_helper:disconnect_node(SlaveNode2),
    timer:sleep(1500),
    [] = nodes(),
    %% reconnect all
    syn_test_suite_helper:connect_node(SlaveNode1),
    syn_test_suite_helper:connect_node(SlaveNode2),
    rpc:call(SlaveNode1, syn_test_suite_helper, connect_node, [SlaveNode2]),
    timer:sleep(5000),
    %% count
    1 = syn:registry_count(),
    1 = rpc:call(SlaveNode1, syn, registry_count, []),
    1 = rpc:call(SlaveNode2, syn, registry_count, []),
    %% retrieve
    true = lists:member(syn:whereis(ConflictingName), [Pid0, Pid1, Pid2]),
    true = lists:member(rpc:call(SlaveNode1, syn, whereis, [ConflictingName]), [Pid0, Pid1, Pid2]),
    true = lists:member(rpc:call(SlaveNode2, syn, whereis, [ConflictingName]), [Pid0, Pid1, Pid2]),
    %% check metadata that we kept the correct process on all nodes
    {Pid1, keep_this_one} = syn:whereis(ConflictingName, with_meta),
    {Pid1, keep_this_one} = rpc:call(SlaveNode1, syn, whereis, [ConflictingName, with_meta]),
    {Pid1, keep_this_one} = rpc:call(SlaveNode1, syn, whereis, [ConflictingName, with_meta]),
    %% check that other processes are still alive because we didn't kill them
    true = is_process_alive(Pid0),
    true = rpc:call(SlaveNode1, erlang, is_process_alive, [Pid1]),
    true = rpc:call(SlaveNode2, erlang, is_process_alive, [Pid2]),
    %% check that discarded processes are not monitored
    {monitored_by, []} = erlang:process_info(Pid0, monitored_by),
    {monitored_by, []} = rpc:call(SlaveNode2, erlang, process_info, [Pid2, monitored_by]).

three_nodes_registration_race_condition_custom_conflict_resolution(Config) ->
    ConflictingName = "COMMON",
    %% get slaves
    SlaveNode1 = proplists:get_value(slave_node_1, Config),
    SlaveNode2 = proplists:get_value(slave_node_2, Config),
    %% use customer handler
    syn_test_suite_helper:use_custom_handler(),
    rpc:call(SlaveNode1, syn_test_suite_helper, use_custom_handler, []),
    rpc:call(SlaveNode2, syn_test_suite_helper, use_custom_handler, []),
    %% start syn on nodes
    ok = syn_test_suite_helper:start_syn(),
    ok = rpc:call(SlaveNode1, syn_test_suite_helper, start_syn, []),
    ok = rpc:call(SlaveNode2, syn_test_suite_helper, start_syn, []),
    timer:sleep(500),
    %% start processes
    Pid0 = syn_test_suite_helper:start_process(),
    Pid1 = syn_test_suite_helper:start_process(SlaveNode1),
    Pid2 = syn_test_suite_helper:start_process(SlaveNode2),
    %% inject into syn to simulate concurrent registration with something less recent (which would be discarded without a custom handler)
    ok = rpc:call(SlaveNode1, syn_registry, add_to_local_table, [ConflictingName, Pid1, keep_this_one, erlang:system_time() - 1000000000, undefined]),
    %% register on master node to trigger conflict resolution
    ok = syn:register(ConflictingName, Pid0, node()),
    timer:sleep(1000),
    %% retrieve
    true = lists:member(syn:whereis(ConflictingName), [Pid0, Pid1, Pid2]),
    true = lists:member(rpc:call(SlaveNode1, syn, whereis, [ConflictingName]), [Pid0, Pid1, Pid2]),
    true = lists:member(rpc:call(SlaveNode2, syn, whereis, [ConflictingName]), [Pid0, Pid1, Pid2]),
    %% check metadata that we kept the correct process on all nodes
    {Pid1, keep_this_one} = syn:whereis(ConflictingName, with_meta),
    {Pid1, keep_this_one} = rpc:call(SlaveNode1, syn, whereis, [ConflictingName, with_meta]),
    {Pid1, keep_this_one} = rpc:call(SlaveNode1, syn, whereis, [ConflictingName, with_meta]),
    %% check that other processes are still alive because we didn't kill them
    true = is_process_alive(Pid0),
    true = rpc:call(SlaveNode1, erlang, is_process_alive, [Pid1]),
    true = rpc:call(SlaveNode2, erlang, is_process_alive, [Pid2]).

three_nodes_anti_entropy(Config) ->
    %% get slaves
    SlaveNode1 = proplists:get_value(slave_node_1, Config),
    SlaveNode2 = proplists:get_value(slave_node_2, Config),
    %% use customer handler
    syn_test_suite_helper:use_custom_handler(),
    rpc:call(SlaveNode1, syn_test_suite_helper, use_custom_handler, []),
    rpc:call(SlaveNode2, syn_test_suite_helper, use_custom_handler, []),
    %% set anti-entropy with a very low interval (0.25 second)
    syn_test_suite_helper:use_anti_entropy(registry, 0.25),
    rpc:call(SlaveNode1, syn_test_suite_helper, use_anti_entropy, [registry, 0.25]),
    rpc:call(SlaveNode2, syn_test_suite_helper, use_anti_entropy, [registry, 0.25]),
    %% start syn on nodes
    ok = syn_test_suite_helper:start_syn(),
    ok = rpc:call(SlaveNode1, syn_test_suite_helper, start_syn, []),
    ok = rpc:call(SlaveNode2, syn_test_suite_helper, start_syn, []),
    timer:sleep(100),
    %% start processes
    Pid0 = syn_test_suite_helper:start_process(),
    Pid1 = syn_test_suite_helper:start_process(SlaveNode1),
    Pid2 = syn_test_suite_helper:start_process(SlaveNode2),
    Pid0Conflict = syn_test_suite_helper:start_process(),
    Pid1Conflict = syn_test_suite_helper:start_process(SlaveNode1),
    Pid2Conflict = syn_test_suite_helper:start_process(SlaveNode2),
    timer:sleep(100),
    %% inject data to simulate latent conflicts
    ok = syn_registry:add_to_local_table("pid0", Pid0, node(), 0, undefined),
    ok = rpc:call(SlaveNode1, syn_registry, add_to_local_table, ["pid1", Pid1, SlaveNode1, 0, undefined]),
    ok = rpc:call(SlaveNode2, syn_registry, add_to_local_table, ["pid2", Pid2, SlaveNode2, 0, undefined]),
    ok = syn_registry:add_to_local_table("conflict", Pid0Conflict, node(), erlang:system_time() + 1000000000, undefined),
    ok = rpc:call(SlaveNode1, syn_registry, add_to_local_table, ["conflict", Pid1Conflict, keep_this_one, erlang:system_time(), undefined]),
    ok = rpc:call(SlaveNode2, syn_registry, add_to_local_table, ["conflict", Pid2Conflict, SlaveNode2, erlang:system_time() + 1000000000, undefined]),
    %% wait to let anti-entropy settle
    timer:sleep(5000),
    %% check
    Node = node(),
    {Pid0, Node} = syn:whereis("pid0", with_meta),
    {Pid1, SlaveNode1} = syn:whereis("pid1", with_meta),
    {Pid2, SlaveNode2} = syn:whereis("pid2", with_meta),
    {Pid1Conflict, keep_this_one} = syn:whereis("conflict", with_meta),
    {Pid0, Node} = rpc:call(SlaveNode1, syn, whereis, ["pid0", with_meta]),
    {Pid1, SlaveNode1} = rpc:call(SlaveNode1, syn, whereis, ["pid1", with_meta]),
    {Pid2, SlaveNode2} = rpc:call(SlaveNode1, syn, whereis, ["pid2", with_meta]),
    {Pid1Conflict, keep_this_one} = rpc:call(SlaveNode1, syn, whereis, ["conflict", with_meta]),
    {Pid0, Node} = rpc:call(SlaveNode2, syn, whereis, ["pid0", with_meta]),
    {Pid1, SlaveNode1} = rpc:call(SlaveNode2, syn, whereis, ["pid1", with_meta]),
    {Pid2, SlaveNode2} = rpc:call(SlaveNode2, syn, whereis, ["pid2", with_meta]),
    {Pid1Conflict, keep_this_one} = rpc:call(SlaveNode2, syn, whereis, ["conflict", with_meta]).

three_nodes_anti_entropy_manual(Config) ->
    %% get slaves
    SlaveNode1 = proplists:get_value(slave_node_1, Config),
    SlaveNode2 = proplists:get_value(slave_node_2, Config),
    %% use customer handler
    syn_test_suite_helper:use_custom_handler(),
    rpc:call(SlaveNode1, syn_test_suite_helper, use_custom_handler, []),
    rpc:call(SlaveNode2, syn_test_suite_helper, use_custom_handler, []),
    %% start syn on nodes
    ok = syn_test_suite_helper:start_syn(),
    ok = rpc:call(SlaveNode1, syn_test_suite_helper, start_syn, []),
    ok = rpc:call(SlaveNode2, syn_test_suite_helper, start_syn, []),
    timer:sleep(100),
    %% start processes
    Pid0 = syn_test_suite_helper:start_process(),
    Pid1 = syn_test_suite_helper:start_process(SlaveNode1),
    Pid2 = syn_test_suite_helper:start_process(SlaveNode2),
    Pid0Conflict = syn_test_suite_helper:start_process(),
    Pid1Conflict = syn_test_suite_helper:start_process(SlaveNode1),
    Pid2Conflict = syn_test_suite_helper:start_process(SlaveNode2),
    timer:sleep(100),
    %% inject data to simulate latent conflicts
    ok = syn_registry:add_to_local_table("pid0", Pid0, node(), 0, undefined),
    ok = rpc:call(SlaveNode1, syn_registry, add_to_local_table, ["pid1", Pid1, SlaveNode1, 0, undefined]),
    ok = rpc:call(SlaveNode2, syn_registry, add_to_local_table, ["pid2", Pid2, SlaveNode2, 0, undefined]),
    ok = syn_registry:add_to_local_table("conflict", Pid0Conflict, node(), erlang:system_time() + 1000000000, undefined),
    ok = rpc:call(SlaveNode1, syn_registry, add_to_local_table, ["conflict", Pid1Conflict, keep_this_one, erlang:system_time(), undefined]),
    ok = rpc:call(SlaveNode2, syn_registry, add_to_local_table, ["conflict", Pid2Conflict, SlaveNode2, erlang:system_time() + 1000000000, undefined]),
    %% call anti entropy
    ok = syn:force_cluster_sync(registry),
    timer:sleep(1000),
    %% check
    Node = node(),
    {Pid0, Node} = syn:whereis("pid0", with_meta),
    {Pid1, SlaveNode1} = syn:whereis("pid1", with_meta),
    {Pid2, SlaveNode2} = syn:whereis("pid2", with_meta),
    {Pid1Conflict, keep_this_one} = syn:whereis("conflict", with_meta),
    {Pid0, Node} = rpc:call(SlaveNode1, syn, whereis, ["pid0", with_meta]),
    {Pid1, SlaveNode1} = rpc:call(SlaveNode1, syn, whereis, ["pid1", with_meta]),
    {Pid2, SlaveNode2} = rpc:call(SlaveNode1, syn, whereis, ["pid2", with_meta]),
    {Pid1Conflict, keep_this_one} = rpc:call(SlaveNode1, syn, whereis, ["conflict", with_meta]),
    {Pid0, Node} = rpc:call(SlaveNode2, syn, whereis, ["pid0", with_meta]),
    {Pid1, SlaveNode1} = rpc:call(SlaveNode2, syn, whereis, ["pid1", with_meta]),
    {Pid2, SlaveNode2} = rpc:call(SlaveNode2, syn, whereis, ["pid2", with_meta]),
    {Pid1Conflict, keep_this_one} = rpc:call(SlaveNode2, syn, whereis, ["conflict", with_meta]).

three_nodes_concurrent_registration_unregistration(Config) ->
    CommonName = "common-name",
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
    timer:sleep(100),
    %% register on 0
    ok = syn:register(CommonName, Pid0, node()),
    timer:sleep(250),
    %% check
    Node = node(),
    {Pid0, Node} = syn:whereis(CommonName, with_meta),
    {Pid0, Node} = rpc:call(SlaveNode1, syn, whereis, [CommonName, with_meta]),
    {Pid0, Node} = rpc:call(SlaveNode2, syn, whereis, [CommonName, with_meta]),
    %% simulate unregistration with inconsistent data
    syn_registry:sync_unregister(SlaveNode1, Pid1, CommonName),
    timer:sleep(250),
    %% check
    Node = node(),
    {Pid0, Node} = syn:whereis(CommonName, with_meta),
    {Pid0, Node} = rpc:call(SlaveNode1, syn, whereis, [CommonName, with_meta]),
    {Pid0, Node} = rpc:call(SlaveNode2, syn, whereis, [CommonName, with_meta]).

three_nodes_resolve_conflict_on_all_nodes(Config) ->
    CommonName = "common-name",
    %% get slaves
    SlaveNode1 = proplists:get_value(slave_node_1, Config),
    SlaveNode2 = proplists:get_value(slave_node_2, Config),
    %% start syn on nodes
    ok = syn_test_suite_helper:start_syn(),
    ok = rpc:call(SlaveNode1, syn_test_suite_helper, start_syn, []),
    ok = rpc:call(SlaveNode2, syn_test_suite_helper, start_syn, []),
    timer:sleep(100),
    %% start processes
    Pid1 = syn_test_suite_helper:start_process(SlaveNode1),
    Pid2 = syn_test_suite_helper:start_process(SlaveNode2),
    timer:sleep(100),
    %% register on slave 1
    ok = rpc:call(SlaveNode1, syn, register, [CommonName, Pid1, SlaveNode1]),
    timer:sleep(500),
    %% check
    {Pid1, SlaveNode1} = syn:whereis(CommonName, with_meta),
    {Pid1, SlaveNode1} = rpc:call(SlaveNode1, syn, whereis, [CommonName, with_meta]),
    {Pid1, SlaveNode1} = rpc:call(SlaveNode2, syn, whereis, [CommonName, with_meta]),
    %% force a sync registration conflict on master node from slave 2
    syn_registry:sync_register(node(), CommonName, Pid2, SlaveNode2, erlang:system_time() + 1000000000, false),
    timer:sleep(1000),
    %% check
    {Pid2, SlaveNode2} = syn:whereis(CommonName, with_meta),
    {Pid2, SlaveNode2} = rpc:call(SlaveNode1, syn, whereis, [CommonName, with_meta]).

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
        %%
        syn:start(),
        ok = syn:register(Name, Pid, node())
    end).

start_syn_delayed_with_custom_handler_register_local_process(Name, Pid, Meta, Ms) ->
    spawn(fun() ->
        lists:foreach(fun(Node) ->
            syn_test_suite_helper:disconnect_node(Node)
        end, nodes()),
        timer:sleep(Ms),
        [] = nodes(),
        %% use customer handler
        syn_test_suite_helper:use_custom_handler(),
        %%
        syn:start(),
        ok = syn:register(Name, Pid, Meta)
    end).

seq_unregister_register(Name, Pid, Meta) ->
    syn:unregister(Name),
    syn:register(Name, Pid, Meta).
