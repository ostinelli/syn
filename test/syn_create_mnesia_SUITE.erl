%% ==========================================================================================================
%% Syn - A global Process Registry and Process Group manager.
%%
%% The MIT License (MIT)
%%
%% Copyright (c) 2015 Roberto Ostinelli <roberto@ostinelli.net> and Neato Robotics, Inc.
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
-module(syn_create_mnesia_SUITE).

%% callbacks
-export([all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([groups/0, init_per_group/2, end_per_group/2]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% tests
-export([
    single_node_when_mnesia_is_ram/1,
    single_node_when_mnesia_is_opt_disc_no_schema_exists/1,
    single_node_when_mnesia_is_opt_disc_schema_exists/1,
    single_node_when_mnesia_is_disc/1
]).
-export([
    two_nodes_when_mnesia_is_ram/1,
    two_nodes_when_mnesia_is_opt_disc_no_schema_exists/1,
    two_nodes_when_mnesia_is_opt_disc_schema_exists/1,
    two_nodes_when_mnesia_is_disc/1
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
%% Reason = term()
%% -------------------------------------------------------------------
all() ->
    [
        {group, single_node_mnesia_creation},
        {group, two_nodes_mnesia_creation}
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
        {single_node_mnesia_creation, [shuffle], [
            single_node_when_mnesia_is_ram,
            single_node_when_mnesia_is_opt_disc_no_schema_exists,
            single_node_when_mnesia_is_opt_disc_schema_exists,
            single_node_when_mnesia_is_disc
        ]},
        {two_nodes_mnesia_creation, [shuffle], [
            two_nodes_when_mnesia_is_ram,
            two_nodes_when_mnesia_is_opt_disc_no_schema_exists,
            two_nodes_when_mnesia_is_opt_disc_schema_exists,
            two_nodes_when_mnesia_is_disc
        ]}
    ].
%% -------------------------------------------------------------------
%% Function: init_per_suite(Config0) ->
%%				Config1 | {skip,Reason} |
%%              {skip_and_save,Reason,Config1}
%% Config0 = Config1 = [tuple()]
%% Reason = term()
%% -------------------------------------------------------------------
init_per_suite(Config) ->
    %% config
    [
        {slave_node_short_name, syn_slave}
        | Config
    ].

%% -------------------------------------------------------------------
%% Function: end_per_suite(Config0) -> void() | {save_config,Config1}
%% Config0 = Config1 = [tuple()]
%% -------------------------------------------------------------------
end_per_suite(_Config) -> ok.

%% -------------------------------------------------------------------
%% Function: init_per_group(GroupName, Config0) ->
%%				Config1 | {skip,Reason} |
%%              {skip_and_save,Reason,Config1}
%% GroupName = atom()
%% Config0 = Config1 = [tuple()]
%% Reason = term()
%% -------------------------------------------------------------------
init_per_group(two_nodes_mnesia_creation, Config) ->
    %% start slave
    SlaveNodeShortName = proplists:get_value(slave_node_short_name, Config),
    {ok, SlaveNode} = syn_test_suite_helper:start_slave(SlaveNodeShortName),
    %% config
    [
        {slave_node, SlaveNode}
        | Config
    ];
init_per_group(_GroupName, Config) -> Config.

%% -------------------------------------------------------------------
%% Function: end_per_group(GroupName, Config0) ->
%%				void() | {save_config,Config1}
%% GroupName = atom()
%% Config0 = Config1 = [tuple()]
%% -------------------------------------------------------------------
end_per_group(two_nodes_mnesia_creation, Config) ->
    %% get slave node name
    SlaveNodeShortName = proplists:get_value(slave_node_short_name, Config),
    %% stop slave
    syn_test_suite_helper:stop_slave(SlaveNodeShortName);
end_per_group(_GroupName, _Config) ->
    ok.

% ----------------------------------------------------------------------------------------------------------
% Function: init_per_testcase(TestCase, Config0) ->
%				Config1 | {skip,Reason} | {skip_and_save,Reason,Config1}
% TestCase = atom()
% Config0 = Config1 = [tuple()]
% Reason = term()
% ----------------------------------------------------------------------------------------------------------
init_per_testcase(_TestCase, Config) ->
    Config.

% ----------------------------------------------------------------------------------------------------------
% Function: end_per_testcase(TestCase, Config0) ->
%				void() | {save_config,Config1} | {fail,Reason}
% TestCase = atom()
% Config0 = Config1 = [tuple()]
% Reason = term()
% ----------------------------------------------------------------------------------------------------------
end_per_testcase(_TestCase, Config) ->
    %% get slave
    SlaveNode = proplists:get_value(slave_node, Config),
    syn_test_suite_helper:clean_after_test(SlaveNode).

%% ===================================================================
%% Tests
%% ===================================================================
single_node_when_mnesia_is_ram(_Config) ->
    %% set schema location
    application:set_env(mnesia, schema_location, ram),
    %% start
    ok = syn:start(),
    ok = syn:init(),
    %% check table exists
    true = lists:member(syn_registry_table, mnesia:system_info(tables)).

single_node_when_mnesia_is_opt_disc_no_schema_exists(_Config) ->
    %% set schema location
    application:set_env(mnesia, schema_location, opt_disc),
    %% start
    ok = syn:start(),
    ok = syn:init(),
    %% check table exists
    true = lists:member(syn_registry_table, mnesia:system_info(tables)).

single_node_when_mnesia_is_opt_disc_schema_exists(_Config) ->
    %% set schema location
    application:set_env(mnesia, schema_location, opt_disc),
    %% create schema
    mnesia:create_schema([node()]),
    %% start
    ok = syn:start(),
    ok = syn:init(),
    %% check table exists
    true = lists:member(syn_registry_table, mnesia:system_info(tables)).

single_node_when_mnesia_is_disc(_Config) ->
    %% set schema location
    application:set_env(mnesia, schema_location, disc),
    %% create schema
    mnesia:create_schema([node()]),
    %% start
    ok = syn:start(),
    ok = syn:init(),
    %% check table exists
    true = lists:member(syn_registry_table, mnesia:system_info(tables)).

two_nodes_when_mnesia_is_ram(Config) ->
    %% get slave
    SlaveNode = proplists:get_value(slave_node, Config),
    %% set schema location
    application:set_env(mnesia, schema_location, ram),
    rpc:call(SlaveNode, mnesia, schema_location, [ram]),
    %% start
    ok = syn:start(),
    ok = syn:init(),
    ok = rpc:call(SlaveNode, syn, start, []),
    ok = rpc:call(SlaveNode, syn, init, []),
    timer:sleep(100),
    %% check table exists on local
    true = lists:member(syn_registry_table, mnesia:system_info(tables)),
    %% check table exists on remote
    SlaveNodeMnesiaSystemInfo = rpc:call(SlaveNode, mnesia, system_info, [tables]),
    true = rpc:call(SlaveNode, lists, member, [syn_registry_table, SlaveNodeMnesiaSystemInfo]).

two_nodes_when_mnesia_is_opt_disc_no_schema_exists(Config) ->
    %% get slave
    SlaveNode = proplists:get_value(slave_node, Config),
    %% set schema location
    application:set_env(mnesia, schema_location, opt_disc),
    rpc:call(SlaveNode, mnesia, schema_location, [opt_disc]),
    %% start
    ok = syn:start(),
    ok = syn:init(),
    ok = rpc:call(SlaveNode, syn, start, []),
    ok = rpc:call(SlaveNode, syn, init, []),
    timer:sleep(100),
    %% check table exists on local
    true = lists:member(syn_registry_table, mnesia:system_info(tables)),
    %% check table exists on remote
    SlaveNodeMnesiaSystemInfo = rpc:call(SlaveNode, mnesia, system_info, [tables]),
    true = rpc:call(SlaveNode, lists, member, [syn_registry_table, SlaveNodeMnesiaSystemInfo]).

two_nodes_when_mnesia_is_opt_disc_schema_exists(Config) ->
    %% get slave
    SlaveNode = proplists:get_value(slave_node, Config),
    %% set schema location
    application:set_env(mnesia, schema_location, opt_disc),
    rpc:call(SlaveNode, mnesia, schema_location, [opt_disc]),
    %% create schema
    mnesia:create_schema([node(), SlaveNode]),
    %% start
    ok = syn:start(),
    ok = syn:init(),
    ok = rpc:call(SlaveNode, syn, start, []),
    ok = rpc:call(SlaveNode, syn, init, []),
    timer:sleep(100),
    %% check table exists on local
    true = lists:member(syn_registry_table, mnesia:system_info(tables)),
    %% check table exists on remote
    SlaveNodeMnesiaSystemInfo = rpc:call(SlaveNode, mnesia, system_info, [tables]),
    true = rpc:call(SlaveNode, lists, member, [syn_registry_table, SlaveNodeMnesiaSystemInfo]).

two_nodes_when_mnesia_is_disc(Config) ->
    %% get slave
    SlaveNode = proplists:get_value(slave_node, Config),
    %% set schema location
    application:set_env(mnesia, schema_location, disc),
    rpc:call(SlaveNode, mnesia, schema_location, [disc]),
    %% create schema
    mnesia:create_schema([node(), SlaveNode]),
    %% start
    ok = syn:start(),
    ok = syn:init(),
    ok = rpc:call(SlaveNode, syn, start, []),
    ok = rpc:call(SlaveNode, syn, init, []),
    timer:sleep(100),
    %% check table exists on local
    true = lists:member(syn_registry_table, mnesia:system_info(tables)),
    %% check table exists on remote
    SlaveNodeMnesiaSystemInfo = rpc:call(SlaveNode, mnesia, system_info, [tables]),
    true = rpc:call(SlaveNode, lists, member, [syn_registry_table, SlaveNodeMnesiaSystemInfo]).
