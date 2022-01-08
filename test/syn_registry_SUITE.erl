%% ==========================================================================================================
%% Syn - A global Process Registry and Process Group manager.
%%
%% The MIT License (MIT)
%%
%% Copyright (c) 2015-2022 Roberto Ostinelli <roberto@ostinelli.net> and Neato Robotics, Inc.
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
    one_node_via_register_unregister/1,
    one_node_via_register_unregister_with_metadata/1,
    one_node_strict_mode/1
]).
-export([
    three_nodes_discover/1,
    three_nodes_register_unregister_and_monitor/1,
    three_nodes_register_filter_unknown_node/1,
    three_nodes_cluster_changes/1,
    three_nodes_cluster_conflicts/1,
    three_nodes_custom_event_handler_reg_unreg/1,
    three_nodes_custom_event_handler_conflict_resolution/1,
    three_nodes_update/1
]).
-export([
    four_nodes_concurrency/1
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
        {group, one_node_registry},
        {group, three_nodes_registry},
        {group, four_nodes_registry}
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
        {one_node_registry, [shuffle], [
            one_node_via_register_unregister,
            one_node_via_register_unregister_with_metadata,
            one_node_strict_mode
        ]},
        {three_nodes_registry, [shuffle], [
            three_nodes_discover,
            three_nodes_register_unregister_and_monitor,
            three_nodes_register_filter_unknown_node,
            three_nodes_cluster_changes,
            three_nodes_cluster_conflicts,
            three_nodes_custom_event_handler_reg_unreg,
            three_nodes_custom_event_handler_conflict_resolution,
            three_nodes_update
        ]},
        {four_nodes_registry, [shuffle], [
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
init_per_group(three_nodes_registry, Config) ->
    case syn_test_suite_helper:init_cluster(3) of
        {error_initializing_cluster, Other} ->
            end_per_group(three_nodes_registry, Config),
            {skip, Other};

        NodesConfig ->
            NodesConfig ++ Config
    end;

init_per_group(four_nodes_registry, Config) ->
    case syn_test_suite_helper:init_cluster(4) of
        {error_initializing_cluster, Other} ->
            end_per_group(four_nodes_registry, Config),
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
end_per_group(three_nodes_registry, Config) ->
    syn_test_suite_helper:end_cluster(3, Config);
end_per_group(four_nodes_registry, Config) ->
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
one_node_via_register_unregister(_Config) ->
    %% start syn
    ok = syn:start(),

    %% --->  scope
    syn:add_node_to_scopes([scope]),

    %% start gen server via syn
    GenServerNameCustom = {scope, <<"my proc">>},
    TupleCustom = {via, syn, GenServerNameCustom},
    {ok, PidCustom} = syn_test_gen_server:start_link(TupleCustom),

    %% retrieve
    {PidCustom, undefined} = syn:lookup(scope, <<"my proc">>),
    PidCustom = syn:whereis_name(GenServerNameCustom),

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
        fun() -> syn:lookup(scope, <<"my proc">>) end
    ),

    %% send via syn
    {badarg, {GenServerNameCustom, anything}} = (catch syn:send(GenServerNameCustom, anything)).

one_node_via_register_unregister_with_metadata(_Config) ->
    %% start syn
    ok = syn:start(),
    syn:add_node_to_scopes([scope]),

    %% start gen server via syn
    GenServerNameCustomMeta = {scope, <<"my proc">>, my_metadata},
    TupleCustomMeta = {via, syn, GenServerNameCustomMeta},
    {ok, PidCustom} = syn_test_gen_server:start_link(TupleCustomMeta),

    %% retrieve
    {PidCustom, my_metadata} = syn:lookup(scope, <<"my proc">>),
    PidCustom = syn:whereis_name(GenServerNameCustomMeta),
    PidCustom = syn:whereis_name({scope, <<"my proc">>}),

    %% call
    pong = syn_test_gen_server:ping(TupleCustomMeta),

    %% send via syn
    syn:send(GenServerNameCustomMeta, {self(), send_ping}),
    syn_test_suite_helper:assert_received_messages([
        reply_pong
    ]),

    %% stop server
    syn_test_gen_server:stop(TupleCustomMeta),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> syn:lookup(scope, <<"my proc">>) end
    ),

    %% send via syn
    {badarg, {GenServerNameCustomMeta, anything}} = (catch syn:send(GenServerNameCustomMeta, anything)).

one_node_strict_mode(_Config) ->
    %% start syn
    ok = syn:start(),
    syn:add_node_to_scopes([scope]),

    %% strict mode enabled
    application:set_env(syn, strict_mode, true),

    %% start process
    Pid = syn_test_suite_helper:start_process(),
    {error, not_self} = syn:register(scope, "strict-true", Pid, metadata),

    Self = self(),
    ok = syn:register(scope, "strict-true", Self, metadata),
    ok = syn:register(scope, "strict-true", Self, new_metadata),
    {Self, new_metadata} = syn:lookup(scope, "strict-true"),
    ok = syn:register(scope, "strict-true", Self),
    {Self, undefined} = syn:lookup(scope, "strict-true").

three_nodes_discover(Config) ->
    %% get slaves
    SlaveNode1 = proplists:get_value(syn_slave_1, Config),
    SlaveNode2 = proplists:get_value(syn_slave_2, Config),

    %% add scopes partially with ENV
    ok = rpc:call(SlaveNode2, application, set_env, [syn, scopes, [scope_all]]),

    %% start syn on nodes
    ok = syn:start(),
    ok = rpc:call(SlaveNode1, syn, start, []),
    ok = rpc:call(SlaveNode2, syn, start, []),

    %% add scopes
    ok = syn:add_node_to_scopes([scope_ab]),
    ok = syn:add_node_to_scopes([scope_all]),
    ok = rpc:call(SlaveNode1, syn, add_node_to_scopes, [[scope_ab, scope_bc, scope_all]]),
    ok = rpc:call(SlaveNode2, syn, add_node_to_scopes, [[scope_bc, scope_c]]),

    %% subcluster_nodes should return invalid errors
    {'EXIT', {{invalid_scope, custom_abcdef}, _}} = (catch syn_registry:subcluster_nodes(custom_abcdef)),

    %% check
    syn_test_suite_helper:assert_registry_scope_subcluster(node(), scope_ab, [SlaveNode1]),
    syn_test_suite_helper:assert_registry_scope_subcluster(node(), scope_all, [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode1, scope_ab, [node()]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode1, scope_bc, [SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode1, scope_all, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode2, scope_bc, [SlaveNode1]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode2, scope_c, []),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode2, scope_all, [node(), SlaveNode1]),

    %% disconnect node 2 (node 1 can still see node 2)
    syn_test_suite_helper:disconnect_node(SlaveNode2),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node(), SlaveNode2]),

    %% check
    syn_test_suite_helper:assert_registry_scope_subcluster(node(), scope_ab, [SlaveNode1]),
    syn_test_suite_helper:assert_registry_scope_subcluster(node(), scope_all, [SlaveNode1]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode1, scope_ab, [node()]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode1, scope_bc, [SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode1, scope_all, [node(), SlaveNode2]),

    %% reconnect node 2
    syn_test_suite_helper:connect_node(SlaveNode2),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node(), SlaveNode1]),

    %% check
    syn_test_suite_helper:assert_registry_scope_subcluster(node(), scope_ab, [SlaveNode1]),
    syn_test_suite_helper:assert_registry_scope_subcluster(node(), scope_all, [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode1, scope_ab, [node()]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode1, scope_bc, [SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode1, scope_all, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode2, scope_bc, [SlaveNode1]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode2, scope_c, []),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode2, scope_all, [node(), SlaveNode1]),

    %% crash a scope process on 2
    rpc:call(SlaveNode2, syn_test_suite_helper, kill_process, [syn_registry_scope_bc]),
    rpc:call(SlaveNode2, syn_test_suite_helper, wait_process_name_ready, [syn_registry_scope_bc]),

    %% check
    syn_test_suite_helper:assert_registry_scope_subcluster(node(), scope_ab, [SlaveNode1]),
    syn_test_suite_helper:assert_registry_scope_subcluster(node(), scope_all, [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode1, scope_ab, [node()]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode1, scope_bc, [SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode1, scope_all, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode2, scope_bc, [SlaveNode1]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode2, scope_c, []),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode2, scope_all, [node(), SlaveNode1]),

    %% crash scopes supervisor on local
    syn_test_suite_helper:kill_process(syn_scopes_sup),
    syn_test_suite_helper:wait_process_name_ready(syn_registry_scope_ab),
    syn_test_suite_helper:wait_process_name_ready(syn_registry_scope_all),

    %% check
    syn_test_suite_helper:assert_registry_scope_subcluster(node(), scope_ab, [SlaveNode1]),
    syn_test_suite_helper:assert_registry_scope_subcluster(node(), scope_all, [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode1, scope_ab, [node()]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode1, scope_bc, [SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode1, scope_all, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode2, scope_bc, [SlaveNode1]),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode2, scope_c, []),
    syn_test_suite_helper:assert_registry_scope_subcluster(SlaveNode2, scope_all, [node(), SlaveNode1]).

three_nodes_register_unregister_and_monitor(Config) ->
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
    PidRemoteWithMetaOn1 = syn_test_suite_helper:start_process(SlaveNode1),

    %% retrieve
    undefined = syn:lookup(scope_ab, "scope_a"),
    undefined = rpc:call(SlaveNode1, syn, lookup, [scope_ab, "scope_a"]),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, lookup, [scope_ab, "scope_a"])),
    undefined = syn:lookup(scope_ab, "scope_a_alias"),
    undefined = rpc:call(SlaveNode1, syn, lookup, [scope_ab, "scope_a_alias"]),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, lookup, [scope_ab, "scope_a_alias"])),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:lookup(scope_bc, {remote_scoped_bc})),
    undefined = rpc:call(SlaveNode1, syn, lookup, [scope_bc, {remote_scoped_bc}]),
    undefined = rpc:call(SlaveNode2, syn, lookup, [scope_bc, {remote_scoped_bc}]),
    0 = syn:registry_count(scope_ab),
    0 = syn:registry_count(scope_ab, node()),
    0 = syn:registry_count(scope_ab, SlaveNode1),
    0 = syn:registry_count(scope_ab, SlaveNode2),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:registry_count(scope_bc)),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:registry_count(scope_bc, node())),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:registry_count(scope_bc, SlaveNode1)),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:registry_count(scope_bc, SlaveNode2)),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_ab]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_ab, node()]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_ab, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_ab, SlaveNode2]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_bc]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_bc, node()]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_bc, SlaveNode2]),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, registry_count, [scope_ab])),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, registry_count, [scope_ab, node()])),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, registry_count, [scope_ab, SlaveNode1])),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, registry_count, [scope_ab, SlaveNode2])),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_bc]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_bc, node()]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_bc, SlaveNode2]),

    %% register
    ok = syn:register(scope_ab, "scope_a", Pid),
    ok = syn:register(scope_ab, "scope_a_alias", PidWithMeta, <<"with_meta">>),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:register(scope_bc, "scope_a", Pid)),
    {'EXIT', {{invalid_scope, non_existent_scope}, _}} = (catch syn:register(non_existent_scope, "scope_a", Pid)),
    ok = rpc:call(SlaveNode2, syn, register, [scope_bc, {remote_scoped_bc}, PidRemoteWithMetaOn1, <<"with_meta 1">>]),

    %% errors
    {error, taken} = syn:register(scope_ab, "scope_a", PidWithMeta),
    {error, not_alive} = syn:register(scope_ab, {"pid not alive"}, list_to_pid("<0.9999.0>")),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:register(scope_bc, "scope_a_noscope", Pid)),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:unregister(scope_bc, "scope_a_noscope")),
    LocalNode = node(),
    {badrpc, {'EXIT', {{invalid_remote_scope, scope_bc, LocalNode}, _}}} = (catch rpc:call(SlaveNode1, syn, register, [scope_bc, "pid-outside", Pid])),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        {Pid, undefined},
        fun() -> syn:lookup(scope_ab, "scope_a") end
    ),
    syn_test_suite_helper:assert_wait(
        {Pid, undefined},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [scope_ab, "scope_a"]) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, lookup, [scope_ab, "scope_a"])),
    syn_test_suite_helper:assert_wait(
        {PidWithMeta, <<"with_meta">>},
        fun() -> syn:lookup(scope_ab, "scope_a_alias") end
    ),
    syn_test_suite_helper:assert_wait(
        {PidWithMeta, <<"with_meta">>},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [scope_ab, "scope_a_alias"]) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, lookup, [scope_ab, "scope_a_alias"])),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:lookup(scope_bc, {remote_scoped_bc})),
    syn_test_suite_helper:assert_wait(
        {PidRemoteWithMetaOn1, <<"with_meta 1">>},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [scope_bc, {remote_scoped_bc}]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteWithMetaOn1, <<"with_meta 1">>},
        fun() -> rpc:call(SlaveNode2, syn, lookup, [scope_bc, {remote_scoped_bc}]) end
    ),
    2 = syn:registry_count(scope_ab),
    2 = syn:registry_count(scope_ab, node()),
    0 = syn:registry_count(scope_ab, SlaveNode1),
    0 = syn:registry_count(scope_ab, SlaveNode2),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:registry_count(scope_bc)),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:registry_count(scope_bc, node())),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:registry_count(scope_bc, SlaveNode1)),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:registry_count(scope_bc, SlaveNode2)),
    2 = rpc:call(SlaveNode1, syn, registry_count, [scope_ab]),
    2 = rpc:call(SlaveNode1, syn, registry_count, [scope_ab, node()]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_ab, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_ab, SlaveNode2]),
    1 = rpc:call(SlaveNode1, syn, registry_count, [scope_bc]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_bc, node()]),
    1 = rpc:call(SlaveNode1, syn, registry_count, [scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_bc, SlaveNode2]),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, registry_count, [scope_ab])),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, registry_count, [scope_ab, node()])),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, registry_count, [scope_ab, SlaveNode1])),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, registry_count, [scope_ab, SlaveNode2])),
    1 = rpc:call(SlaveNode2, syn, registry_count, [scope_bc]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_bc, node()]),
    1 = rpc:call(SlaveNode2, syn, registry_count, [scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_bc, SlaveNode2]),

    %% re-register to edit meta
    ok = syn:register(scope_ab, "scope_a_alias", PidWithMeta, <<"with_meta_updated">>),

    syn_test_suite_helper:assert_wait(
        {PidWithMeta, <<"with_meta_updated">>},
        fun() -> syn:lookup(scope_ab, "scope_a_alias") end
    ),
    syn_test_suite_helper:assert_wait(
        {PidWithMeta, <<"with_meta_updated">>},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [scope_ab, "scope_a_alias"]) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, lookup, [scope_ab, "scope_a_alias"])),

    %% register remote
    ok = syn:register(scope_ab, "ab_on_1", PidRemoteWithMetaOn1, <<"ab-on-1">>),
    syn_test_suite_helper:assert_wait(
        {PidRemoteWithMetaOn1, <<"ab-on-1">>},
        fun() -> syn:lookup(scope_ab, "ab_on_1") end
    ),

    %% crash scope process to ensure that monitors get recreated & data received from other nodes
    syn_test_suite_helper:kill_process(syn_registry_scope_ab),
    syn_test_suite_helper:wait_process_name_ready(syn_registry_scope_ab),

    %% check remote has been sync'ed back
    syn_test_suite_helper:assert_wait(
        {PidRemoteWithMetaOn1, <<"ab-on-1">>},
        fun() -> syn:lookup(scope_ab, "ab_on_1") end
    ),

    %% kill process
    syn_test_suite_helper:kill_process(Pid),
    syn_test_suite_helper:kill_process(PidWithMeta),
    %% unregister processes
    {error, undefined} = (catch syn:unregister(scope_ab, <<"my proc with meta">>)),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:unregister(scope_bc, <<"my proc with meta">>)),
    ok = rpc:call(SlaveNode1, syn, unregister, [scope_bc, {remote_scoped_bc}]),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> syn:lookup(scope_ab, "scope_a") end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode1, syn, lookup, [scope_ab, "scope_a"]) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, lookup, [scope_ab, "scope_a"])),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> syn:lookup(scope_ab, "scope_a_alias") end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode1, syn, lookup, [scope_ab, "scope_a_alias"]) end
    ),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, lookup, [scope_ab, "scope_a_alias"])),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:lookup(scope_bc, {remote_scoped_bc})),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode1, syn, lookup, [scope_bc, {remote_scoped_bc}]) end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode2, syn, lookup, [scope_bc, {remote_scoped_bc}]) end
    ),
    1 = syn:registry_count(scope_ab),
    0 = syn:registry_count(scope_ab, node()),
    1 = syn:registry_count(scope_ab, SlaveNode1),
    0 = syn:registry_count(scope_ab, SlaveNode2),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:registry_count(scope_bc)),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:registry_count(scope_bc, node())),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:registry_count(scope_bc, SlaveNode1)),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:registry_count(scope_bc, SlaveNode2)),
    1 = rpc:call(SlaveNode1, syn, registry_count, [scope_ab]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_ab, node()]),
    1 = rpc:call(SlaveNode1, syn, registry_count, [scope_ab, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_ab, SlaveNode2]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_bc]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_bc, node()]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_bc, SlaveNode2]),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, registry_count, [scope_ab])),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, registry_count, [scope_ab, node()])),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, registry_count, [scope_ab, SlaveNode1])),
    {badrpc, {'EXIT', {{invalid_scope, scope_ab}, _}}} = (catch rpc:call(SlaveNode2, syn, registry_count, [scope_ab, SlaveNode2])),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_bc]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_bc, node()]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_bc, SlaveNode2]),

    %% errors
    {error, undefined} = syn:unregister(scope_ab, {invalid_name}),

    %% (simulate race condition)
    Pid1 = syn_test_suite_helper:start_process(),
    Pid2 = syn_test_suite_helper:start_process(),
    ok = syn:register(scope_ab, <<"my proc">>, Pid1),
    syn_test_suite_helper:assert_wait(
        {Pid1, undefined},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [scope_ab, <<"my proc">>]) end
    ),
    remove_from_local_table(scope_ab, <<"my proc">>, Pid1),
    add_to_local_table(scope_ab, <<"my proc">>, Pid2, undefined, 0, undefined),
    {error, race_condition} = rpc:call(SlaveNode1, syn, unregister, [scope_ab, <<"my proc">>]).

