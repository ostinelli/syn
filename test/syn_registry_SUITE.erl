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
-module(syn_registry_SUITE).

%% callbacks
-export([all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([groups/0, init_per_group/2, end_per_group/2]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% tests
-export([
    one_node_via_register_unregister/1
]).
-export([
    three_nodes_discover_default_scope/1,
    three_nodes_discover_custom_scope/1,
    three_nodes_register_unregister_and_monitor_default_scope/1,
    three_nodes_register_unregister_and_monitor_custom_scope/1,
    three_nodes_cluster_changes/1,
    three_nodes_cluster_conflicts/1,
    three_nodes_custom_event_handler_reg_unreg/1,
    three_nodes_custom_event_handler_conflict_resolution/1
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
        {group, one_node_process_registration},
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
        {one_node_process_registration, [shuffle], [
            one_node_via_register_unregister
        ]},
        {three_nodes_process_registration, [shuffle], [
            three_nodes_discover_default_scope,
            three_nodes_discover_custom_scope,
            three_nodes_register_unregister_and_monitor_default_scope,
            three_nodes_register_unregister_and_monitor_custom_scope,
            three_nodes_cluster_changes,
            three_nodes_cluster_conflicts,
            three_nodes_custom_event_handler_reg_unreg,
            three_nodes_custom_event_handler_conflict_resolution
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
one_node_via_register_unregister(_Config) ->
    %% start syn
    ok = syn:start(),

    %% ---> default scope
    %% start gen server via syn
    GenServerName = {default, <<"my proc">>},
    Tuple = {via, syn, GenServerName},
    {ok, Pid} = syn_test_gen_server:start_link(Tuple),
    %% retrieve
    {Pid, undefined} = syn:lookup(<<"my proc">>),
    %% call
    pong = syn_test_gen_server:ping(Tuple),
    %% send via syn
    syn:send(GenServerName, {self(), send_ping}),
    syn_test_suite_helper:assert_received_messages([
        reply_pong
    ]),
    %% stop server
    syn_test_gen_server:stop(Tuple),
    %% retrieve
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> syn:lookup(<<"my proc">>) end
    ),
    %% send via syn
    {badarg, {GenServerName, anything}} = catch syn:send(GenServerName, anything),

    %% ---> custom scope
    syn:add_node_to_scope(custom_scope),

    %% start gen server via syn
    GenServerNameCustom = {custom_scope, <<"my proc">>},
    TupleCustom = {via, syn, GenServerNameCustom},
    {ok, PidCustom} = syn_test_gen_server:start_link(TupleCustom),
    %% retrieve
    {PidCustom, undefined} = syn:lookup(custom_scope, <<"my proc">>),
    %% call
    pong = syn_test_gen_server:ping(TupleCustom),
    %% send via syn
    syn:send(GenServerNameCustom, {self(), send_ping}),
    syn_test_suite_helper:assert_received_messages([
        reply_pong
    ]),
    %% stop server
    syn_test_gen_server:stop(TupleCustom),
    %% retrieve
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> syn:lookup(custom_scope, <<"my proc">>) end
    ),
    %% send via syn
    {badarg, {GenServerNameCustom, anything}} = catch syn:send(GenServerNameCustom, anything).

three_nodes_discover_default_scope(Config) ->
    %% get slaves
    SlaveNode1 = proplists:get_value(slave_node_1, Config),
    SlaveNode2 = proplists:get_value(slave_node_2, Config),

    %% start syn on nodes
    ok = syn:start(),
    ok = rpc:call(SlaveNode1, syn, start, []),
    ok = rpc:call(SlaveNode2, syn, start, []),

    %% check
    syn_test_suite_helper:assert_registry_scope_subcluster(node(), default, [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode1, default, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode2, default, [node(), SlaveNode1]),

    %% simulate full netsplit
    rpc:call(SlaveNode1, syn_test_suite_helper, disconnect_node, [SlaveNode2]),
    syn_test_suite_helper:disconnect_node(SlaveNode1),
    syn_test_suite_helper:disconnect_node(SlaveNode2),
    syn_test_suite_helper:assert_cluster(node(), []),

    %% check
    syn_test_suite_helper:assert_registry_scope_subcluster(node(), default, []),

    %% reconnect slave 1
    syn_test_suite_helper:connect_node(SlaveNode1),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node()]),

    %% check
    syn_test_suite_helper:assert_registry_scope_subcluster(node(), default, [SlaveNode1]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode1, default, [node()]),

    %% reconnect all
    syn_test_suite_helper:connect_node(SlaveNode2),
    rpc:call(SlaveNode1, syn_test_suite_helper, connect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node(), SlaveNode1]),

    %% check
    syn_test_suite_helper:assert_registry_scope_subcluster(node(), default, [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode1, default, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode2, default, [node(), SlaveNode1]),

    %% simulate full netsplit, again
    rpc:call(SlaveNode1, syn_test_suite_helper, disconnect_node, [SlaveNode2]),
    syn_test_suite_helper:disconnect_node(SlaveNode1),
    syn_test_suite_helper:disconnect_node(SlaveNode2),
    syn_test_suite_helper:assert_cluster(node(), []),

    %% check
    syn_test_suite_helper:assert_registry_scope_subcluster(node(), default, []),
    %% reconnect all, again
    syn_test_suite_helper:connect_node(SlaveNode2),
    rpc:call(SlaveNode1, syn_test_suite_helper, connect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node(), SlaveNode1]),

    %% check
    syn_test_suite_helper:assert_registry_scope_subcluster(node(), default, [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode1, default, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode2, default, [node(), SlaveNode1]),

    %% crash the scope process on local
    syn_test_suite_helper:kill_process(syn_registry_default),
    syn_test_suite_helper:wait_process_name_ready(syn_registry_default),

    %% check, it should have rebuilt after supervisor restarts it
    syn_test_suite_helper:assert_registry_scope_subcluster(node(), default, [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode1, default, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode2, default, [node(), SlaveNode1]),

    %% crash scopes supervisor on local
    syn_test_suite_helper:kill_process(syn_scopes_sup),
    syn_test_suite_helper:wait_process_name_ready(syn_registry_default),

    %% check
    syn_test_suite_helper:assert_registry_scope_subcluster(node(), default, [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode1, default, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode2, default, [node(), SlaveNode1]).

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
    syn_test_suite_helper:assert_registry_scope_subcluster(node(), custom_scope_ab, [SlaveNode1]),
    syn_test_suite_helper:assert_registry_scope_subcluster(node(), custom_scope_all, [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode1, custom_scope_ab, [node()]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode1, custom_scope_bc, [SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode1, custom_scope_all, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode2, custom_scope_bc, [SlaveNode1]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode2, custom_scope_c, []),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode2, custom_scope_all, [node(), SlaveNode1]),

    %% check default
    syn_test_suite_helper:assert_registry_scope_subcluster(node(), default, [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode1, default, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode2, default, [node(), SlaveNode1]),

    %% disconnect node 2 (node 1 can still see node 2)
    syn_test_suite_helper:disconnect_node(SlaveNode2),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node(), SlaveNode2]),

    %% check
    syn_test_suite_helper:assert_registry_scope_subcluster(node(), custom_scope_ab, [SlaveNode1]),
    syn_test_suite_helper:assert_registry_scope_subcluster(node(), custom_scope_all, [SlaveNode1]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode1, custom_scope_ab, [node()]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode1, custom_scope_bc, [SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode1, custom_scope_all, [node(), SlaveNode2]),

    %% reconnect node 2
    syn_test_suite_helper:connect_node(SlaveNode2),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node(), SlaveNode1]),

    %% check
    syn_test_suite_helper:assert_registry_scope_subcluster(node(), custom_scope_ab, [SlaveNode1]),
    syn_test_suite_helper:assert_registry_scope_subcluster(node(), custom_scope_all, [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode1, custom_scope_ab, [node()]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode1, custom_scope_bc, [SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode1, custom_scope_all, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode2, custom_scope_bc, [SlaveNode1]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode2, custom_scope_c, []),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode2, custom_scope_all, [node(), SlaveNode1]),

    %% crash a scope process on 2
    rpc:call(SlaveNode2, syn_test_suite_helper, kill_process, [syn_registry_custom_scope_bc]),
    rpc:call(SlaveNode2, syn_test_suite_helper, wait_process_name_ready, [syn_registry_default]),

    %% check
    syn_test_suite_helper:assert_registry_scope_subcluster(node(), custom_scope_ab, [SlaveNode1]),
    syn_test_suite_helper:assert_registry_scope_subcluster(node(), custom_scope_all, [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode1, custom_scope_ab, [node()]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode1, custom_scope_bc, [SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode1, custom_scope_all, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode2, custom_scope_bc, [SlaveNode1]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode2, custom_scope_c, []),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode2, custom_scope_all, [node(), SlaveNode1]),

    %% crash scopes supervisor on local
    syn_test_suite_helper:kill_process(syn_scopes_sup),
    syn_test_suite_helper:wait_process_name_ready(syn_registry_default),

    %% check
    syn_test_suite_helper:assert_registry_scope_subcluster(node(), custom_scope_ab, [SlaveNode1]),
    syn_test_suite_helper:assert_registry_scope_subcluster(node(), custom_scope_all, [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode1, custom_scope_ab, [node()]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode1, custom_scope_bc, [SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode1, custom_scope_all, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode2, custom_scope_bc, [SlaveNode1]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode2, custom_scope_c, []),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode2, custom_scope_all, [node(), SlaveNode1]).

three_nodes_register_unregister_and_monitor_default_scope(Config) ->
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

    %% retrieve
    undefined = syn:lookup(<<"my proc">>),
    undefined = rpc:call(SlaveNode1, syn, lookup, [<<"my proc">>]),
    undefined = rpc:call(SlaveNode2, syn, lookup, [<<"my proc">>]),
    undefined = syn:lookup({"my proc alias"}),
    undefined = rpc:call(SlaveNode1, syn, lookup, [{"my proc alias"}]),
    undefined = rpc:call(SlaveNode2, syn, lookup, [{"my proc alias"}]),
    undefined = syn:lookup(<<"my proc with meta">>),
    undefined = rpc:call(SlaveNode1, syn, lookup, [<<"my proc with meta">>]),
    undefined = rpc:call(SlaveNode2, syn, lookup, [<<"my proc with meta">>]),
    undefined = syn:lookup({remote_pid_on, slave_1}),
    undefined = rpc:call(SlaveNode1, syn, lookup, [{remote_pid_on, slave_1}]),
    undefined = rpc:call(SlaveNode2, syn, lookup, [{remote_pid_on, slave_1}]),
    0 = syn:registry_count(),
    0 = syn:registry_count(default, node()),
    0 = syn:registry_count(default, SlaveNode1),
    0 = syn:registry_count(default, SlaveNode2),

    %% register
    ok = syn:register(<<"my proc">>, Pid),
    ok = syn:register({"my proc alias"}, Pid), %% same pid, different name
    ok = syn:register(<<"my proc with meta">>, PidWithMeta, {meta, <<"meta">>}), %% pid with meta
    ok = syn:register({remote_pid_on, slave_1}, PidRemoteOn1), %% remote on slave 1

    %% errors
    {error, taken} = syn:register(<<"my proc">>, PidRemoteOn1),
    {error, not_alive} = syn:register({"pid not alive"}, list_to_pid("<0.9999.0>")),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        {Pid, undefined},
        fun() -> syn:lookup(<<"my proc">>) end
    ),
    syn_test_suite_helper:assert_wait(
        {Pid, undefined},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [<<"my proc">>]) end
    ),
    syn_test_suite_helper:assert_wait(
        {Pid, undefined},
        fun() -> rpc:call(SlaveNode2, syn, lookup, [<<"my proc">>]) end
    ),
    syn_test_suite_helper:assert_wait(
        {Pid, undefined},
        fun() -> syn:lookup({"my proc alias"}) end
    ),
    syn_test_suite_helper:assert_wait(
        {Pid, undefined},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [{"my proc alias"}]) end
    ),
    syn_test_suite_helper:assert_wait(
        {Pid, undefined},
        fun() -> rpc:call(SlaveNode2, syn, lookup, [{"my proc alias"}]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidWithMeta, {meta, <<"meta">>}},
        fun() -> syn:lookup(<<"my proc with meta">>) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidWithMeta, {meta, <<"meta">>}},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [<<"my proc with meta">>]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidWithMeta, {meta, <<"meta">>}},
        fun() -> rpc:call(SlaveNode2, syn, lookup, [<<"my proc with meta">>]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, undefined},
        fun() -> syn:lookup({remote_pid_on, slave_1}) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, undefined},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [{remote_pid_on, slave_1}]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, undefined},
        fun() -> rpc:call(SlaveNode2, syn, lookup, [{remote_pid_on, slave_1}]) end
    ),
    4 = syn:registry_count(),
    3 = syn:registry_count(default, node()),
    1 = syn:registry_count(default, SlaveNode1),
    0 = syn:registry_count(default, SlaveNode2),

    %% re-register to edit meta
    ok = syn:register(<<"my proc with meta">>, PidWithMeta, {meta2, <<"meta2">>}),
    ok = rpc:call(SlaveNode2, syn, register, [{remote_pid_on, slave_1}, PidRemoteOn1, added_meta]), %% updated on slave 2

    %% retrieve
    syn_test_suite_helper:assert_wait(
        {PidWithMeta, {meta2, <<"meta2">>}},
        fun() -> syn:lookup(<<"my proc with meta">>) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidWithMeta, {meta2, <<"meta2">>}},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [<<"my proc with meta">>]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidWithMeta, {meta2, <<"meta2">>}},
        fun() -> rpc:call(SlaveNode2, syn, lookup, [<<"my proc with meta">>]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, added_meta},
        fun() -> syn:lookup({remote_pid_on, slave_1}) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, added_meta},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [{remote_pid_on, slave_1}]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, added_meta},
        fun() -> rpc:call(SlaveNode2, syn, lookup, [{remote_pid_on, slave_1}]) end
    ),
    4 = syn:registry_count(),
    3 = syn:registry_count(default, node()),
    1 = syn:registry_count(default, SlaveNode1),
    0 = syn:registry_count(default, SlaveNode2),

    %% crash scope process to ensure that monitors get recreated
    exit(whereis(syn_registry_default), kill),
    syn_test_suite_helper:wait_process_name_ready(syn_registry_default),

    %% kill process
    syn_test_suite_helper:kill_process(Pid),
    syn_test_suite_helper:kill_process(PidRemoteOn1),
    %% unregister process
    ok = syn:unregister(<<"my proc with meta">>),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> syn:lookup(<<"my proc">>) end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode1, syn, lookup, [<<"my proc">>]) end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode2, syn, lookup, [<<"my proc">>]) end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> syn:lookup({"my proc alias"}) end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode1, syn, lookup, [{"my proc alias"}]) end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode2, syn, lookup, [{"my proc alias"}]) end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> syn:lookup(<<"my proc with meta">>) end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode1, syn, lookup, [<<"my proc with meta">>]) end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode2, syn, lookup, [<<"my proc with meta">>]) end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> syn:lookup({remote_pid_on, slave_1}) end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode1, syn, lookup, [{remote_pid_on, slave_1}]) end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode2, syn, lookup, [{remote_pid_on, slave_1}]) end
    ),
    0 = syn:registry_count(),
    0 = syn:registry_count(default, node()),
    0 = syn:registry_count(default, SlaveNode1),
    0 = syn:registry_count(default, SlaveNode2),

    %% errors
    {error, undefined} = syn:unregister({invalid_name}),

    %% (simulate race condition)
    Pid1 = syn_test_suite_helper:start_process(),
    Pid2 = syn_test_suite_helper:start_process(),
    ok = syn:register(<<"my proc">>, Pid1),
    syn_test_suite_helper:assert_wait(
        {Pid1, undefined},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [<<"my proc">>]) end
    ),
    remove_from_local_table(default, <<"my proc">>, Pid1),
    add_to_local_table(default, <<"my proc">>, Pid2, undefined, 0, undefined),
    {error, race_condition} = rpc:call(SlaveNode1, syn, unregister, [<<"my proc">>]).

