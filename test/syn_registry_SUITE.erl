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
    three_nodes_discover_default_scope/1
%%    three_nodes_register_unregister_and_monitor_default_scope/1
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
        {three_nodes_process_registration, [shuffle], [
            three_nodes_discover_default_scope
%%            three_nodes_register_unregister_and_monitor_default_scope
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
init_per_group(three_nodes_process_registration, Config) ->
    %% start slave
    {ok, SlaveNode1} = syn_test_suite_helper:start_slave(syn_slave_1),
    {ok, SlaveNode2} = syn_test_suite_helper:start_slave(syn_slave_2),
    %% wait full cluster
    case syn_test_suite_helper:wait_cluster_connected([node(), SlaveNode1, SlaveNode2]) of
        ok ->
            %% config
            [{slave_node_1, SlaveNode1}, {slave_node_2, SlaveNode2} | Config];

        Other ->
            ct:pal("*********** Could not get full cluster, skipping"),
            end_per_group(three_nodes_process_registration, Config),
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
three_nodes_discover_default_scope(Config) ->
    %% get slaves
    SlaveNode1 = proplists:get_value(slave_node_1, Config),
    SlaveNode2 = proplists:get_value(slave_node_2, Config),
    %% start syn on nodes
    ok = syn:start(),
    ok = rpc:call(SlaveNode1, syn, start, []),
    ok = rpc:call(SlaveNode2, syn, start, []),
    timer:sleep(100),

    %% check scope network
    NodesMap0_0 = syn_registry:get_nodes(default),
    Nodes0_0 = maps:keys(NodesMap0_0),
    2 = length(Nodes0_0),
    true = lists:member(SlaveNode1, Nodes0_0),
    true = lists:member(SlaveNode2, Nodes0_0),
    NodesMap0_1 = rpc:call(SlaveNode1, syn_registry, get_nodes, [default]),
    Nodes0_1 = maps:keys(NodesMap0_1),
    2 = length(Nodes0_1),
    true = lists:member(node(), Nodes0_1),
    true = lists:member(SlaveNode2, Nodes0_1),
    NodesMap0_2 = rpc:call(SlaveNode2, syn_registry, get_nodes, [default]),
    Nodes0_2 = maps:keys(NodesMap0_2),
    2 = length(Nodes0_2),
    true = lists:member(node(), Nodes0_2),
    true = lists:member(SlaveNode1, Nodes0_2),

    %% simulate full netsplit
    rpc:call(SlaveNode1, syn_test_suite_helper, disconnect_node, [SlaveNode2]),
    syn_test_suite_helper:disconnect_node(SlaveNode1),
    syn_test_suite_helper:disconnect_node(SlaveNode2),
    timer:sleep(100),

    %% check scope network
    NodesMap1_0 = syn_registry:get_nodes(default),
    Nodes1_0 = maps:keys(NodesMap1_0),
    0 = length(Nodes1_0),

    %% reconnect one node
    syn_test_suite_helper:connect_node(SlaveNode1),
    ok = syn_test_suite_helper:wait_cluster_connected([node(), SlaveNode1]),

    %% check scope network
    NodesMap2_0 = syn_registry:get_nodes(default),
    Nodes2_0 = maps:keys(NodesMap2_0),
    1 = length(Nodes2_0),
    true = lists:member(SlaveNode1, Nodes2_0),
    false = lists:member(SlaveNode2, Nodes2_0),
    NodesMap2_1 = rpc:call(SlaveNode1, syn_registry, get_nodes, [default]),
    Nodes2_1 = maps:keys(NodesMap2_1),
    1 = length(Nodes2_1),
    true = lists:member(node(), Nodes2_1),
    false = lists:member(SlaveNode2, Nodes2_1),

    %% reconnect all
    syn_test_suite_helper:connect_node(SlaveNode2),
    rpc:call(SlaveNode1, syn_test_suite_helper, connect_node, [SlaveNode2]),
    ok = syn_test_suite_helper:wait_cluster_connected([node(), SlaveNode1, SlaveNode2]),

    %% check scope network
    NodesMap3_0 = syn_registry:get_nodes(default),
    Nodes3_0 = maps:keys(NodesMap3_0),
    2 = length(Nodes3_0),
    true = lists:member(SlaveNode1, Nodes3_0),
    true = lists:member(SlaveNode2, Nodes3_0),
    NodesMap3_1 = rpc:call(SlaveNode1, syn_registry, get_nodes, [default]),
    Nodes3_1 = maps:keys(NodesMap3_1),
    2 = length(Nodes3_1),
    true = lists:member(node(), Nodes3_1),
    true = lists:member(SlaveNode2, Nodes3_1),
    NodesMap3_2 = rpc:call(SlaveNode2, syn_registry, get_nodes, [default]),
    Nodes3_2 = maps:keys(NodesMap3_2),
    2 = length(Nodes3_2),
    true = lists:member(node(), Nodes3_2),
    true = lists:member(SlaveNode1, Nodes3_2),

    %% crash the scope process on slave1
    rpc:call(SlaveNode1, syn_test_suite_helper, kill_process, [syn_registry_default]),
    timer:sleep(100),

    %% check scope network, it should have rebuilt after supervisor restarts it
    NodesMap3_0 = syn_registry:get_nodes(default),
    Nodes3_0 = maps:keys(NodesMap3_0),
    2 = length(Nodes3_0),
    true = lists:member(SlaveNode1, Nodes3_0),
    true = lists:member(SlaveNode2, Nodes3_0),
    NodesMap3_1 = rpc:call(SlaveNode1, syn_registry, get_nodes, [default]),
    Nodes3_1 = maps:keys(NodesMap3_1),
    2 = length(Nodes3_1),
    true = lists:member(node(), Nodes3_1),
    true = lists:member(SlaveNode2, Nodes3_1),
    NodesMap3_2 = rpc:call(SlaveNode2, syn_registry, get_nodes, [default]),
    Nodes3_2 = maps:keys(NodesMap3_2),
    2 = length(Nodes3_2),
    true = lists:member(node(), Nodes3_2),
    true = lists:member(SlaveNode1, Nodes3_2).

%%three_nodes_register_unregister_and_monitor_default_scope(Config) ->
%%    %% get slaves
%%    SlaveNode1 = proplists:get_value(slave_node_1, Config),
%%    SlaveNode2 = proplists:get_value(slave_node_2, Config),
%%    %% start syn on nodes
%%    ok = syn:start(),
%%    ok = rpc:call(SlaveNode1, syn, start, []),
%%    ok = rpc:call(SlaveNode2, syn, start, []),
%%    timer:sleep(50),
%%
%%    %% start processes
%%    Pid = syn_test_suite_helper:start_process(),
%%    PidWithMeta = syn_test_suite_helper:start_process(),
%%    PidRemote1 = syn_test_suite_helper:start_process(SlaveNode1),
%%
%%    %% retrieve
%%    undefined = syn:lookup(<<"my proc">>),
%%    undefined = rpc:call(SlaveNode1, syn, lookup, [<<"my proc">>]),
%%    undefined = rpc:call(SlaveNode2, syn, lookup, [<<"my proc">>]),
%%    undefined = syn:lookup({"my proc 2"}),
%%    undefined = rpc:call(SlaveNode1, syn, lookup, [{"my proc 2"}]),
%%    undefined = rpc:call(SlaveNode2, syn, lookup, [{"my proc 2"}]),
%%    undefined = syn:lookup(<<"my proc with meta">>),
%%    undefined = rpc:call(SlaveNode1, syn, lookup, [<<"my proc with meta">>]),
%%    undefined = rpc:call(SlaveNode2, syn, lookup, [<<"my proc with meta">>]),
%%    undefined = syn:lookup({remote_pid_on, slave_1}),
%%    undefined = rpc:call(SlaveNode1, syn, lookup, [{remote_pid_on, slave_1}]),
%%    undefined = rpc:call(SlaveNode2, syn, lookup, [{remote_pid_on, slave_1}]),
%%
%%    %% register
%%    ok = syn:register(<<"my proc">>, Pid),
%%    ok = syn:register({"my proc 2"}, Pid), %% same pid, different name
%%    ok = syn:register(<<"my proc with meta">>, PidWithMeta, {meta, <<"meta">>}), %% pid with meta
%%    ok = rpc:call(SlaveNode1, syn, register, [{remote_pid_on, slave_1}, PidRemote1]), %% remote on slave 1
%%    timer:sleep(100),
%%
%%    %% retrieve
%%    {Pid, undefined} = syn:lookup(<<"my proc">>),
%%    {Pid, undefined} = rpc:call(SlaveNode1, syn, lookup, [<<"my proc">>]),
%%    {Pid, undefined} = rpc:call(SlaveNode2, syn, lookup, [<<"my proc">>]),
%%    {Pid, undefined} = syn:lookup({"my proc 2"}),
%%    {Pid, undefined} = rpc:call(SlaveNode1, syn, lookup, [{"my proc 2"}]),
%%    {Pid, undefined} = rpc:call(SlaveNode2, syn, lookup, [{"my proc 2"}]),
%%    {PidWithMeta, {meta, <<"meta">>}} = syn:lookup(<<"my proc with meta">>),
%%    {PidWithMeta, {meta, <<"meta">>}} = rpc:call(SlaveNode1, syn, lookup, [<<"my proc with meta">>]),
%%    {PidWithMeta, {meta, <<"meta">>}} = rpc:call(SlaveNode2, syn, lookup, [<<"my proc with meta">>]),
%%    {PidRemote1, undefined} = syn:lookup({remote_pid_on, slave_1}),
%%    {PidRemote1, undefined} = rpc:call(SlaveNode1, syn, lookup, [{remote_pid_on, slave_1}]),
%%    {PidRemote1, undefined} = rpc:call(SlaveNode2, syn, lookup, [{remote_pid_on, slave_1}]),
%%
%%    %% re-register to edit meta
%%    ok = syn:register(<<"my proc with meta">>, PidWithMeta, {meta2, <<"meta2">>}),
%%    ok = rpc:call(SlaveNode2, syn, register, [{remote_pid_on, slave_1}, PidRemote1, added_meta]), %% updated on slave 2
%%    timer:sleep(50),
%%
%%    %% retrieve
%%    {PidWithMeta, {meta2, <<"meta2">>}} = syn:lookup(<<"my proc with meta">>),
%%    {PidWithMeta, {meta2, <<"meta2">>}} = rpc:call(SlaveNode1, syn, lookup, [<<"my proc with meta">>]),
%%    {PidWithMeta, {meta2, <<"meta2">>}} = rpc:call(SlaveNode2, syn, lookup, [<<"my proc with meta">>]),
%%    {PidRemote1, added_meta} = syn:lookup({remote_pid_on, slave_1}),
%%    {PidRemote1, added_meta} = rpc:call(SlaveNode1, syn, lookup, [{remote_pid_on, slave_1}]),
%%    {PidRemote1, added_meta} = rpc:call(SlaveNode2, syn, lookup, [{remote_pid_on, slave_1}]),
%%
%%    %% kill process
%%    syn_test_suite_helper:kill_process(Pid),
%%    syn_test_suite_helper:kill_process(PidRemote1),
%%    %% unregister process
%%    syn:unregister(<<"my proc with meta">>),
%%    timer:sleep(50),
%%
%%    %% retrieve
%%    undefined = syn:lookup(<<"my proc">>),
%%    undefined = rpc:call(SlaveNode1, syn, lookup, [<<"my proc">>]),
%%    undefined = rpc:call(SlaveNode2, syn, lookup, [<<"my proc">>]),
%%    undefined = syn:lookup({"my proc 2"}),
%%    undefined = rpc:call(SlaveNode1, syn, lookup, [{"my proc 2"}]),
%%    undefined = rpc:call(SlaveNode2, syn, lookup, [{"my proc 2"}]),
%%    undefined = syn:lookup(<<"my proc with meta">>),
%%    undefined = rpc:call(SlaveNode1, syn, lookup, [<<"my proc with meta">>]),
%%    undefined = rpc:call(SlaveNode2, syn, lookup, [<<"my proc with meta">>]),
%%    undefined = syn:lookup({remote_pid_on, slave_1}),
%%    undefined = rpc:call(SlaveNode1, syn, lookup, [{remote_pid_on, slave_1}]),
%%    undefined = rpc:call(SlaveNode2, syn, lookup, [{remote_pid_on, slave_1}]).