three_nodes_register_filter_unknown_node(Config) ->
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
    {syn_registry_scope_bc, SlaveNode1} ! {'3.0', sync_register, <<"proc-name">>, InvalidPid, undefined, os:system_time(millisecond), normal},

    %% check
    undefined = rpc:call(SlaveNode1, syn, lookup, [scope_bc, <<"proc-name">>]).

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

    %% register
    ok = rpc:call(SlaveNode1, syn, register, [scope_all, "proc-1", PidRemoteOn1, "meta-1"]),
    ok = rpc:call(SlaveNode2, syn, register, [scope_all, "proc-2", PidRemoteOn2, "meta-2"]),
    ok = rpc:call(SlaveNode1, syn, register, [scope_bc, "BC-proc-1", PidRemoteOn1, "meta-1"]),
    ok = rpc:call(SlaveNode1, syn, register, [scope_bc, "BC-proc-1 alias", PidRemoteOn1, "meta-1 alias"]),

    %% form full cluster
    ok = syn:start(),
    ok = syn:add_node_to_scopes([scope_all]),

    rpc:call(SlaveNode1, syn_test_suite_helper, connect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node(), SlaveNode1]),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, "meta-1"},
        fun() -> syn:lookup(scope_all, "proc-1") end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, "meta-1"},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [scope_all, "proc-1"]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, "meta-1"},
        fun() -> rpc:call(SlaveNode2, syn, lookup, [scope_all, "proc-1"]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn2, "meta-2"},
        fun() -> syn:lookup(scope_all, "proc-2") end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn2, "meta-2"},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [scope_all, "proc-2"]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn2, "meta-2"},
        fun() -> rpc:call(SlaveNode2, syn, lookup, [scope_all, "proc-2"]) end
    ),
    2 = syn:registry_count(scope_all),
    0 = syn:registry_count(scope_all, node()),
    1 = syn:registry_count(scope_all, SlaveNode1),
    1 = syn:registry_count(scope_all, SlaveNode2),
    2 = rpc:call(SlaveNode1, syn, registry_count, [scope_all]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_all, node()]),
    1 = rpc:call(SlaveNode1, syn, registry_count, [scope_all, SlaveNode1]),
    1 = rpc:call(SlaveNode1, syn, registry_count, [scope_all, SlaveNode2]),
    2 = rpc:call(SlaveNode2, syn, registry_count, [scope_all]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_all, node()]),
    1 = rpc:call(SlaveNode2, syn, registry_count, [scope_all, SlaveNode1]),
    1 = rpc:call(SlaveNode2, syn, registry_count, [scope_all, SlaveNode2]),

    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:lookup(scope_bc, "BC-proc-1")),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, "meta-1"},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [scope_bc, "BC-proc-1"]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, "meta-1"},
        fun() -> rpc:call(SlaveNode2, syn, lookup, [scope_bc, "BC-proc-1"]) end
    ),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:lookup(scope_bc, "BC-proc-1 alias")),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, "meta-1 alias"},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [scope_bc, "BC-proc-1 alias"]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, "meta-1 alias"},
        fun() -> rpc:call(SlaveNode2, syn, lookup, [scope_bc, "BC-proc-1 alias"]) end
    ),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:registry_count(scope_bc)),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:registry_count(scope_bc, node())),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:registry_count(scope_bc, SlaveNode1)),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:registry_count(scope_bc, SlaveNode2)),
    2 = rpc:call(SlaveNode1, syn, registry_count, [scope_bc]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_bc, node()]),
    2 = rpc:call(SlaveNode1, syn, registry_count, [scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_bc, SlaveNode2]),
    2 = rpc:call(SlaveNode2, syn, registry_count, [scope_bc]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_bc, node()]),
    2 = rpc:call(SlaveNode2, syn, registry_count, [scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_bc, SlaveNode2]),

    %% partial netsplit (1 cannot see 2)
    rpc:call(SlaveNode1, syn_test_suite_helper, disconnect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node()]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node()]),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, "meta-1"},
        fun() -> syn:lookup(scope_all, "proc-1") end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, "meta-1"},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [scope_all, "proc-1"]) end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode2, syn, lookup, [scope_all, "proc-1"]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn2, "meta-2"},
        fun() -> syn:lookup(scope_all, "proc-2") end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode1, syn, lookup, [scope_all, "proc-2"]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn2, "meta-2"},
        fun() -> rpc:call(SlaveNode2, syn, lookup, [scope_all, "proc-2"]) end
    ),
    2 = syn:registry_count(scope_all),
    0 = syn:registry_count(scope_all, node()),
    1 = syn:registry_count(scope_all, SlaveNode1),
    1 = syn:registry_count(scope_all, SlaveNode2),
    1 = rpc:call(SlaveNode1, syn, registry_count, [scope_all]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_all, node()]),
    1 = rpc:call(SlaveNode1, syn, registry_count, [scope_all, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_all, SlaveNode2]),
    1 = rpc:call(SlaveNode2, syn, registry_count, [scope_all]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_all, node()]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_all, SlaveNode1]),
    1 = rpc:call(SlaveNode2, syn, registry_count, [scope_all, SlaveNode2]),

    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:lookup(scope_bc, "BC-proc-1")),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, "meta-1"},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [scope_bc, "BC-proc-1"]) end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode2, syn, lookup, [scope_bc, "BC-proc-1"]) end
    ),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:lookup(scope_bc, "BC-proc-1 alias")),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, "meta-1 alias"},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [scope_bc, "BC-proc-1 alias"]) end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode2, syn, lookup, [scope_bc, "BC-proc-1 alias"]) end
    ),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:registry_count(scope_bc)),
    2 = rpc:call(SlaveNode1, syn, registry_count, [scope_bc]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_bc, node()]),
    2 = rpc:call(SlaveNode1, syn, registry_count, [scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_bc, SlaveNode2]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_bc]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_bc, node()]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_bc, SlaveNode2]),

    %% re-join
    rpc:call(SlaveNode1, syn_test_suite_helper, connect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node(), SlaveNode1]),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, "meta-1"},
        fun() -> syn:lookup(scope_all, "proc-1") end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, "meta-1"},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [scope_all, "proc-1"]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, "meta-1"},
        fun() -> rpc:call(SlaveNode2, syn, lookup, [scope_all, "proc-1"]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn2, "meta-2"},
        fun() -> syn:lookup(scope_all, "proc-2") end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn2, "meta-2"},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [scope_all, "proc-2"]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn2, "meta-2"},
        fun() -> rpc:call(SlaveNode2, syn, lookup, [scope_all, "proc-2"]) end
    ),
    2 = syn:registry_count(scope_all),
    0 = syn:registry_count(scope_all, node()),
    1 = syn:registry_count(scope_all, SlaveNode1),
    1 = syn:registry_count(scope_all, SlaveNode2),
    2 = rpc:call(SlaveNode1, syn, registry_count, [scope_all]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_all, node()]),
    1 = rpc:call(SlaveNode1, syn, registry_count, [scope_all, SlaveNode1]),
    1 = rpc:call(SlaveNode1, syn, registry_count, [scope_all, SlaveNode2]),
    2 = rpc:call(SlaveNode2, syn, registry_count, [scope_all]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_all, node()]),
    1 = rpc:call(SlaveNode2, syn, registry_count, [scope_all, SlaveNode1]),
    1 = rpc:call(SlaveNode2, syn, registry_count, [scope_all, SlaveNode2]),

    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:lookup(scope_bc, "BC-proc-1")),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, "meta-1"},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [scope_bc, "BC-proc-1"]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, "meta-1"},
        fun() -> rpc:call(SlaveNode2, syn, lookup, [scope_bc, "BC-proc-1"]) end
    ),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:lookup(scope_bc, "BC-proc-1 alias")),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, "meta-1 alias"},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [scope_bc, "BC-proc-1 alias"]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidRemoteOn1, "meta-1 alias"},
        fun() -> rpc:call(SlaveNode2, syn, lookup, [scope_bc, "BC-proc-1 alias"]) end
    ),
    {'EXIT', {{invalid_scope, scope_bc}, _}} = (catch syn:registry_count(scope_bc)),
    2 = rpc:call(SlaveNode1, syn, registry_count, [scope_bc]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_bc, node()]),
    2 = rpc:call(SlaveNode1, syn, registry_count, [scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_bc, SlaveNode2]),
    2 = rpc:call(SlaveNode2, syn, registry_count, [scope_bc]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_bc, node()]),
    2 = rpc:call(SlaveNode2, syn, registry_count, [scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_bc, SlaveNode2]).

