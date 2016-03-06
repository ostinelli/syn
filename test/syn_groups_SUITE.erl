%% ==========================================================================================================
%% Syn - A global Process Registry and Process Group manager.
%%
%% The MIT License (MIT)
%%
%% Copyright (c) 2016 Roberto Ostinelli <roberto@ostinelli.net> and Neato Robotics, Inc.
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
    single_node_leave/1,
    single_node_kill/1,
    single_node_publish/1
]).
-export([
    two_nodes_kill/1,
    two_nodes_publish/1
]).

%% internal
-export([recipient_loop/1]).

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
        {group, single_node_process_groups},
        {group, two_nodes_process_groups}
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
        {single_node_process_groups, [shuffle], [
            single_node_leave,
            single_node_kill,
            single_node_publish
        ]},
        {two_nodes_process_groups, [shuffle], [
            two_nodes_kill,
            two_nodes_publish
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
init_per_group(two_nodes_process_groups, Config) ->
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
end_per_group(two_nodes_process_groups, Config) ->
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
single_node_leave(_Config) ->
    %% set schema location
    application:set_env(mnesia, schema_location, ram),
    %% start
    ok = syn:start(),
    ok = syn:init(),
    %% start process
    Pid = syn_test_suite_helper:start_process(),
    %% retrieve
    [] = syn:get_members(<<"my group">>),
    false = syn:member(Pid, <<"my group">>),
    %% join
    ok = syn:join(<<"my group">>, Pid),
    %% retrieve
    [Pid] = syn:get_members(<<"my group">>),
    true = syn:member(Pid, <<"my group">>),
    %% leave
    ok = syn:leave(<<"my group">>, Pid),
    %% retrieve
    [] = syn:get_members(<<"my group">>),
    false = syn:member(Pid, <<"my group">>),
    %% kill process
    syn_test_suite_helper:kill_process(Pid).

single_node_kill(_Config) ->
    %% set schema location
    application:set_env(mnesia, schema_location, ram),
    %% start
    ok = syn:start(),
    ok = syn:init(),
    %% start process
    Pid = syn_test_suite_helper:start_process(),
    %% retrieve
    [] = syn:get_members(<<"my group">>),
    false = syn:member(Pid, <<"my group">>),
    %% join
    ok = syn:join(<<"my group">>, Pid),
    %% retrieve
    [Pid] = syn:get_members(<<"my group">>),
    true = syn:member(Pid, <<"my group">>),
    %% kill process
    syn_test_suite_helper:kill_process(Pid),
    timer:sleep(100),
    %% retrieve
    [] = syn:get_members(<<"my group">>),
    false = syn:member(Pid, <<"my group">>).

single_node_publish(_Config) ->
    %% set schema location
    application:set_env(mnesia, schema_location, ram),
    %% start
    ok = syn:start(),
    ok = syn:init(),
    %% start process
    ResultPid = self(),
    F = fun() -> recipient_loop(ResultPid) end,
    Pid1 = syn_test_suite_helper:start_process(F),
    Pid2 = syn_test_suite_helper:start_process(F),
    %% join
    ok = syn:join(<<"my group">>, Pid1),
    ok = syn:join(<<"my group">>, Pid2),
    %% publish
    syn:publish(<<"my group">>, {test, message}),
    %% check publish was received
    receive
        {received, Pid1, {test, message}} -> ok
    after 2000 ->
        ok = published_message_was_not_received_by_pid1
    end,
    receive
        {received, Pid2, {test, message}} -> ok
    after 2000 ->
        ok = published_message_was_not_received_by_pid2
    end,
    %% kill processes
    syn_test_suite_helper:kill_process(Pid1),
    syn_test_suite_helper:kill_process(Pid2).

two_nodes_kill(Config) ->
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
    %% start processes
    PidLocal = syn_test_suite_helper:start_process(),
    PidSlave = syn_test_suite_helper:start_process(SlaveNode),
    %% retrieve
    [] = syn:get_members(<<"my group">>),
    false = syn:member(PidLocal, <<"my group">>),
    false = syn:member(PidSlave, <<"my group">>),
    [] = rpc:call(SlaveNode, syn, get_members, [<<"my group">>]),
    false = rpc:call(SlaveNode, syn, member, [PidLocal, <<"my group">>]),
    false = rpc:call(SlaveNode, syn, member, [PidSlave, <<"my group">>]),
    %% register
    ok = syn:join(<<"my group">>, PidSlave),
    ok = rpc:call(SlaveNode, syn, join, [<<"my group">>, PidLocal]),
    %% retrieve
    2 = length(syn:get_members(<<"my group">>)),
    true = syn:member(PidLocal, <<"my group">>),
    true = syn:member(PidSlave, <<"my group">>),
    2 = length(rpc:call(SlaveNode, syn, get_members, [<<"my group">>])),
    true = rpc:call(SlaveNode, syn, member, [PidLocal, <<"my group">>]),
    true = rpc:call(SlaveNode, syn, member, [PidSlave, <<"my group">>]),
    %% kill processes
    syn_test_suite_helper:kill_process(PidLocal),
    syn_test_suite_helper:kill_process(PidSlave),
    timer:sleep(100),
    %% retrieve
    [] = syn:get_members(<<"my group">>),
    false = syn:member(PidLocal, <<"my group">>),
    false = syn:member(PidSlave, <<"my group">>),
    [] = rpc:call(SlaveNode, syn, get_members, [<<"my group">>]),
    false = rpc:call(SlaveNode, syn, member, [PidLocal, <<"my group">>]),
    false = rpc:call(SlaveNode, syn, member, [PidSlave, <<"my group">>]).

two_nodes_publish(Config) ->
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
    %% start process
    ResultPid = self(),
    F = fun() -> recipient_loop(ResultPid) end,
    PidLocal = syn_test_suite_helper:start_process(F),
    PidSlave = syn_test_suite_helper:start_process(SlaveNode, F),
    %% register
    ok = syn:join(<<"my group">>, PidSlave),
    ok = rpc:call(SlaveNode, syn, join, [<<"my group">>, PidLocal]),
    %% publish
    syn:publish(<<"my group">>, {test, message}),
    %% check publish was received
    receive
        {received, PidLocal, {test, message}} -> ok
    after 2000 ->
        ok = published_message_was_not_received_by_pidlocal
    end,
    receive
        {received, PidSlave, {test, message}} -> ok
    after 2000 ->
        ok = published_message_was_not_received_by_pidslave
    end,
    %% kill processes
    syn_test_suite_helper:kill_process(PidLocal),
    syn_test_suite_helper:kill_process(PidSlave).

%% ===================================================================
%% Internal
%% ===================================================================
recipient_loop(Pid) ->
    receive
        Message -> Pid ! {received, self(), Message}
    end.
