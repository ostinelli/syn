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
    two_nodes_when_mnesia_is_ram/1
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
        {group, mnesia_creation_single_node}
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
        {mnesia_creation_single_node, [shuffle], [
            single_node_when_mnesia_is_ram,
            single_node_when_mnesia_is_opt_disc_no_schema_exists,
            single_node_when_mnesia_is_opt_disc_schema_exists,
            single_node_when_mnesia_is_disc
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
        {slave_node_bare_name, syn_slave}
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
init_per_group(_GroupName, Config) -> Config.

%% -------------------------------------------------------------------
%% Function: end_per_group(GroupName, Config0) ->
%%				void() | {save_config,Config1}
%% GroupName = atom()
%% Config0 = Config1 = [tuple()]
%% -------------------------------------------------------------------
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