three_nodes_cluster_conflicts(Config) ->
    %% get slaves
    SlaveNode1 = proplists:get_value(syn_slave_1, Config),
    SlaveNode2 = proplists:get_value(syn_slave_2, Config),

    %% start syn on nodes
    ok = syn:start(),
    ok = rpc:call(SlaveNode1, syn, start, []),
    ok = rpc:call(SlaveNode2, syn, start, []),

    %% add scopes
    ok = syn:add_node_to_scopes([scope_all]),
    ok = rpc:call(SlaveNode1, syn, add_node_to_scopes, [[scope_all, scope_bc]]),
    ok = rpc:call(SlaveNode2, syn, add_node_to_scopes, [[scope_all, scope_bc]]),

    %% partial netsplit (1 cannot see 2)
    rpc:call(SlaveNode1, syn_test_suite_helper, disconnect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node()]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node()]),

    %% start conflict processes
    Pid2RemoteOn1 = syn_test_suite_helper:start_process(SlaveNode1),
    Pid2RemoteOn2 = syn_test_suite_helper:start_process(SlaveNode2),

    %% --> conflict by netsplit
    ok = rpc:call(SlaveNode1, syn, register, [scope_all, "proc-confict-by-netsplit", Pid2RemoteOn1, "meta-1"]),
    ok = rpc:call(SlaveNode2, syn, register, [scope_all, "proc-confict-by-netsplit", Pid2RemoteOn2, "meta-2"]),
    ok = rpc:call(SlaveNode1, syn, register, [scope_bc, "proc-confict-by-netsplit-scoped", Pid2RemoteOn1, "meta-1"]),
    ok = rpc:call(SlaveNode2, syn, register, [scope_bc, "proc-confict-by-netsplit-scoped", Pid2RemoteOn2, "meta-2"]),

    %% re-join
    rpc:call(SlaveNode1, syn_test_suite_helper, connect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node(), SlaveNode1]),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        {Pid2RemoteOn2, "meta-2"},
        fun() -> syn:lookup(scope_all, "proc-confict-by-netsplit") end
    ),
    syn_test_suite_helper:assert_wait(
        {Pid2RemoteOn2, "meta-2"},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [scope_all, "proc-confict-by-netsplit"]) end
    ),
    syn_test_suite_helper:assert_wait(
        {Pid2RemoteOn2, "meta-2"},
        fun() -> rpc:call(SlaveNode2, syn, lookup, [scope_all, "proc-confict-by-netsplit"]) end
    ),
    1 = syn:registry_count(scope_all),
    0 = syn:registry_count(scope_all, node()),
    0 = syn:registry_count(scope_all, SlaveNode1),
    1 = syn:registry_count(scope_all, SlaveNode2),
    1 = rpc:call(SlaveNode1, syn, registry_count, [scope_all]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_all, node()]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_all, SlaveNode1]),
    1 = rpc:call(SlaveNode1, syn, registry_count, [scope_all, SlaveNode2]),
    1 = rpc:call(SlaveNode2, syn, registry_count, [scope_all]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_all, node()]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_all, SlaveNode1]),
    1 = rpc:call(SlaveNode2, syn, registry_count, [scope_all, SlaveNode2]),
    syn_test_suite_helper:assert_wait(
        {Pid2RemoteOn2, "meta-2"},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [scope_bc, "proc-confict-by-netsplit-scoped"]) end
    ),
    syn_test_suite_helper:assert_wait(
        {Pid2RemoteOn2, "meta-2"},
        fun() -> rpc:call(SlaveNode2, syn, lookup, [scope_bc, "proc-confict-by-netsplit-scoped"]) end
    ),
    1 = rpc:call(SlaveNode1, syn, registry_count, [scope_bc]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_bc, node()]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_bc, SlaveNode1]),
    1 = rpc:call(SlaveNode1, syn, registry_count, [scope_bc, SlaveNode2]),
    1 = rpc:call(SlaveNode2, syn, registry_count, [scope_bc]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_bc, node()]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_bc, SlaveNode1]),
    1 = rpc:call(SlaveNode2, syn, registry_count, [scope_bc, SlaveNode2]),

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
    ok = syn:register(scope_all, <<"my proc">>, PidOnMaster, "meta-1"),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        {PidOnMaster, "meta-1"},
        fun() -> syn:lookup(scope_all, <<"my proc">>) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidOnMaster, "meta-1"},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [scope_all, <<"my proc">>]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidOnMaster, "meta-1"},
        fun() -> rpc:call(SlaveNode2, syn, lookup, [scope_all, <<"my proc">>]) end
    ),
    %% NB: we can't check for process alive here because we injected the conflicting process in the DB
    %% -> it's not actually monitored
    ok.