three_nodes_register_unregister_and_monitor_custom_scope(Config) ->
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
    PidRemoteWithMetaOn1 = syn_test_suite_helper:start_process(SlaveNode1),

    %% retrieve
    undefined = syn:lookup("scope_a"),
    undefined = rpc:call(SlaveNode1, syn, lookup, ["scope_a"]),
    undefined = rpc:call(SlaveNode2, syn, lookup, ["scope_a"]),
    undefined = syn:lookup(custom_scope_ab, "scope_a"),
    undefined = rpc:call(SlaveNode1, syn, lookup, [custom_scope_ab, "scope_a"]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, lookup, [custom_scope_ab, "scope_a"]),
    undefined = syn:lookup(custom_scope_ab, "scope_a_alias"),
    undefined = rpc:call(SlaveNode1, syn, lookup, [custom_scope_ab, "scope_a_alias"]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, lookup, [custom_scope_ab, "scope_a_alias"]),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:lookup(custom_scope_bc, {remote_scoped_bc}),
    undefined = rpc:call(SlaveNode1, syn, lookup, [custom_scope_bc, {remote_scoped_bc}]),
    undefined = rpc:call(SlaveNode2, syn, lookup, [custom_scope_bc, {remote_scoped_bc}]),
    0 = syn:registry_count(custom_scope_ab),
    0 = syn:registry_count(custom_scope_ab, node()),
    0 = syn:registry_count(custom_scope_ab, SlaveNode1),
    0 = syn:registry_count(custom_scope_ab, SlaveNode2),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:registry_count(custom_scope_bc),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:registry_count(custom_scope_bc, node()),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:registry_count(custom_scope_bc, SlaveNode1),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:registry_count(custom_scope_bc, SlaveNode2),
    0 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_ab]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_ab, node()]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_ab, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_ab, SlaveNode2]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_bc, node()]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_bc, SlaveNode2]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, registry_count, [custom_scope_ab]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, registry_count, [custom_scope_ab, node()]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, registry_count, [custom_scope_ab, SlaveNode1]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, registry_count, [custom_scope_ab, SlaveNode2]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [custom_scope_bc, node()]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [custom_scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [custom_scope_bc, SlaveNode2]),

    %% register
    ok = syn:register(custom_scope_ab, "scope_a", Pid),
    ok = syn:register(custom_scope_ab, "scope_a_alias", PidWithMeta, <<"with_meta">>),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:register(custom_scope_bc, "scope_a", Pid),
    {'EXIT', {{invalid_scope, non_existent_scope}, _}} = catch syn:register(non_existent_scope, "scope_a", Pid),
    ok = rpc:call(SlaveNode2, syn, register, [custom_scope_bc, {remote_scoped_bc}, PidRemoteWithMetaOn1, <<"with_meta 1">>]),

    %% errors
    {error, taken} = syn:register(custom_scope_ab, "scope_a", PidWithMeta),
    {error, not_alive} = syn:register(custom_scope_ab, {"pid not alive"}, list_to_pid("<0.9999.0>")),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:register(custom_scope_bc, "scope_a_noscope", Pid),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:unregister(custom_scope_bc, "scope_a_noscope"),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_bc}, _}}} = catch rpc:call(SlaveNode1, syn, register, [custom_scope_bc, "pid-outside", Pid]),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> syn:lookup("scope_a") end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode1, syn, lookup, ["scope_a"]) end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode2, syn, lookup, ["scope_a"]) end
    ),
    syn_test_suite_helper:assert_wait(
        {Pid, undefined},
        fun() -> syn:lookup(custom_scope_ab, "scope_a") end
    ),
    syn_test_suite_helper:assert_wait(
        {Pid, undefined},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [custom_scope_ab, "scope_a"]) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, lookup, [custom_scope_ab, "scope_a"]),
    syn_test_suite_helper:assert_wait(
        {PidWithMeta, <<"with_meta">>},
        fun() -> syn:lookup(custom_scope_ab, "scope_a_alias") end
    ),
    syn_test_suite_helper:assert_wait(
        {PidWithMeta, <<"with_meta">>},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [custom_scope_ab, "scope_a_alias"]) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, lookup, [custom_scope_ab, "scope_a_alias"]),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:lookup(custom_scope_bc, {remote_scoped_bc}),
    syn_test_suite_helper:assert_wait(
        {PidRemoteWithMetaOn1, <<"with_meta 1">>},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [custom_scope_bc, {remote_scoped_bc}]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteWithMetaOn1, <<"with_meta 1">>},
        fun() -> rpc:call(SlaveNode2, syn, lookup, [custom_scope_bc, {remote_scoped_bc}]) end
    ),
    2 = syn:registry_count(custom_scope_ab),
    2 = syn:registry_count(custom_scope_ab, node()),
    0 = syn:registry_count(custom_scope_ab, SlaveNode1),
    0 = syn:registry_count(custom_scope_ab, SlaveNode2),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:registry_count(custom_scope_bc),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:registry_count(custom_scope_bc, node()),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:registry_count(custom_scope_bc, SlaveNode1),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:registry_count(custom_scope_bc, SlaveNode2),
    2 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_ab]),
    2 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_ab, node()]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_ab, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_ab, SlaveNode2]),
    1 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_bc, node()]),
    1 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_bc, SlaveNode2]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, registry_count, [custom_scope_ab]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, registry_count, [custom_scope_ab, node()]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, registry_count, [custom_scope_ab, SlaveNode1]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, registry_count, [custom_scope_ab, SlaveNode2]),
    1 = rpc:call(SlaveNode2, syn, registry_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [custom_scope_bc, node()]),
    1 = rpc:call(SlaveNode2, syn, registry_count, [custom_scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [custom_scope_bc, SlaveNode2]),

    %% re-register to edit meta
    ok = syn:register(custom_scope_ab, "scope_a_alias", PidWithMeta, <<"with_meta_updated">>),
    syn_test_suite_helper:assert_wait(
        {PidWithMeta, <<"with_meta_updated">>},
        fun() -> syn:lookup(custom_scope_ab, "scope_a_alias") end
    ),
    syn_test_suite_helper:assert_wait(
        {PidWithMeta, <<"with_meta_updated">>},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [custom_scope_ab, "scope_a_alias"]) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, lookup, [custom_scope_ab, "scope_a_alias"]),

    %% crash scope process to ensure that monitors get recreated
    syn_test_suite_helper:kill_process(syn_registry_custom_scope_ab),
    syn_test_suite_helper:wait_process_name_ready(syn_registry_default),

    %% kill process
    syn_test_suite_helper:kill_process(Pid),
    syn_test_suite_helper:kill_process(PidWithMeta),
    %% unregister processes
    {error, undefined} = catch syn:unregister(<<"my proc with meta">>),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:unregister(custom_scope_bc, <<"my proc with meta">>),
    ok = rpc:call(SlaveNode1, syn, unregister, [custom_scope_bc, {remote_scoped_bc}]),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> syn:lookup("scope_a") end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode1, syn, lookup, ["scope_a"]) end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode2, syn, lookup, ["scope_a"]) end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> syn:lookup(custom_scope_ab, "scope_a") end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode1, syn, lookup, [custom_scope_ab, "scope_a"]) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, lookup, [custom_scope_ab, "scope_a"]),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> syn:lookup(custom_scope_ab, "scope_a_alias") end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode1, syn, lookup, [custom_scope_ab, "scope_a_alias"]) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, lookup, [custom_scope_ab, "scope_a_alias"]),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:lookup(custom_scope_bc, {remote_scoped_bc}),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode1, syn, lookup, [custom_scope_bc, {remote_scoped_bc}]) end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode2, syn, lookup, [custom_scope_bc, {remote_scoped_bc}]) end
    ),
    0 = syn:registry_count(custom_scope_ab),
    0 = syn:registry_count(custom_scope_ab, node()),
    0 = syn:registry_count(custom_scope_ab, SlaveNode1),
    0 = syn:registry_count(custom_scope_ab, SlaveNode2),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:registry_count(custom_scope_bc),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:registry_count(custom_scope_bc, node()),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:registry_count(custom_scope_bc, SlaveNode1),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:registry_count(custom_scope_bc, SlaveNode2),
    0 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_ab]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_ab, node()]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_ab, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_ab, SlaveNode2]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_bc, node()]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_bc, SlaveNode2]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, registry_count, [custom_scope_ab]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, registry_count, [custom_scope_ab, node()]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, registry_count, [custom_scope_ab, SlaveNode1]),
    {badrpc, {'EXIT', {{invalid_scope, custom_scope_ab}, _}}} = catch rpc:call(SlaveNode2, syn, registry_count, [custom_scope_ab, SlaveNode2]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [custom_scope_bc, node()]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [custom_scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [custom_scope_bc, SlaveNode2]),

    %% errors
    {error, undefined} = syn:unregister(custom_scope_ab, {invalid_name}),

    %% (simulate race condition)
    Pid1 = syn_test_suite_helper:start_process(),
    Pid2 = syn_test_suite_helper:start_process(),
    ok = syn:register(custom_scope_ab, <<"my proc">>, Pid1),
    syn_test_suite_helper:assert_wait(
        {Pid1, undefined},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [custom_scope_ab, <<"my proc">>]) end
    ),
    remove_from_local_table(custom_scope_ab, <<"my proc">>, Pid1),
    add_to_local_table(custom_scope_ab, <<"my proc">>, Pid2, undefined, 0, undefined),
    {error, race_condition} = rpc:call(SlaveNode1, syn, unregister, [custom_scope_ab, <<"my proc">>]).

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

    %% register
    ok = rpc:call(SlaveNode1, syn, register, ["proc-1", PidRemoteOn1, "meta-1"]),
    ok = rpc:call(SlaveNode2, syn, register, ["proc-2", PidRemoteOn2, "meta-2"]),
    ok = rpc:call(SlaveNode1, syn, register, [custom_scope_bc, "BC-proc-1", PidRemoteOn1, "meta-1"]),
    ok = rpc:call(SlaveNode1, syn, register, [custom_scope_bc, "BC-proc-1 alias", PidRemoteOn1, "meta-1 alias"]),

    %% form full cluster
    ok = syn:start(),
    rpc:call(SlaveNode1, syn_test_suite_helper, connect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node(), SlaveNode1]),
    syn_test_suite_helper:wait_process_name_ready(syn_registry_default),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, "meta-1"},
        fun() -> syn:lookup("proc-1") end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, "meta-1"},
        fun() -> rpc:call(SlaveNode1, syn, lookup, ["proc-1"]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, "meta-1"},
        fun() -> rpc:call(SlaveNode2, syn, lookup, ["proc-1"]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn2, "meta-2"},
        fun() -> syn:lookup("proc-2") end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn2, "meta-2"},
        fun() -> rpc:call(SlaveNode1, syn, lookup, ["proc-2"]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn2, "meta-2"},
        fun() -> rpc:call(SlaveNode2, syn, lookup, ["proc-2"]) end
    ),
    2 = syn:registry_count(),
    0 = syn:registry_count(default, node()),
    1 = syn:registry_count(default, SlaveNode1),
    1 = syn:registry_count(default, SlaveNode2),
    2 = rpc:call(SlaveNode1, syn, registry_count, []),
    0 = rpc:call(SlaveNode1, syn, registry_count, [default, node()]),
    1 = rpc:call(SlaveNode1, syn, registry_count, [default, SlaveNode1]),
    1 = rpc:call(SlaveNode1, syn, registry_count, [default, SlaveNode2]),
    2 = rpc:call(SlaveNode2, syn, registry_count, []),
    0 = rpc:call(SlaveNode2, syn, registry_count, [default, node()]),
    1 = rpc:call(SlaveNode2, syn, registry_count, [default, SlaveNode1]),
    1 = rpc:call(SlaveNode2, syn, registry_count, [default, SlaveNode2]),

    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:lookup(custom_scope_bc, "BC-proc-1"),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, "meta-1"},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [custom_scope_bc, "BC-proc-1"]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, "meta-1"},
        fun() -> rpc:call(SlaveNode2, syn, lookup, [custom_scope_bc, "BC-proc-1"]) end
    ),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:lookup(custom_scope_bc, "BC-proc-1 alias"),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, "meta-1 alias"},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [custom_scope_bc, "BC-proc-1 alias"]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, "meta-1 alias"},
        fun() -> rpc:call(SlaveNode2, syn, lookup, [custom_scope_bc, "BC-proc-1 alias"]) end
    ),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:registry_count(custom_scope_bc),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:registry_count(custom_scope_bc, node()),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:registry_count(custom_scope_bc, SlaveNode1),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:registry_count(custom_scope_bc, SlaveNode2),
    2 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_bc, node()]),
    2 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_bc, SlaveNode2]),
    2 = rpc:call(SlaveNode2, syn, registry_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [custom_scope_bc, node()]),
    2 = rpc:call(SlaveNode2, syn, registry_count, [custom_scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [custom_scope_bc, SlaveNode2]),

    %% partial netsplit (1 cannot see 2)
    rpc:call(SlaveNode1, syn_test_suite_helper, disconnect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node()]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node()]),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, "meta-1"},
        fun() -> syn:lookup("proc-1") end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, "meta-1"},
        fun() -> rpc:call(SlaveNode1, syn, lookup, ["proc-1"]) end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode2, syn, lookup, ["proc-1"]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn2, "meta-2"},
        fun() -> syn:lookup("proc-2") end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode1, syn, lookup, ["proc-2"]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn2, "meta-2"},
        fun() -> rpc:call(SlaveNode2, syn, lookup, ["proc-2"]) end
    ),
    2 = syn:registry_count(),
    0 = syn:registry_count(default, node()),
    1 = syn:registry_count(default, SlaveNode1),
    1 = syn:registry_count(default, SlaveNode2),
    1 = rpc:call(SlaveNode1, syn, registry_count, []),
    0 = rpc:call(SlaveNode1, syn, registry_count, [default, node()]),
    1 = rpc:call(SlaveNode1, syn, registry_count, [default, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [default, SlaveNode2]),
    1 = rpc:call(SlaveNode2, syn, registry_count, []),
    0 = rpc:call(SlaveNode2, syn, registry_count, [default, node()]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [default, SlaveNode1]),
    1 = rpc:call(SlaveNode2, syn, registry_count, [default, SlaveNode2]),

    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:lookup(custom_scope_bc, "BC-proc-1"),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, "meta-1"},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [custom_scope_bc, "BC-proc-1"]) end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode2, syn, lookup, [custom_scope_bc, "BC-proc-1"]) end
    ),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:lookup(custom_scope_bc, "BC-proc-1 alias"),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, "meta-1 alias"},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [custom_scope_bc, "BC-proc-1 alias"]) end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode2, syn, lookup, [custom_scope_bc, "BC-proc-1 alias"]) end
    ),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:registry_count(custom_scope_bc),
    2 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_bc, node()]),
    2 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_bc, SlaveNode2]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [custom_scope_bc, node()]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [custom_scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [custom_scope_bc, SlaveNode2]),

    %% re-join
    rpc:call(SlaveNode1, syn_test_suite_helper, connect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node(), SlaveNode1]),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, "meta-1"},
        fun() -> syn:lookup("proc-1") end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, "meta-1"},
        fun() -> rpc:call(SlaveNode1, syn, lookup, ["proc-1"]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, "meta-1"},
        fun() -> rpc:call(SlaveNode2, syn, lookup, ["proc-1"]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn2, "meta-2"},
        fun() -> syn:lookup("proc-2") end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn2, "meta-2"},
        fun() -> rpc:call(SlaveNode1, syn, lookup, ["proc-2"]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn2, "meta-2"},
        fun() -> rpc:call(SlaveNode2, syn, lookup, ["proc-2"]) end
    ),
    2 = syn:registry_count(),
    0 = syn:registry_count(default, node()),
    1 = syn:registry_count(default, SlaveNode1),
    1 = syn:registry_count(default, SlaveNode2),
    2 = rpc:call(SlaveNode1, syn, registry_count, []),
    0 = rpc:call(SlaveNode1, syn, registry_count, [default, node()]),
    1 = rpc:call(SlaveNode1, syn, registry_count, [default, SlaveNode1]),
    1 = rpc:call(SlaveNode1, syn, registry_count, [default, SlaveNode2]),
    2 = rpc:call(SlaveNode2, syn, registry_count, []),
    0 = rpc:call(SlaveNode2, syn, registry_count, [default, node()]),
    1 = rpc:call(SlaveNode2, syn, registry_count, [default, SlaveNode1]),
    1 = rpc:call(SlaveNode2, syn, registry_count, [default, SlaveNode2]),

    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:lookup(custom_scope_bc, "BC-proc-1"),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, "meta-1"},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [custom_scope_bc, "BC-proc-1"]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, "meta-1"},
        fun() -> rpc:call(SlaveNode2, syn, lookup, [custom_scope_bc, "BC-proc-1"]) end
    ),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:lookup(custom_scope_bc, "BC-proc-1 alias"),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, "meta-1 alias"},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [custom_scope_bc, "BC-proc-1 alias"]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, "meta-1 alias"},
        fun() -> rpc:call(SlaveNode2, syn, lookup, [custom_scope_bc, "BC-proc-1 alias"]) end
    ),
    {'EXIT', {{invalid_scope, custom_scope_bc}, _}} = catch syn:registry_count(custom_scope_bc),
    2 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_bc, node()]),
    2 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_bc, SlaveNode2]),
    2 = rpc:call(SlaveNode2, syn, registry_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [custom_scope_bc, node()]),
    2 = rpc:call(SlaveNode2, syn, registry_count, [custom_scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [custom_scope_bc, SlaveNode2]).

three_nodes_cluster_conflicts(Config) ->
    %% get slaves
    SlaveNode1 = proplists:get_value(slave_node_1, Config),
    SlaveNode2 = proplists:get_value(slave_node_2, Config),

    %% start syn on nodes
    ok = syn:start(),
    ok = rpc:call(SlaveNode1, syn, start, []),
    ok = rpc:call(SlaveNode2, syn, start, []),

    %% add custom scopes
    ok = rpc:call(SlaveNode1, syn, add_node_to_scopes, [[custom_scope_bc]]),
    ok = rpc:call(SlaveNode2, syn, add_node_to_scopes, [[custom_scope_bc]]),

    %% partial netsplit (1 cannot see 2)
    rpc:call(SlaveNode1, syn_test_suite_helper, disconnect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node()]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node()]),

    %% start conflict processes
    Pid2RemoteOn1 = syn_test_suite_helper:start_process(SlaveNode1),
    Pid2RemoteOn2 = syn_test_suite_helper:start_process(SlaveNode2),

    %% --> conflict by netsplit
    ok = rpc:call(SlaveNode1, syn, register, ["proc-confict-by-netsplit", Pid2RemoteOn1, "meta-1"]),
    ok = rpc:call(SlaveNode2, syn, register, ["proc-confict-by-netsplit", Pid2RemoteOn2, "meta-2"]),
    ok = rpc:call(SlaveNode1, syn, register, [custom_scope_bc, "proc-confict-by-netsplit-scoped", Pid2RemoteOn1, "meta-1"]),
    ok = rpc:call(SlaveNode2, syn, register, [custom_scope_bc, "proc-confict-by-netsplit-scoped", Pid2RemoteOn2, "meta-2"]),

    %% re-join
    rpc:call(SlaveNode1, syn_test_suite_helper, connect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node(), SlaveNode1]),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        {Pid2RemoteOn2, "meta-2"},
        fun() -> syn:lookup("proc-confict-by-netsplit") end
    ),
    syn_test_suite_helper:assert_wait(
        {Pid2RemoteOn2, "meta-2"},
        fun() -> rpc:call(SlaveNode1, syn, lookup, ["proc-confict-by-netsplit"]) end
    ),
    syn_test_suite_helper:assert_wait(
        {Pid2RemoteOn2, "meta-2"},
        fun() -> rpc:call(SlaveNode2, syn, lookup, ["proc-confict-by-netsplit"]) end
    ),
    1 = syn:registry_count(),
    0 = syn:registry_count(default, node()),
    0 = syn:registry_count(default, SlaveNode1),
    1 = syn:registry_count(default, SlaveNode2),
    1 = rpc:call(SlaveNode1, syn, registry_count, []),
    0 = rpc:call(SlaveNode1, syn, registry_count, [default, node()]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [default, SlaveNode1]),
    1 = rpc:call(SlaveNode1, syn, registry_count, [default, SlaveNode2]),
    1 = rpc:call(SlaveNode2, syn, registry_count, []),
    0 = rpc:call(SlaveNode2, syn, registry_count, [default, node()]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [default, SlaveNode1]),
    1 = rpc:call(SlaveNode2, syn, registry_count, [default, SlaveNode2]),
    syn_test_suite_helper:assert_wait(
        {Pid2RemoteOn2, "meta-2"},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [custom_scope_bc, "proc-confict-by-netsplit-scoped"]) end
    ),
    syn_test_suite_helper:assert_wait(
        {Pid2RemoteOn2, "meta-2"},
        fun() -> rpc:call(SlaveNode2, syn, lookup, [custom_scope_bc, "proc-confict-by-netsplit-scoped"]) end
    ),
    1 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_bc, node()]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_bc, SlaveNode1]),
    1 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_bc, SlaveNode2]),
    1 = rpc:call(SlaveNode2, syn, registry_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [custom_scope_bc, node()]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [custom_scope_bc, SlaveNode1]),
    1 = rpc:call(SlaveNode2, syn, registry_count, [custom_scope_bc, SlaveNode2]),

    %% process alive
    syn_test_suite_helper:assert_wait(
        false,
        fun() -> rpc:call(SlaveNode1, erlang, is_process_alive, [Pid2RemoteOn1]) end
    ),
    syn_test_suite_helper:assert_wait(
        true,
        fun() -> rpc:call(SlaveNode2, erlang, is_process_alive, [Pid2RemoteOn2]) end
    ),

    %% --> conflict by race condition
    PidOnMaster = syn_test_suite_helper:start_process(),
    PidOn1 = syn_test_suite_helper:start_process(SlaveNode1),
    rpc:call(SlaveNode1, syn_registry, add_to_local_table,
        [default, <<"my proc">>, PidOn1, "meta-2", erlang:system_time(), undefined]
    ),
    ok = syn:register(<<"my proc">>, PidOnMaster, "meta-1"),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        {PidOnMaster, "meta-1"},
        fun() -> syn:lookup(<<"my proc">>) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidOnMaster, "meta-1"},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [<<"my proc">>]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidOnMaster, "meta-1"},
        fun() -> rpc:call(SlaveNode2, syn, lookup, [<<"my proc">>]) end
    ),

    %% NB: we can't check for process alive here because we injected the conflictinf process in the DB
    %% -> it's not actually monitored

    %% same, but custom scope
    PidCustom1 = syn_test_suite_helper:start_process(SlaveNode1),
    PidCustom2 = syn_test_suite_helper:start_process(SlaveNode2),
    rpc:call(SlaveNode2, syn_registry, add_to_local_table,
        [custom_scope_bc, <<"my proc">>, PidCustom2, "meta-2", erlang:system_time(), undefined]
    ),
    ok = rpc:call(SlaveNode1, syn, register, [custom_scope_bc, <<"my proc">>, PidCustom1, "meta-1"]),

    syn_test_suite_helper:assert_wait(
        {PidCustom1, "meta-1"},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [custom_scope_bc, <<"my proc">>]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidCustom1, "meta-1"},
        fun() -> rpc:call(SlaveNode2, syn, lookup, [custom_scope_bc, <<"my proc">>]) end
    ).

