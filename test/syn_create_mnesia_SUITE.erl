-module(syn_create_mnesia_SUITE).

%% callbacks
-export([all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([groups/0, init_per_group/2, end_per_group/2]).

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
    %% get slave node short name
    SlaveNodeShortName = proplists:get_value(slave_node_short_name, Config),
    {ok, SlaveNodeName} = syn_test_suite_helper:start_slave(SlaveNodeShortName),
    %% config
    [
        {slave_node_name, SlaveNodeName}
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
    SlaveNodeName = proplists:get_value(slave_node_name, Config),
    %% clean
    clean_after_test(SlaveNodeName),
    %% stop slave
    syn_test_suite_helper:stop_slave(SlaveNodeName);
end_per_group(_GroupName, _Config) ->
    clean_after_test().

%% ===================================================================
%% Tests
%% ===================================================================
single_node_when_mnesia_is_ram(_Config) ->
    %% set schema location
    application:set_env(mnesia, schema_location, ram),
    %% start
    ok = syn:start(),
    %% check table exists
    true = lists:member(syn_processes_table, mnesia:system_info(tables)).

single_node_when_mnesia_is_opt_disc_no_schema_exists(_Config) ->
    %% set schema location
    application:set_env(mnesia, schema_location, opt_disc),
    %% start
    ok = syn:start(),
    %% check table exists
    true = lists:member(syn_processes_table, mnesia:system_info(tables)).

single_node_when_mnesia_is_opt_disc_schema_exists(_Config) ->
    %% set schema location
    application:set_env(mnesia, schema_location, opt_disc),
    %% create schema
    mnesia:create_schema([node()]),
    %% start
    ok = syn:start(),
    %% check table exists
    true = lists:member(syn_processes_table, mnesia:system_info(tables)).

single_node_when_mnesia_is_disc(_Config) ->
    %% set schema location
    application:set_env(mnesia, schema_location, disc),
    %% create schema
    mnesia:create_schema([node()]),
    %% start
    ok = syn:start(),
    %% check table exists
    true = lists:member(syn_processes_table, mnesia:system_info(tables)).

two_nodes_when_mnesia_is_ram(Config) ->
    %% get slave
    SlaveNodeName = proplists:get_value(slave_node_name, Config),
    %% set schema location
    application:set_env(mnesia, schema_location, ram),
    rpc:call(SlaveNodeName, mnesia, schema_location, [ram]),
    %% start
    ok = syn:start(),
    ok = rpc:call(SlaveNodeName, syn, start, []),
    %% check table exists on local
    true = lists:member(syn_processes_table, mnesia:system_info(tables)),
    %% check table exists on remote
    SlaveNodeMnesiaSystemInfo = rpc:call(SlaveNodeName, mnesia, system_info, [tables]),
    true = rpc:call(SlaveNodeName, lists, member, [syn_processes_table, SlaveNodeMnesiaSystemInfo]).

two_nodes_when_mnesia_is_opt_disc_no_schema_exists(Config) ->
    %% get slave
    SlaveNodeName = proplists:get_value(slave_node_name, Config),
    %% set schema location
    application:set_env(mnesia, schema_location, opt_disc),
    rpc:call(SlaveNodeName, mnesia, schema_location, [opt_disc]),
    %% start
    ok = syn:start(),
    ok = rpc:call(SlaveNodeName, syn, start, []),
    %% check table exists on local
    true = lists:member(syn_processes_table, mnesia:system_info(tables)),
    %% check table exists on remote
    SlaveNodeMnesiaSystemInfo = rpc:call(SlaveNodeName, mnesia, system_info, [tables]),
    true = rpc:call(SlaveNodeName, lists, member, [syn_processes_table, SlaveNodeMnesiaSystemInfo]).

two_nodes_when_mnesia_is_opt_disc_schema_exists(Config) ->
    %% get slave
    SlaveNodeName = proplists:get_value(slave_node_name, Config),
    %% set schema location
    application:set_env(mnesia, schema_location, opt_disc),
    rpc:call(SlaveNodeName, mnesia, schema_location, [opt_disc]),
    %% create schema
    mnesia:create_schema([node(), SlaveNodeName]),
    %% start
    ok = syn:start(),
    ok = rpc:call(SlaveNodeName, syn, start, []),
    %% check table exists on local
    true = lists:member(syn_processes_table, mnesia:system_info(tables)),
    %% check table exists on remote
    SlaveNodeMnesiaSystemInfo = rpc:call(SlaveNodeName, mnesia, system_info, [tables]),
    true = rpc:call(SlaveNodeName, lists, member, [syn_processes_table, SlaveNodeMnesiaSystemInfo]).

two_nodes_when_mnesia_is_disc(Config) ->
    %% get slave
    SlaveNodeName = proplists:get_value(slave_node_name, Config),
    %% set schema location
    application:set_env(mnesia, schema_location, disc),
    rpc:call(SlaveNodeName, mnesia, schema_location, [disc]),
    %% create schema
    mnesia:create_schema([node(), SlaveNodeName]),
    %% start
    ok = syn:start(),
    ok = rpc:call(SlaveNodeName, syn, start, []),
    %% check table exists on local
    true = lists:member(syn_processes_table, mnesia:system_info(tables)),
    %% check table exists on remote
    SlaveNodeMnesiaSystemInfo = rpc:call(SlaveNodeName, mnesia, system_info, [tables]),
    true = rpc:call(SlaveNodeName, lists, member, [syn_processes_table, SlaveNodeMnesiaSystemInfo]).

%% ===================================================================
%% Internal
%% ===================================================================
clean_after_test() ->
    %% stop mnesia
    mnesia:stop(),
    %% delete schema
    mnesia:delete_schema([node()]),
    %% stop syn
    syn:stop().

clean_after_test(SlaveNodeName) ->
    clean_after_test(),
    %% stop mnesia
    rpc:call(SlaveNodeName, mnesia, stop, []),
    %% delete schema
    rpc:call(SlaveNodeName, mnesia, delete_schema, [SlaveNodeName]),
    %% stop syn
    rpc:call(SlaveNodeName, syn, stop, []).