three_nodes_custom_event_handler_reg_unreg(Config) ->
    %% get slaves
    SlaveNode1 = proplists:get_value(syn_slave_1, Config),
    SlaveNode2 = proplists:get_value(syn_slave_2, Config),

    %% add custom handler for callbacks (using ENV)
    rpc:call(SlaveNode2, application, set_env, [syn, event_handler, syn_test_event_handler_callbacks]),

    %% start syn on nodes
    ok = syn:start(),
    ok = rpc:call(SlaveNode1, syn, start, []),
    ok = rpc:call(SlaveNode2, syn, start, []),

    %% add custom handler for callbacks (using method call)
    syn:set_event_handler(syn_test_event_handler_callbacks),
    rpc:call(SlaveNode1, syn, set_event_handler, [syn_test_event_handler_callbacks]),

    %% add scopes
    ok = syn:add_node_to_scopes([scope_all]),
    ok = rpc:call(SlaveNode1, syn, add_node_to_scopes, [[scope_all]]),
    ok = rpc:call(SlaveNode2, syn, add_node_to_scopes, [[scope_all]]),

    %% init
    LocalNode = node(),

    %% start process
    Pid = syn_test_suite_helper:start_process(),
    Pid2 = syn_test_suite_helper:start_process(),

    %% ---> on registration
    ok = syn:register(scope_all, "proc-handler", Pid, {recipient, self(), <<"meta">>}),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_registered, LocalNode, scope_all, "proc-handler", Pid, <<"meta">>, normal},
        {on_process_registered, SlaveNode1, scope_all, "proc-handler", Pid, <<"meta">>, normal},
        {on_process_registered, SlaveNode2, scope_all, "proc-handler", Pid, <<"meta">>, normal}
    ]),

    %% registration from another node
    ok = rpc:call(SlaveNode1, syn, register, [scope_all, "proc-handler-2", Pid2, {recipient, self(), <<"meta-for-2">>}]),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_registered, LocalNode, scope_all, "proc-handler-2", Pid2, <<"meta-for-2">>, normal},
        {on_process_registered, SlaveNode1, scope_all, "proc-handler-2", Pid2, <<"meta-for-2">>, normal},
        {on_process_registered, SlaveNode2, scope_all, "proc-handler-2", Pid2, <<"meta-for-2">>, normal}
    ]),

    %% ---> on meta update
    ok = syn:register(scope_all, "proc-handler", Pid, {recipient, self(), <<"new-meta">>}),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_registry_process_updated, LocalNode, scope_all, "proc-handler", Pid, <<"new-meta">>, normal},
        {on_registry_process_updated, SlaveNode1, scope_all, "proc-handler", Pid, <<"new-meta">>, normal},
        {on_registry_process_updated, SlaveNode2, scope_all, "proc-handler", Pid, <<"new-meta">>, normal}
    ]),

    %% meta update from another node
    ok = rpc:call(SlaveNode1, syn, register, [scope_all, "proc-handler-2", Pid2, {recipient, self(), <<"meta-for-2-update">>}]),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_registry_process_updated, LocalNode, scope_all, "proc-handler-2", Pid2, <<"meta-for-2-update">>, normal},
        {on_registry_process_updated, SlaveNode1, scope_all, "proc-handler-2", Pid2, <<"meta-for-2-update">>, normal},
        {on_registry_process_updated, SlaveNode2, scope_all, "proc-handler-2", Pid2, <<"meta-for-2-update">>, normal}
    ]),

    %% ---> on unregister
    ok = syn:unregister(scope_all, "proc-handler"),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_unregistered, LocalNode, scope_all, "proc-handler", Pid, <<"new-meta">>, normal},
        {on_process_unregistered, SlaveNode1, scope_all, "proc-handler", Pid, <<"new-meta">>, normal},
        {on_process_unregistered, SlaveNode2, scope_all, "proc-handler", Pid, <<"new-meta">>, normal}
    ]),

    %% unregister from another node
    ok = rpc:call(SlaveNode1, syn, unregister, [scope_all, "proc-handler-2"]),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_unregistered, LocalNode, scope_all, "proc-handler-2", Pid2, <<"meta-for-2-update">>, normal},
        {on_process_unregistered, SlaveNode1, scope_all, "proc-handler-2", Pid2, <<"meta-for-2-update">>, normal},
        {on_process_unregistered, SlaveNode2, scope_all, "proc-handler-2", Pid2, <<"meta-for-2-update">>, normal}
    ]),

    %% clean & check
    syn_test_suite_helper:kill_process(Pid),
    %% no messages
    syn_test_suite_helper:assert_empty_queue(),

    %% ---> after a netsplit
    PidRemoteOn1 = syn_test_suite_helper:start_process(SlaveNode1),
    ok = syn:register(scope_all, remote_on_1, PidRemoteOn1, {recipient, self(), <<"netsplit">>}),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_registered, LocalNode, scope_all, remote_on_1, PidRemoteOn1, <<"netsplit">>, normal},
        {on_process_registered, SlaveNode1, scope_all, remote_on_1, PidRemoteOn1, <<"netsplit">>, normal},
        {on_process_registered, SlaveNode2, scope_all, remote_on_1, PidRemoteOn1, <<"netsplit">>, normal}
    ]),

    %% partial netsplit (1 cannot see 2)
    rpc:call(SlaveNode1, syn_test_suite_helper, disconnect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node()]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node()]),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_unregistered, SlaveNode2, scope_all, remote_on_1, PidRemoteOn1, <<"netsplit">>, {syn_remote_scope_node_down, scope_all, SlaveNode1}}
    ]),

    %% ---> after a re-join
    %% re-join
    rpc:call(SlaveNode1, syn_test_suite_helper, connect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node(), SlaveNode1]),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_registered, SlaveNode2, scope_all, remote_on_1, PidRemoteOn1, <<"netsplit">>, {syn_remote_scope_node_up, scope_all, SlaveNode1}}
    ]),

    %% clean
    syn_test_suite_helper:kill_process(PidRemoteOn1),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_unregistered, LocalNode, scope_all, remote_on_1, PidRemoteOn1, <<"netsplit">>, killed},
        {on_process_unregistered, SlaveNode1, scope_all, remote_on_1, PidRemoteOn1, <<"netsplit">>, killed},
        {on_process_unregistered, SlaveNode2, scope_all, remote_on_1, PidRemoteOn1, <<"netsplit">>, killed}
    ]),

    %% ---> after a conflict resolution
    %% partial netsplit (1 cannot see 2)
    rpc:call(SlaveNode1, syn_test_suite_helper, disconnect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node()]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node()]),

    %% start conflict processes
    Pid2RemoteOn1 = syn_test_suite_helper:start_process(SlaveNode1),
    Pid2RemoteOn2 = syn_test_suite_helper:start_process(SlaveNode2),

    ok = rpc:call(SlaveNode1, syn, register, [scope_all, "proc-confict", Pid2RemoteOn1, {recipient, self(), <<"meta-1">>}]),
    ok = rpc:call(SlaveNode2, syn, register, [scope_all, "proc-confict", Pid2RemoteOn2, {recipient, self(), <<"meta-2">>}]),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_registered, LocalNode, scope_all, "proc-confict", Pid2RemoteOn1, <<"meta-1">>, normal},
        {on_process_unregistered, LocalNode, scope_all, "proc-confict", Pid2RemoteOn1, <<"meta-1">>, normal},
        {on_process_registered, LocalNode, scope_all, "proc-confict", Pid2RemoteOn2, <<"meta-2">>, normal},
        {on_process_registered, SlaveNode1, scope_all, "proc-confict", Pid2RemoteOn1, <<"meta-1">>, normal},
        {on_process_registered, SlaveNode2, scope_all, "proc-confict", Pid2RemoteOn2, <<"meta-2">>, normal}
    ]),

    %% re-join
    rpc:call(SlaveNode1, syn_test_suite_helper, connect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node(), SlaveNode1]),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_unregistered, SlaveNode1, scope_all, "proc-confict", Pid2RemoteOn1, <<"meta-1">>, syn_conflict_resolution},
        {on_process_registered, SlaveNode1, scope_all, "proc-confict", Pid2RemoteOn2, <<"meta-2">>, syn_conflict_resolution}
    ]),

    %% kill
    syn_test_suite_helper:kill_process(Pid2RemoteOn1),
    syn_test_suite_helper:kill_process(Pid2RemoteOn2),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_unregistered, LocalNode, scope_all, "proc-confict", Pid2RemoteOn2, <<"meta-2">>, killed},
        {on_process_unregistered, SlaveNode1, scope_all, "proc-confict", Pid2RemoteOn2, <<"meta-2">>, killed},
        {on_process_unregistered, SlaveNode2, scope_all, "proc-confict", Pid2RemoteOn2, <<"meta-2">>, killed}
    ]),

    %% ---> don't call on monitor rebuild
    %% crash the scope process on local
    syn_test_suite_helper:kill_process(syn_registry_scope_all),
    syn_test_suite_helper:wait_process_name_ready(syn_registry_scope_all),

    %% no messages
    syn_test_suite_helper:assert_empty_queue(),

    %% ---> call if process died during the scope process crash
    TransientPid = syn_test_suite_helper:start_process(),
    ok = syn:register(scope_all, "transient-pid", TransientPid, {recipient, self(), "transient-meta"}),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_registered, LocalNode, scope_all, "transient-pid", TransientPid, "transient-meta", normal},
        {on_process_registered, SlaveNode1, scope_all, "transient-pid", TransientPid, "transient-meta", normal},
        {on_process_registered, SlaveNode2, scope_all, "transient-pid", TransientPid, "transient-meta", normal}
    ]),

    %% crash the scope process & fake a died process on local
    InvalidPid = list_to_pid("<0.9999.0>"),
    add_to_local_table(scope_all, "invalid-pid", InvalidPid, {recipient, self(), "invalid-meta"}, 0, undefined),
    syn_test_suite_helper:kill_process(syn_registry_scope_all),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_unregistered, LocalNode, scope_all, "invalid-pid", InvalidPid, "invalid-meta", undefined},
        {on_process_unregistered, SlaveNode1, scope_all, "transient-pid", TransientPid, "transient-meta", {syn_remote_scope_node_down, scope_all, LocalNode}},
        {on_process_unregistered, SlaveNode2, scope_all, "transient-pid", TransientPid, "transient-meta", {syn_remote_scope_node_down, scope_all, LocalNode}},
        {on_process_registered, SlaveNode1, scope_all, "transient-pid", TransientPid, "transient-meta", {syn_remote_scope_node_up, scope_all, LocalNode}},
        {on_process_registered, SlaveNode2, scope_all, "transient-pid", TransientPid, "transient-meta", {syn_remote_scope_node_up, scope_all, LocalNode}}
    ]).