three_nodes_custom_event_handler_reg_unreg(Config) ->
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
    Pid2 = syn_test_suite_helper:start_process(),

    %% ---> on registration
    ok = syn:register("proc-handler", Pid, {recipient, self(), <<"meta">>}),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_registered, CurrentNode, default, "proc-handler", Pid, <<"meta">>, normal},
        {on_process_registered, SlaveNode1, default, "proc-handler", Pid, <<"meta">>, normal},
        {on_process_registered, SlaveNode2, default, "proc-handler", Pid, <<"meta">>, normal}
    ]),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% registration from another node
    ok = rpc:call(SlaveNode1, syn, register, ["proc-handler-2", Pid2, {recipient, self(), <<"meta-for-2">>}]),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_registered, CurrentNode, default, "proc-handler-2", Pid2, <<"meta-for-2">>, normal},
        {on_process_registered, SlaveNode1, default, "proc-handler-2", Pid2, <<"meta-for-2">>, normal},
        {on_process_registered, SlaveNode2, default, "proc-handler-2", Pid2, <<"meta-for-2">>, normal}
    ]),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% ---> on meta update
    ok = syn:register("proc-handler", Pid, {recipient, self(), <<"new-meta">>}),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_registry_process_updated, CurrentNode, default, "proc-handler", Pid, <<"new-meta">>, normal},
        {on_registry_process_updated, SlaveNode1, default, "proc-handler", Pid, <<"new-meta">>, normal},
        {on_registry_process_updated, SlaveNode2, default, "proc-handler", Pid, <<"new-meta">>, normal}
    ]),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% meta update from another node
    ok = rpc:call(SlaveNode1, syn, register, ["proc-handler-2", Pid2, {recipient, self(), <<"meta-for-2-update">>}]),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_registry_process_updated, CurrentNode, default, "proc-handler-2", Pid2, <<"meta-for-2-update">>, normal},
        {on_registry_process_updated, SlaveNode1, default, "proc-handler-2", Pid2, <<"meta-for-2-update">>, normal},
        {on_registry_process_updated, SlaveNode2, default, "proc-handler-2", Pid2, <<"meta-for-2-update">>, normal}
    ]),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% ---> on unregister
    ok = syn:unregister("proc-handler"),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_unregistered, CurrentNode, default, "proc-handler", Pid, <<"new-meta">>, normal},
        {on_process_unregistered, SlaveNode1, default, "proc-handler", Pid, <<"new-meta">>, normal},
        {on_process_unregistered, SlaveNode2, default, "proc-handler", Pid, <<"new-meta">>, normal}
    ]),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% unregister from another node
    ok = rpc:call(SlaveNode1, syn, unregister, ["proc-handler-2"]),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_unregistered, CurrentNode, default, "proc-handler-2", Pid2, <<"meta-for-2-update">>, normal},
        {on_process_unregistered, SlaveNode1, default, "proc-handler-2", Pid2, <<"meta-for-2-update">>, normal},
        {on_process_unregistered, SlaveNode2, default, "proc-handler-2", Pid2, <<"meta-for-2-update">>, normal}
    ]),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% clean & check
    syn_test_suite_helper:kill_process(Pid),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% ---> after a netsplit
    PidRemoteOn1 = syn_test_suite_helper:start_process(SlaveNode1),
    syn:register(remote_on_1, PidRemoteOn1, {recipient, self(), <<"netsplit">>}),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_registered, CurrentNode, default, remote_on_1, PidRemoteOn1, <<"netsplit">>, normal},
        {on_process_registered, SlaveNode1, default, remote_on_1, PidRemoteOn1, <<"netsplit">>, normal},
        {on_process_registered, SlaveNode2, default, remote_on_1, PidRemoteOn1, <<"netsplit">>, normal}
    ]),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% partial netsplit (1 cannot see 2)
    rpc:call(SlaveNode1, syn_test_suite_helper, disconnect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node()]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node()]),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_unregistered, SlaveNode2, default, remote_on_1, PidRemoteOn1, <<"netsplit">>, {syn_remote_scope_node_down, default, SlaveNode1}}
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
        {on_process_registered, SlaveNode2, default, remote_on_1, PidRemoteOn1, <<"netsplit">>, {syn_remote_scope_node_up, default, SlaveNode1}}
    ]),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% clean
    syn_test_suite_helper:kill_process(PidRemoteOn1),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_unregistered, CurrentNode, default, remote_on_1, PidRemoteOn1, <<"netsplit">>, killed},
        {on_process_unregistered, SlaveNode1, default, remote_on_1, PidRemoteOn1, <<"netsplit">>, killed},
        {on_process_unregistered, SlaveNode2, default, remote_on_1, PidRemoteOn1, <<"netsplit">>, killed}
    ]),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% ---> after a conflict resolution
    %% partial netsplit (1 cannot see 2)
    rpc:call(SlaveNode1, syn_test_suite_helper, disconnect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node()]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node()]),

    %% start conflict processes
    Pid2RemoteOn1 = syn_test_suite_helper:start_process(SlaveNode1),
    Pid2RemoteOn2 = syn_test_suite_helper:start_process(SlaveNode2),

    ok = rpc:call(SlaveNode1, syn, register, ["proc-confict", Pid2RemoteOn1, {recipient, self(), <<"meta-1">>}]),
    ok = rpc:call(SlaveNode2, syn, register, ["proc-confict", Pid2RemoteOn2, {recipient, self(), <<"meta-2">>}]),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_registered, CurrentNode, default, "proc-confict", Pid2RemoteOn1, <<"meta-1">>, normal},
        {on_process_unregistered, CurrentNode, default, "proc-confict", Pid2RemoteOn1, <<"meta-1">>, normal},
        {on_process_registered, CurrentNode, default, "proc-confict", Pid2RemoteOn2, <<"meta-2">>, normal},
        {on_process_registered, SlaveNode1, default, "proc-confict", Pid2RemoteOn1, <<"meta-1">>, normal},
        {on_process_registered, SlaveNode2, default, "proc-confict", Pid2RemoteOn2, <<"meta-2">>, normal}
    ]),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% re-join
    rpc:call(SlaveNode1, syn_test_suite_helper, connect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node(), SlaveNode1]),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_unregistered, SlaveNode1, default, "proc-confict", Pid2RemoteOn1, <<"meta-1">>, syn_conflict_resolution},
        {on_process_registered, SlaveNode1, default, "proc-confict", Pid2RemoteOn2, <<"meta-2">>, syn_conflict_resolution}
    ]),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% kill
    syn_test_suite_helper:kill_process(Pid2RemoteOn1),
    syn_test_suite_helper:kill_process(Pid2RemoteOn2),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_unregistered, CurrentNode, default, "proc-confict", Pid2RemoteOn2, <<"meta-2">>, killed},
        {on_process_unregistered, SlaveNode1, default, "proc-confict", Pid2RemoteOn2, <<"meta-2">>, killed},
        {on_process_unregistered, SlaveNode2, default, "proc-confict", Pid2RemoteOn2, <<"meta-2">>, killed}
    ]),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% ---> don't call on monitor rebuild
    %% crash the scope process on local
    syn_test_suite_helper:kill_process(syn_registry_default),

    %% no messages
    syn_test_suite_helper:assert_wait(
        ok,
        fun() -> syn_test_suite_helper:assert_empty_queue(self()) end
    ).