three_nodes_custom_event_handler_conflict_resolution(Config) ->
    %% get slaves
    SlaveNode1 = proplists:get_value(syn_slave_1, Config),
    SlaveNode2 = proplists:get_value(syn_slave_2, Config),

    %% add custom handler for resolution & scopes (using ENV)
    rpc:call(SlaveNode2, application, set_env, [syn, event_handler, syn_test_event_handler_resolution]),
    rpc:call(SlaveNode2, application, set_env, [syn, scopes, [scope_all, scope_bc]]),

    %% start syn on nodes
    ok = syn:start(),
    ok = rpc:call(SlaveNode1, syn, start, []),
    ok = rpc:call(SlaveNode2, syn, start, []),

    %% add custom handler for resolution (using method call)
    syn:set_event_handler(syn_test_event_handler_resolution),
    rpc:call(SlaveNode1, syn, set_event_handler, [syn_test_event_handler_resolution]),

    %% add scopes
    ok = syn:add_node_to_scopes([scope_all]),
    ok = rpc:call(SlaveNode1, syn, add_node_to_scopes, [[scope_all, scope_bc]]),

    %% current node
    TestPid = self(),
    LocalNode = node(),

    %% partial netsplit (1 cannot see 2)
    rpc:call(SlaveNode1, syn_test_suite_helper, disconnect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node()]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node()]),

    %% start conflict processes
    PidOn1 = syn_test_suite_helper:start_process(SlaveNode1),
    PidOn2 = syn_test_suite_helper:start_process(SlaveNode2),

    %% --> conflict by netsplit
    ok = rpc:call(SlaveNode1, syn, register, [scope_all, "proc-confict-by-netsplit-custom", PidOn1, {recipient, TestPid, keepthis}]),
    ok = rpc:call(SlaveNode2, syn, register, [scope_all, "proc-confict-by-netsplit-custom", PidOn2, {recipient, TestPid, "meta-2"}]),
    ok = rpc:call(SlaveNode1, syn, register, [scope_bc, "proc-confict-by-netsplit-scoped-custom", PidOn1, {recipient, TestPid, keepthis}]),
    ok = rpc:call(SlaveNode2, syn, register, [scope_bc, "proc-confict-by-netsplit-scoped-custom", PidOn2, {recipient, TestPid, "meta-2"}]),

    %% check callbacks
    syn_test_suite_helper:assert_received_messages([
        {on_process_registered, LocalNode, scope_all, "proc-confict-by-netsplit-custom", PidOn1, keepthis, normal},
        {on_process_unregistered, LocalNode, scope_all, "proc-confict-by-netsplit-custom", PidOn1, keepthis, normal},
        {on_process_registered, LocalNode, scope_all, "proc-confict-by-netsplit-custom", PidOn2, "meta-2", normal},

        {on_process_registered, SlaveNode1, scope_all, "proc-confict-by-netsplit-custom", PidOn1, keepthis, normal},
        {on_process_registered, SlaveNode2, scope_all, "proc-confict-by-netsplit-custom", PidOn2, "meta-2", normal},
        {on_process_registered, SlaveNode1, scope_bc, "proc-confict-by-netsplit-scoped-custom", PidOn1, keepthis, normal},
        {on_process_registered, SlaveNode2, scope_bc, "proc-confict-by-netsplit-scoped-custom", PidOn2, "meta-2", normal}
    ]),

    %% re-join
    rpc:call(SlaveNode1, syn_test_suite_helper, connect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node(), SlaveNode1]),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        {PidOn1, {recipient, TestPid, keepthis}},
        fun() -> syn:lookup(scope_all, "proc-confict-by-netsplit-custom") end
    ),
    syn_test_suite_helper:assert_wait(
        {PidOn1, {recipient, TestPid, keepthis}},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [scope_all, "proc-confict-by-netsplit-custom"]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidOn1, {recipient, TestPid, keepthis}},
        fun() -> rpc:call(SlaveNode2, syn, lookup, [scope_all, "proc-confict-by-netsplit-custom"]) end
    ),
    1 = syn:registry_count(scope_all),
    0 = syn:registry_count(scope_all, node()),
    1 = syn:registry_count(scope_all, SlaveNode1),
    0 = syn:registry_count(scope_all, SlaveNode2),
    1 = rpc:call(SlaveNode1, syn, registry_count, [scope_all]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_all, node()]),
    1 = rpc:call(SlaveNode1, syn, registry_count, [scope_all, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_all, SlaveNode2]),
    1 = rpc:call(SlaveNode2, syn, registry_count, [scope_all]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_all, node()]),
    1 = rpc:call(SlaveNode2, syn, registry_count, [scope_all, SlaveNode1]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_all, SlaveNode2]),
    syn_test_suite_helper:assert_wait(
        {PidOn1, {recipient, TestPid, keepthis}},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [scope_bc, "proc-confict-by-netsplit-scoped-custom"]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidOn1, {recipient, TestPid, keepthis}},
        fun() -> rpc:call(SlaveNode2, syn, lookup, [scope_bc, "proc-confict-by-netsplit-scoped-custom"]) end
    ),
    1 = rpc:call(SlaveNode1, syn, registry_count, [scope_bc]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_bc, node()]),
    1 = rpc:call(SlaveNode1, syn, registry_count, [scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_bc, SlaveNode2]),
    1 = rpc:call(SlaveNode2, syn, registry_count, [scope_bc]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_bc, node()]),
    1 = rpc:call(SlaveNode2, syn, registry_count, [scope_bc, SlaveNode1]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_bc, SlaveNode2]),

    syn_test_suite_helper:assert_received_messages([
        {on_process_unregistered, LocalNode, scope_all, "proc-confict-by-netsplit-custom", PidOn2, "meta-2", syn_conflict_resolution},
        {on_process_registered, LocalNode, scope_all, "proc-confict-by-netsplit-custom", PidOn1, keepthis, syn_conflict_resolution},

        {on_process_unregistered, SlaveNode2, scope_all, "proc-confict-by-netsplit-custom", PidOn2, "meta-2", syn_conflict_resolution},
        {on_process_registered, SlaveNode2, scope_all, "proc-confict-by-netsplit-custom", PidOn1, keepthis, syn_conflict_resolution},
        {on_process_unregistered, SlaveNode2, scope_bc, "proc-confict-by-netsplit-scoped-custom", PidOn2, "meta-2", syn_conflict_resolution},
        {on_process_registered, SlaveNode2, scope_bc, "proc-confict-by-netsplit-scoped-custom", PidOn1, keepthis, syn_conflict_resolution}
    ]),

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
    syn:unregister(scope_all, "proc-confict-by-netsplit-custom"),
    ok = rpc:call(SlaveNode1, syn, unregister, [scope_bc, "proc-confict-by-netsplit-scoped-custom"]),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> syn:lookup(scope_all, "proc-confict-by-netsplit-custom") end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode1, syn, lookup, [scope_all, "proc-confict-by-netsplit-custom"]) end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode2, syn, lookup, [scope_all, "proc-confict-by-netsplit-custom"]) end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode1, syn, lookup, [scope_bc, "proc-confict-by-netsplit-scoped-custom"]) end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode2, syn, lookup, [scope_bc, "proc-confict-by-netsplit-scoped-custom"]) end
    ),

    %% check callbacks
    syn_test_suite_helper:assert_received_messages([
        {on_process_unregistered, LocalNode, scope_all, "proc-confict-by-netsplit-custom", PidOn1, keepthis, normal},
        {on_process_unregistered, SlaveNode1, scope_all, "proc-confict-by-netsplit-custom", PidOn1, keepthis, normal},
        {on_process_unregistered, SlaveNode2, scope_all, "proc-confict-by-netsplit-custom", PidOn1, keepthis, normal},
        {on_process_unregistered, SlaveNode1, scope_bc, "proc-confict-by-netsplit-scoped-custom", PidOn1, keepthis, normal},
        {on_process_unregistered, SlaveNode2, scope_bc, "proc-confict-by-netsplit-scoped-custom", PidOn1, keepthis, normal}
    ]),

    %% --> conflict by netsplit, which returns invalid pid
    %% partial netsplit (1 cannot see 2)
    rpc:call(SlaveNode1, syn_test_suite_helper, disconnect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node()]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node()]),

    %% register with meta with no 'keepthis' element
    ok = rpc:call(SlaveNode1, syn, register, [scope_all, "proc-confict-by-netsplit-custom-other-pid", PidOn1, {recipient, TestPid, "meta-1"}]),
    ok = rpc:call(SlaveNode2, syn, register, [scope_all, "proc-confict-by-netsplit-custom-other-pid", PidOn2, {recipient, TestPid, "meta-2"}]),

    %% check callbacks
    syn_test_suite_helper:assert_received_messages([
        {on_process_registered, LocalNode, scope_all, "proc-confict-by-netsplit-custom-other-pid", PidOn1, "meta-1", normal},
        {on_process_unregistered, LocalNode, scope_all, "proc-confict-by-netsplit-custom-other-pid", PidOn1, "meta-1", normal},
        {on_process_registered, LocalNode, scope_all, "proc-confict-by-netsplit-custom-other-pid", PidOn2, "meta-2", normal},

        {on_process_registered, SlaveNode1, scope_all, "proc-confict-by-netsplit-custom-other-pid", PidOn1, "meta-1", normal},
        {on_process_registered, SlaveNode2, scope_all, "proc-confict-by-netsplit-custom-other-pid", PidOn2, "meta-2", normal}
    ]),

    %% re-join
    rpc:call(SlaveNode1, syn_test_suite_helper, connect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node(), SlaveNode1]),

    %% retrieve (names get freed)
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> syn:lookup(scope_all, "proc-confict-by-netsplit-custom-other-pid") end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode1, syn, lookup, [scope_all, "proc-confict-by-netsplit-custom-other-pid"]) end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode2, syn, lookup, [scope_all, "proc-confict-by-netsplit-custom-other-pid"]) end
    ),
    0 = syn:registry_count(scope_all),
    0 = syn:registry_count(scope_all, node()),
    0 = syn:registry_count(scope_all, SlaveNode1),
    0 = syn:registry_count(scope_all, SlaveNode2),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_all]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_all, node()]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_all, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_all, SlaveNode2]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_all]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_all, node()]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_all, SlaveNode1]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_all, SlaveNode2]),

    %% check callbacks
    syn_test_suite_helper:assert_received_messages([
        {on_process_unregistered, LocalNode, scope_all, "proc-confict-by-netsplit-custom-other-pid", PidOn2, "meta-2", syn_conflict_resolution},
        {on_process_unregistered, SlaveNode1, scope_all, "proc-confict-by-netsplit-custom-other-pid", PidOn1, "meta-1", syn_conflict_resolution},
        {on_process_unregistered, SlaveNode2, scope_all, "proc-confict-by-netsplit-custom-other-pid", PidOn2, "meta-2", syn_conflict_resolution}
    ]),

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
    ok = rpc:call(SlaveNode1, syn, register, [scope_all, "proc-confict-by-netsplit-custom-crash", PidOn1, {recipient, TestPid, crash}]),
    ok = rpc:call(SlaveNode2, syn, register, [scope_all, "proc-confict-by-netsplit-custom-crash", PidOn2, {recipient, TestPid, crash}]),

    %% check callbacks
    syn_test_suite_helper:assert_received_messages([
        {on_process_registered, LocalNode, scope_all, "proc-confict-by-netsplit-custom-crash", PidOn1, crash, normal},
        {on_process_unregistered, LocalNode, scope_all, "proc-confict-by-netsplit-custom-crash", PidOn1, crash, normal},
        {on_process_registered, LocalNode, scope_all, "proc-confict-by-netsplit-custom-crash", PidOn2, crash, normal},

        {on_process_registered, SlaveNode1, scope_all, "proc-confict-by-netsplit-custom-crash", PidOn1, crash, normal},
        {on_process_registered, SlaveNode2, scope_all, "proc-confict-by-netsplit-custom-crash", PidOn2, crash, normal}
    ]),

    %% re-join
    rpc:call(SlaveNode1, syn_test_suite_helper, connect_node, [SlaveNode2]),
    syn_test_suite_helper:assert_cluster(node(), [SlaveNode1, SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode1, [node(), SlaveNode2]),
    syn_test_suite_helper:assert_cluster(SlaveNode2, [node(), SlaveNode1]),

    %% retrieve (names get freed)
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> syn:lookup(scope_all, "proc-confict-by-netsplit-custom-crash") end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode1, syn, lookup, [scope_all, "proc-confict-by-netsplit-custom-crash"]) end
    ),
    syn_test_suite_helper:assert_wait(
        undefined,
        fun() -> rpc:call(SlaveNode2, syn, lookup, [scope_all, "proc-confict-by-netsplit-custom-crash"]) end
    ),
    0 = syn:registry_count(scope_all),
    0 = syn:registry_count(scope_all, node()),
    0 = syn:registry_count(scope_all, SlaveNode1),
    0 = syn:registry_count(scope_all, SlaveNode2),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_all]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_all, node()]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_all, SlaveNode1]),
    0 = rpc:call(SlaveNode1, syn, registry_count, [scope_all, SlaveNode2]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_all]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_all, node()]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_all, SlaveNode1]),
    0 = rpc:call(SlaveNode2, syn, registry_count, [scope_all, SlaveNode2]),

    %% check callbacks
    syn_test_suite_helper:assert_received_messages([
        {on_process_unregistered, LocalNode, scope_all, "proc-confict-by-netsplit-custom-crash", PidOn2, crash, syn_conflict_resolution},
        {on_process_unregistered, SlaveNode1, scope_all, "proc-confict-by-netsplit-custom-crash", PidOn1, crash, syn_conflict_resolution},
        {on_process_unregistered, SlaveNode2, scope_all, "proc-confict-by-netsplit-custom-crash", PidOn2, crash, syn_conflict_resolution}
    ]),

    %% process alive (discarded process does not get killed with a custom handler)
    syn_test_suite_helper:assert_wait(
        true,
        fun() -> rpc:call(SlaveNode1, erlang, is_process_alive, [PidOn1]) end
    ),
    syn_test_suite_helper:assert_wait(
        true,
        fun() -> rpc:call(SlaveNode2, erlang, is_process_alive, [PidOn2]) end
    ).

three_nodes_update(Config) ->
    %% get slaves
    SlaveNode1 = proplists:get_value(syn_slave_1, Config),
    SlaveNode2 = proplists:get_value(syn_slave_2, Config),

    %% start syn
    ok = syn:start(),
    ok = rpc:call(SlaveNode1, syn, start, []),
    ok = rpc:call(SlaveNode2, syn, start, []),

    %% add scopes
    ok = syn:add_node_to_scopes([scope_all]),
    ok = rpc:call(SlaveNode1, syn, add_node_to_scopes, [[scope_all, scope_bc]]),
    ok = rpc:call(SlaveNode2, syn, add_node_to_scopes, [[scope_all, scope_bc]]),

    %% start processes
    Pid = syn_test_suite_helper:start_process(),
    PidOn1 = syn_test_suite_helper:start_process(SlaveNode1),

    %% init
    TestPid = self(),
    LocalNode = node(),

    %% register
    ok = syn:register(scope_all, "my-proc", Pid, {recipient, TestPid, 10}),

    %% re-register with same data
    ok = syn:register(scope_all, "my-proc", Pid, {recipient, TestPid, 10}),
    ok = rpc:call(SlaveNode1, syn, register, [scope_all, "my-proc", Pid, {recipient, TestPid, 10}]),

    %% add custom handler for resolution (using method call)
    syn:set_event_handler(syn_test_event_handler_callbacks),
    rpc:call(SlaveNode1, syn, set_event_handler, [syn_test_event_handler_callbacks]),
    rpc:call(SlaveNode2, syn, set_event_handler, [syn_test_event_handler_callbacks]),

    %% errors
    {error, undefined} = syn:update_registry(scope_all, "unknown", fun(_IPid, ExistingMeta) -> ExistingMeta end),
    {error, {update_fun, {badarith, _}}} = syn:update_registry(scope_all, "my-proc", fun(_IPid, _IMeta) -> 1/0 end),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        {Pid, {recipient, TestPid, 10}},
        fun() -> syn:lookup(scope_all, "my-proc") end
    ),
    syn_test_suite_helper:assert_wait(
        {Pid, {recipient, TestPid, 10}},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [scope_all, "my-proc"]) end
    ),
    syn_test_suite_helper:assert_wait(
        {Pid, {recipient, TestPid, 10}},
        fun() -> rpc:call(SlaveNode2, syn, lookup, [scope_all, "my-proc"]) end
    ),

    %% update
    {ok, {Pid, {recipient, TestPid, 20}}} = syn:update_registry(scope_all, "my-proc", fun(IPid, {recipient, TestPid0, Count}) ->
        IPid = Pid,
        {recipient, TestPid0, Count * 2}
    end),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        {Pid, {recipient, TestPid, 20}},
        fun() -> syn:lookup(scope_all, "my-proc") end
    ),
    syn_test_suite_helper:assert_wait(
        {Pid, {recipient, TestPid, 20}},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [scope_all, "my-proc"]) end
    ),
    syn_test_suite_helper:assert_wait(
        {Pid, {recipient, TestPid, 20}},
        fun() -> rpc:call(SlaveNode2, syn, lookup, [scope_all, "my-proc"]) end
    ),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_registry_process_updated, LocalNode, scope_all, "my-proc", Pid, 20, normal},
        {on_registry_process_updated, SlaveNode1, scope_all, "my-proc", Pid, 20, normal},
        {on_registry_process_updated, SlaveNode2, scope_all, "my-proc", Pid, 20, normal}
    ]),

    %% register on remote
    ok = syn:register(scope_all, "my-proc-on-1", PidOn1, {recipient, TestPid, 1000}),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_process_registered, LocalNode, scope_all, "my-proc-on-1", PidOn1, 1000, normal},
        {on_process_registered, SlaveNode1, scope_all, "my-proc-on-1", PidOn1, 1000, normal},
        {on_process_registered, SlaveNode2, scope_all, "my-proc-on-1", PidOn1, 1000, normal}
    ]),

    %% update on remote
    {ok, {PidOn1, {recipient, TestPid, 1001}}} = syn:update_registry(scope_all, "my-proc-on-1", fun(_IPid, {recipient, TestPid0, Count}) ->
        {recipient, TestPid0, Count + 1}
    end),

    %% retrieve
    syn_test_suite_helper:assert_wait(
        {PidOn1, {recipient, TestPid, 1001}},
        fun() -> syn:lookup(scope_all, "my-proc-on-1") end
    ),
    syn_test_suite_helper:assert_wait(
        {PidOn1, {recipient, TestPid, 1001}},
        fun() -> rpc:call(SlaveNode1, syn, lookup, [scope_all, "my-proc-on-1"]) end
    ),
    syn_test_suite_helper:assert_wait(
        {PidOn1, {recipient, TestPid, 1001}},
        fun() -> rpc:call(SlaveNode2, syn, lookup, [scope_all, "my-proc-on-1"]) end
    ),

    %% check callbacks called
    syn_test_suite_helper:assert_received_messages([
        {on_registry_process_updated, LocalNode, scope_all, "my-proc-on-1", PidOn1, 1001, normal},
        {on_registry_process_updated, SlaveNode1, scope_all, "my-proc-on-1", PidOn1, 1001, normal},
        {on_registry_process_updated, SlaveNode2, scope_all, "my-proc-on-1", PidOn1, 1001, normal}
    ]).

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

    %% concurrent test
    WorkerFun = fun() ->
        lists:foreach(fun(_) ->
            %% start pid
            Pid = syn_test_suite_helper:start_process(),
            RandomMeta = rand:uniform(99999),
            %% loop
            case syn:register(scope_all, <<"concurrent">>, Pid, RandomMeta) of
                ok ->
                    ok;

                {error, taken} ->
                    case syn:unregister(scope_all, <<"concurrent">>) of
                        {error, undefined} ->
                            ok;
                        {error, race_condition} ->
                            ok;
                        ok ->
                            syn:register(scope_all, <<"concurrent">>, Pid, RandomMeta)
                    end
            end,
            %% random kill
            case rand:uniform(10) of
                1 -> exit(Pid, kill);
                _ -> ok
            end,
            %% random sleep
            RndTime = rand:uniform(30),
            timer:sleep(RndTime)
        end, lists:seq(1, Iterations)),
        TestPid ! {done, node()}
    end,

    %% spawn concurrent
    LocalNode = node(),
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
            ResultPidLocal = syn:lookup(scope_all, <<"concurrent">>),
            ResultPidOn1 = rpc:call(SlaveNode1, syn, lookup, [scope_all, <<"concurrent">>]),
            ResultPidOn2 = rpc:call(SlaveNode2, syn, lookup, [scope_all, <<"concurrent">>]),
            ResultPidOn3 = rpc:call(SlaveNode3, syn, lookup, [scope_all, <<"concurrent">>]),

            %% if unique set is of 1 element then they all contain the same result
            Ordset = ordsets:from_list([ResultPidLocal, ResultPidOn1, ResultPidOn2, ResultPidOn3]),
            ordsets:size(Ordset)
        end
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