three_nodes_custom_event_handler_conflict_resolution(Config) ->
    %% get slaves
    SlaveNode1 = proplists:get_value(slave_node_1, Config),
    SlaveNode2 = proplists:get_value(slave_node_2, Config),

    %% add custom handler for resolution
    syn:set_event_handler(syn_test_event_handler_resolution),
    rpc:call(SlaveNode1, syn, set_event_handler, [syn_test_event_handler_resolution]),
    rpc:call(SlaveNode2, syn, set_event_handler, [syn_test_event_handler_resolution]),

    %% start syn on nodes
    ok = syn:start(),
    ok = rpc:call(SlaveNode1, syn, start, []),
    ok = rpc:call(SlaveNode2, syn, start, []),

    %% add custom scopes
    ok = rpc:call(SlaveNode1, syn, add_node_to_scopes, [[custom_scope_bc]]),
    ok = rpc:call(SlaveNode2, syn, add_node_to_scopes, [[custom_scope_bc]]),

    %% current node
    TestPid = self(),
    CurrentNode = node(),

    %% partial netsplit (1 cannot see 2)
    rpc:call(SlaveNode1, syn_test_suite_helper, disconnect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node()]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node()]),

    %% start conflict processes
    PidOn1 = syn_test_suite_helper:start_process(SlaveNode1),
    PidOn2 = syn_test_suite_helper:start_process(SlaveNode2),

    %% --> conflict by netsplit
    ok = rpc:call(SlaveNode1, syn, register, ["proc-confict-by-netsplit-custom", PidOn1, {recipient, TestPid, keepthis}]),
    ok = rpc:call(SlaveNode2, syn, register, ["proc-confict-by-netsplit-custom", PidOn2, {recipient, TestPid, "meta-2"}]),
    ok = rpc:call(SlaveNode1, syn, register, [custom_scope_bc, "proc-confict-by-netsplit-scoped-custom", PidOn1, {recipient, TestPid, keepthis}]),
    ok = rpc:call(SlaveNode2, syn, register, [custom_scope_bc, "proc-confict-by-netsplit-scoped-custom", PidOn2, {recipient, TestPid, "meta-2"}]),

    %% check callbacks
    syn_test_suite_helper:assert_received_messages([
        {on_process_registered, CurrentNode, default, "proc-confict-by-netsplit-custom", PidOn1, keepthis, normal},
        {on_process_unregistered, CurrentNode, default, "proc-confict-by-netsplit-custom", PidOn1, keepthis, normal},
        {on_process_registered, CurrentNode, default, "proc-confict-by-netsplit-custom", PidOn2, "meta-2", normal},

        {on_process_registered, SlaveNode1, default, "proc-confict-by-netsplit-custom", PidOn1, keepthis, normal},
        {on_process_registered, SlaveNode2, default, "proc-confict-by-netsplit-custom", PidOn2, "meta-2", normal},
        {on_process_registered, SlaveNode1, custom_scope_bc, "proc-confict-by-netsplit-scoped-custom", PidOn1, keepthis, normal},
        {on_process_registered, SlaveNode2, custom_scope_bc, "proc-confict-by-netsplit-scoped-custom", PidOn2, "meta-2", normal}
    ]),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% re-join
    rpc:call(SlaveNode1, syn_test_suite_helper, connect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node(), SlaveNode1]),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        {PidOn1, {recipient, TestPid, keepthis}},
        fun() -> syn:lookup("proc-confict-by-netsplit-custom") end
    ),
    syn_test_suite_helper:assert_wait(
        {PidOn1, {recipient, TestPid, keepthis}},
        fun() -> rpc:call(SlaveNode1, syn, lookup, ["proc-confict-by-netsplit-custom"]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidOn1, {recipient, TestPid, keepthis}},
        fun() -> rpc:call(SlaveNode2, syn, lookup, ["proc-confict-by-netsplit-custom"]) end
    ),
    1 = syn:registry_count(),
    0 = syn:registry_count(default, node()),
    1 = syn:registry_count(default, SlaveNode1),
    0 = syn:registry_count(default, SlaveNode2),
    1 = rpc:call(SlaveNode1, syn, registry_count, []),
    0 = rpc:call(SlaveNode1, syn, registry_count, [default, node()]),
    1 = rpc:call(SlaveNode1, syn, registry_count, [default, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [default, SlaveNode2]),
    1 = rpc:call(SlaveNode2, syn, registry_count, []),
    0 = rpc:call(SlaveNode2, syn, registry_count, [default, node()]),
    1 = rpc:call(SlaveNode2, syn, registry_count, [default, SlaveNode1]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [default, SlaveNode2]),
    syn_test_suite_helper:assert_wait(
        {PidOn1, {recipient, TestPid, keepthis}},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [custom_scope_bc, "proc-confict-by-netsplit-scoped-custom"]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidOn1, {recipient, TestPid, keepthis}},
        fun() -> rpc:call(SlaveNode2, syn, lookup, [custom_scope_bc, "proc-confict-by-netsplit-scoped-custom"]) end
    ),
    1 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_bc, node()]),
    1 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [custom_scope_bc, SlaveNode2]),
    1 = rpc:call(SlaveNode2, syn, registry_count, [custom_scope_bc]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [custom_scope_bc, node()]),
    1 = rpc:call(SlaveNode2, syn, registry_count, [custom_scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [custom_scope_bc, SlaveNode2]),

    syn_test_suite_helper:assert_received_messages([
        {on_process_unregistered, CurrentNode, default, "proc-confict-by-netsplit-custom", PidOn2, "meta-2", syn_conflict_resolution},
        {on_process_registered, CurrentNode, default, "proc-confict-by-netsplit-custom", PidOn1, keepthis, syn_conflict_resolution},

        {on_process_unregistered, SlaveNode2, default, "proc-confict-by-netsplit-custom", PidOn2, "meta-2", syn_conflict_resolution},
        {on_process_registered, SlaveNode2, default, "proc-confict-by-netsplit-custom", PidOn1, keepthis, syn_conflict_resolution},
        {on_process_unregistered, SlaveNode2, custom_scope_bc, "proc-confict-by-netsplit-scoped-custom", PidOn2, "meta-2", syn_conflict_resolution},
        {on_process_registered, SlaveNode2, custom_scope_bc, "proc-confict-by-netsplit-scoped-custom", PidOn1, keepthis, syn_conflict_resolution}
    ]),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% process alive (discarded process does not get killed with a custom handler)
    syn_test_suite_helper:assert_wait(
        true,
        fun() -> rpc:call(SlaveNode1, erlang, is_process_alive, [PidOn1]) end
    ),
    syn_test_suite_helper:assert_wait(
        true,
        fun() -> rpc:call(SlaveNode2, erlang, is_process_alive, [PidOn2]) end
    ),

    %% clean up default scope
    syn:unregister("proc-confict-by-netsplit-custom"),
    ok = rpc:call(SlaveNode1, syn, unregister, [custom_scope_bc, "proc-confict-by-netsplit-scoped-custom"]),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> syn:lookup("proc-confict-by-netsplit-custom") end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode1, syn, lookup, ["proc-confict-by-netsplit-custom"]) end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode2, syn, lookup, ["proc-confict-by-netsplit-custom"]) end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode1, syn, lookup, [custom_scope_bc, "proc-confict-by-netsplit-scoped-custom"]) end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode2, syn, lookup, [custom_scope_bc, "proc-confict-by-netsplit-scoped-custom"]) end
    ),

    %% check callbacks
    syn_test_suite_helper:assert_received_messages([
        {on_process_unregistered, CurrentNode, default, "proc-confict-by-netsplit-custom", PidOn1, keepthis, normal},
        {on_process_unregistered, SlaveNode1, default, "proc-confict-by-netsplit-custom", PidOn1, keepthis, normal},
        {on_process_unregistered, SlaveNode2, default, "proc-confict-by-netsplit-custom", PidOn1, keepthis, normal},
        {on_process_unregistered, SlaveNode1, custom_scope_bc, "proc-confict-by-netsplit-scoped-custom", PidOn1, keepthis, normal},
        {on_process_unregistered, SlaveNode2, custom_scope_bc, "proc-confict-by-netsplit-scoped-custom", PidOn1, keepthis, normal}
    ]),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% --> conflict by netsplit, which returns invalid pid
    %% partial netsplit (1 cannot see 2)
    rpc:call(SlaveNode1, syn_test_suite_helper, disconnect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node()]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node()]),

    %% register with meta with no 'keepthis' element
    ok = rpc:call(SlaveNode1, syn, register, ["proc-confict-by-netsplit-custom-other-pid", PidOn1, {recipient, TestPid, "meta-1"}]),
    ok = rpc:call(SlaveNode2, syn, register, ["proc-confict-by-netsplit-custom-other-pid", PidOn2, {recipient, TestPid, "meta-2"}]),

    %% check callbacks
    syn_test_suite_helper:assert_received_messages([
        {on_process_registered, CurrentNode, default, "proc-confict-by-netsplit-custom-other-pid", PidOn1, "meta-1", normal},
        {on_process_unregistered, CurrentNode, default, "proc-confict-by-netsplit-custom-other-pid", PidOn1, "meta-1", normal},
        {on_process_registered, CurrentNode, default, "proc-confict-by-netsplit-custom-other-pid", PidOn2, "meta-2", normal},

        {on_process_registered, SlaveNode1, default, "proc-confict-by-netsplit-custom-other-pid", PidOn1, "meta-1", normal},
        {on_process_registered, SlaveNode2, default, "proc-confict-by-netsplit-custom-other-pid", PidOn2, "meta-2", normal}
    ]),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% re-join
    rpc:call(SlaveNode1, syn_test_suite_helper, connect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node(), SlaveNode1]),

    %% retrieve (names get freed)
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> syn:lookup("proc-confict-by-netsplit-custom-other-pid") end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode1, syn, lookup, ["proc-confict-by-netsplit-custom-other-pid"]) end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode2, syn, lookup, ["proc-confict-by-netsplit-custom-other-pid"]) end
    ),
    0 = syn:registry_count(),
    0 = syn:registry_count(default, node()),
    0 = syn:registry_count(default, SlaveNode1),
    0 = syn:registry_count(default, SlaveNode2),
    0 = rpc:call(SlaveNode1, syn, registry_count, []),
    0 = rpc:call(SlaveNode1, syn, registry_count, [default, node()]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [default, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [default, SlaveNode2]),
    0 = rpc:call(SlaveNode2, syn, registry_count, []),
    0 = rpc:call(SlaveNode2, syn, registry_count, [default, node()]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [default, SlaveNode1]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [default, SlaveNode2]),

    %% check callbacks
    syn_test_suite_helper:assert_received_messages([
        {on_process_unregistered, CurrentNode, default, "proc-confict-by-netsplit-custom-other-pid", PidOn2, "meta-2", syn_conflict_resolution},
        {on_process_unregistered, SlaveNode1, default, "proc-confict-by-netsplit-custom-other-pid", PidOn1, "meta-1", syn_conflict_resolution},
        {on_process_unregistered, SlaveNode2, default, "proc-confict-by-netsplit-custom-other-pid", PidOn2, "meta-2", syn_conflict_resolution}
    ]),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% process alive (discarded process does not get killed with a custom handler)
    syn_test_suite_helper:assert_wait(
        true,
        fun() -> rpc:call(SlaveNode1, erlang, is_process_alive, [PidOn1]) end
    ),
    syn_test_suite_helper:assert_wait(
        true,
        fun() -> rpc:call(SlaveNode2, erlang, is_process_alive, [PidOn2]) end
    ),

    %% --> conflict by netsplit, which crashes

    %% partial netsplit (1 cannot see 2)
    rpc:call(SlaveNode1, syn_test_suite_helper, disconnect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node()]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node()]),

    %% register with meta with no 'crash' element
    ok = rpc:call(SlaveNode1, syn, register, ["proc-confict-by-netsplit-custom-crash", PidOn1, {recipient, TestPid, crash}]),
    ok = rpc:call(SlaveNode2, syn, register, ["proc-confict-by-netsplit-custom-crash", PidOn2, {recipient, TestPid, crash}]),

    %% check callbacks
    syn_test_suite_helper:assert_received_messages([
        {on_process_registered, CurrentNode, default, "proc-confict-by-netsplit-custom-crash", PidOn1, crash, normal},
        {on_process_unregistered, CurrentNode, default, "proc-confict-by-netsplit-custom-crash", PidOn1, crash, normal},
        {on_process_registered, CurrentNode, default, "proc-confict-by-netsplit-custom-crash", PidOn2, crash, normal},

        {on_process_registered, SlaveNode1, default, "proc-confict-by-netsplit-custom-crash", PidOn1, crash, normal},
        {on_process_registered, SlaveNode2, default, "proc-confict-by-netsplit-custom-crash", PidOn2, crash, normal}
    ]),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% re-join
    rpc:call(SlaveNode1, syn_test_suite_helper, connect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node(), SlaveNode1]),

    %% retrieve (names get freed)
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> syn:lookup("proc-confict-by-netsplit-custom-crash") end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode1, syn, lookup, ["proc-confict-by-netsplit-custom-crash"]) end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode2, syn, lookup, ["proc-confict-by-netsplit-custom-crash"]) end
    ),
    0 = syn:registry_count(),
    0 = syn:registry_count(default, node()),
    0 = syn:registry_count(default, SlaveNode1),
    0 = syn:registry_count(default, SlaveNode2),
    0 = rpc:call(SlaveNode1, syn, registry_count, []),
    0 = rpc:call(SlaveNode1, syn, registry_count, [default, node()]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [default, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [default, SlaveNode2]),
    0 = rpc:call(SlaveNode2, syn, registry_count, []),
    0 = rpc:call(SlaveNode2, syn, registry_count, [default, node()]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [default, SlaveNode1]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [default, SlaveNode2]),

    %% check callbacks
    syn_test_suite_helper:assert_received_messages([
        {on_process_unregistered, CurrentNode, default, "proc-confict-by-netsplit-custom-crash", PidOn2, crash, syn_conflict_resolution},
        {on_process_unregistered, SlaveNode1, default, "proc-confict-by-netsplit-custom-crash", PidOn1, crash, syn_conflict_resolution},
        {on_process_unregistered, SlaveNode2, default, "proc-confict-by-netsplit-custom-crash", PidOn2, crash, syn_conflict_resolution}
    ]),
    syn_test_suite_helper:assert_empty_queue(self()),

    %% process alive (discarded process does not get killed with a custom handler)
    syn_test_suite_helper:assert_wait(
        true,
        fun() -> rpc:call(SlaveNode1, erlang, is_process_alive, [PidOn1]) end
    ),
    syn_test_suite_helper:assert_wait(
        true,
        fun() -> rpc:call(SlaveNode2, erlang, is_process_alive, [PidOn2]) end
    ).

%% ===================================================================
%% Internal
%% ===================================================================
add_to_local_table(Scope, Name, Pid, Meta, Time, MRef) ->
    TableByName = syn_backbone:get_table_name(syn_registry_by_name, Scope),
    TableByPid = syn_backbone:get_table_name(syn_registry_by_pid, Scope),
    syn_registry:add_to_local_table(Name, Pid, Meta, Time, MRef, TableByName, TableByPid).

remove_from_local_table(Scope, Name, Pid) ->
    TableByName = syn_backbone:get_table_name(syn_registry_by_name, Scope),
    TableByPid = syn_backbone:get_table_name(syn_registry_by_pid, Scope),
    syn_registry:remove_from_local_table(Name, Pid, TableByName, TableByPid).
