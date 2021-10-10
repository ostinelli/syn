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
-module(syn).

%% API
-export([start/0, stop/0]).
%% scopes
-export([node_scopes/0, add_node_to_scope/1, add_node_to_scopes/1]).
-export([set_event_handler/1]).
%% registry
-export([lookup/1, lookup/2]).
-export([register/2, register/3, register/4]).
-export([unregister/1, unregister/2]).
-export([registry_count/0, registry_count/1, registry_count/2]).
-export([local_registry_count/0, local_registry_count/1]).
%% gen_server via interface
-export([register_name/2, unregister_name/1, whereis_name/1, send/2]).
%% groups
-export([members/1, members/2]).
-export([is_member/2, is_member/3]).
-export([local_members/1, local_members/2]).
-export([is_local_member/2, is_local_member/3]).
-export([join/2, join/3, join/4]).
-export([leave/2, leave/3]).
-export([group_count/0, group_count/1, group_count/2]).
-export([local_group_count/0, local_group_count/1]).
-export([group_names/0, group_names/1, group_names/2]).
-export([local_group_names/0, local_group_names/1]).
-export([publish/2, publish/3]).
-export([local_publish/2, local_publish/3]).
-export([multi_call/2, multi_call/3, multi_call/4, multi_call_reply/2]).

%% ===================================================================
%% API
%% ===================================================================
-spec start() -> ok.
start() ->
    {ok, _} = application:ensure_all_started(syn),
    ok.

-spec stop() -> ok | {error, Reason :: any()}.
stop() ->
    application:stop(syn).

%% ----- \/ scopes ---------------------------------------------------
-spec node_scopes() -> [atom()].
node_scopes() ->
    syn_sup:node_scopes().

-spec add_node_to_scope(Scope :: atom()) -> ok.
add_node_to_scope(Scope) ->
    syn_sup:add_node_to_scope(Scope).

-spec add_node_to_scopes(Scopes :: [atom()]) -> ok.
add_node_to_scopes(Scopes) ->
    lists:foreach(fun(Scope) ->
        syn_sup:add_node_to_scope(Scope)
    end, Scopes).

-spec set_event_handler(module()) -> ok.
set_event_handler(Module) ->
    application:set_env(syn, event_handler, Module).

%% ----- \/ registry -------------------------------------------------
-spec lookup(Name :: any()) -> {pid(), Meta :: any()} | undefined.
lookup(Name) ->
    syn_registry:lookup(Name).

-spec lookup(Scope :: atom(), Name :: any()) -> {pid(), Meta :: any()} | undefined.
lookup(Scope, Name) ->
    syn_registry:lookup(Scope, Name).

-spec register(Name :: any(), Pid :: pid()) -> ok | {error, Reason :: any()}.
register(Name, Pid) ->
    syn_registry:register(Name, Pid).

-spec register(NameOrScope :: any(), PidOrName :: any(), MetaOrPid :: any()) -> ok | {error, Reason :: any()}.
register(NameOrScope, PidOrName, MetaOrPid) ->
    syn_registry:register(NameOrScope, PidOrName, MetaOrPid).

-spec register(Scope :: atom(), Name :: any(), Pid :: pid(), Meta :: any()) -> ok | {error, Reason :: any()}.
register(Scope, Name, Pid, Meta) ->
    syn_registry:register(Scope, Name, Pid, Meta).

-spec unregister(Name :: any()) -> ok | {error, Reason :: any()}.
unregister(Name) ->
    syn_registry:unregister(Name).

-spec unregister(Scope :: atom(), Name :: any()) -> ok | {error, Reason :: any()}.
unregister(Scope, Name) ->
    syn_registry:unregister(Scope, Name).

-spec registry_count() -> non_neg_integer().
registry_count() ->
    syn_registry:count().

-spec registry_count(Scope :: atom()) -> non_neg_integer().
registry_count(Scope) ->
    syn_registry:count(Scope).

-spec registry_count(Scope :: atom(), Node :: node()) -> non_neg_integer().
registry_count(Scope, Node) ->
    syn_registry:count(Scope, Node).

-spec local_registry_count() -> non_neg_integer().
local_registry_count() ->
    syn_registry:local_count().

-spec local_registry_count(Scope :: atom()) -> non_neg_integer().
local_registry_count(Scope) ->
    syn_registry:local_count(Scope).

%% ----- \/ gen_server via module interface --------------------------
-spec register_name(Name :: any(), Pid :: pid()) -> yes | no.
register_name(Name, Pid) ->
    case syn_registry:register(Name, Pid) of
        ok -> yes;
        _ -> no
    end.

-spec unregister_name(Name :: any()) -> any().
unregister_name(Name) ->
    case syn_registry:unregister(Name) of
        ok -> Name;
        _ -> nil
    end.

-spec whereis_name(Name :: any()) -> pid() | undefined.
whereis_name(Name) ->
    case syn_registry:lookup(Name) of
        {Pid, _Meta} -> Pid;
        undefined -> undefined
    end.

-spec send(Name :: any(), Message :: any()) -> pid().
send(Name, Message) ->
    case whereis_name(Name) of
        undefined ->
            {badarg, {Name, Message}};
        Pid ->
            Pid ! Message,
            Pid
    end.

%% ----- \/ groups ---------------------------------------------------
-spec members(GroupName :: term()) -> [{Pid :: pid(), Meta :: term()}].
members(GroupName) ->
    syn_groups:members(GroupName).

-spec members(Scope :: atom(), GroupName :: term()) -> [{Pid :: pid(), Meta :: term()}].
members(Scope, GroupName) ->
    syn_groups:members(Scope, GroupName).

-spec is_member(GroupName :: any(), Pid :: pid()) -> boolean().
is_member(GroupName, Pid) ->
    syn_groups:is_member(GroupName, Pid).

-spec is_member(Scope :: atom(), GroupName :: any(), Pid :: pid()) -> boolean().
is_member(Scope, GroupName, Pid) ->
    syn_groups:is_member(Scope, GroupName, Pid).

-spec local_members(GroupName :: term()) -> [{Pid :: pid(), Meta :: term()}].
local_members(GroupName) ->
    syn_groups:local_members(GroupName).

-spec local_members(Scope :: atom(), GroupName :: term()) -> [{Pid :: pid(), Meta :: term()}].
local_members(Scope, GroupName) ->
    syn_groups:local_members(Scope, GroupName).

-spec is_local_member(GroupName :: any(), Pid :: pid()) -> boolean().
is_local_member(GroupName, Pid) ->
    syn_groups:is_local_member(GroupName, Pid).

-spec is_local_member(Scope :: atom(), GroupName :: any(), Pid :: pid()) -> boolean().
is_local_member(Scope, GroupName, Pid) ->
    syn_groups:is_local_member(Scope, GroupName, Pid).

-spec join(GroupName :: any(), Pid :: pid()) -> ok | {error, Reason :: any()}.
join(GroupName, Pid) ->
    syn_groups:join(GroupName, Pid).

-spec join(GroupNameOrScope :: any(), PidOrGroupName :: any(), MetaOrPid :: any()) -> ok | {error, Reason :: any()}.
join(GroupNameOrScope, PidOrGroupName, MetaOrPid) ->
    syn_groups:join(GroupNameOrScope, PidOrGroupName, MetaOrPid).

-spec join(Scope :: atom(), GroupName :: any(), Pid :: pid(), Meta :: any()) -> ok | {error, Reason :: any()}.
join(Scope, GroupName, Pid, Meta) ->
    syn_groups:join(Scope, GroupName, Pid, Meta).

-spec leave(GroupName :: any(), Pid :: pid()) -> ok | {error, Reason :: any()}.
leave(GroupName, Pid) ->
    syn_groups:leave(GroupName, Pid).

-spec leave(Scope :: atom(), GroupName :: any(), Pid :: pid()) -> ok | {error, Reason :: any()}.
leave(Scope, GroupName, Pid) ->
    syn_groups:leave(Scope, GroupName, Pid).

-spec group_count() -> non_neg_integer().
group_count() ->
    syn_groups:count().

-spec group_count(Scope :: atom()) -> non_neg_integer().
group_count(Scope) ->
    syn_groups:count(Scope).

-spec group_count(Scope :: atom(), Node :: node()) -> non_neg_integer().
group_count(Scope, Node) ->
    syn_groups:count(Scope, Node).

-spec local_group_count() -> non_neg_integer().
local_group_count() ->
    syn_groups:local_count().

-spec local_group_count(Scope :: atom()) -> non_neg_integer().
local_group_count(Scope) ->
    syn_groups:local_count(Scope).

-spec group_names() -> [GroupName :: term()].
group_names() ->
    syn_groups:group_names().

-spec group_names(Scope :: atom()) -> [GroupName :: term()].
group_names(Scope) ->
    syn_groups:group_names(Scope).

-spec group_names(Scope :: atom(), Node :: node()) -> [GroupName :: term()].
group_names(Scope, Node) ->
    syn_groups:group_names(Scope, Node).

-spec local_group_names() -> [GroupName :: term()].
local_group_names() ->
    syn_groups:local_group_names().

-spec local_group_names(Scope :: atom()) -> [GroupName :: term()].
local_group_names(Scope) ->
    syn_groups:local_group_names(Scope).

-spec publish(GroupName :: any(), Message :: any()) -> {ok, RecipientCount :: non_neg_integer()}.
publish(GroupName, Message) ->
    syn_groups:publish(GroupName, Message).

-spec publish(Scope :: atom(), GroupName :: any(), Message :: any()) -> {ok, RecipientCount :: non_neg_integer()}.
publish(Scope, GroupName, Message) ->
    syn_groups:publish(Scope, GroupName, Message).

-spec local_publish(GroupName :: any(), Message :: any()) -> {ok, RecipientCount :: non_neg_integer()}.
local_publish(GroupName, Message) ->
    syn_groups:local_publish(GroupName, Message).

-spec local_publish(Scope :: atom(), GroupName :: any(), Message :: any()) -> {ok, RecipientCount :: non_neg_integer()}.
local_publish(Scope, GroupName, Message) ->
    syn_groups:local_publish(Scope, GroupName, Message).

-spec multi_call(GroupName :: any(), Message :: any()) ->
    {[{pid(), Reply :: any()}], [BadPid :: pid()]}.
multi_call(GroupName, Message) ->
    syn_groups:multi_call(GroupName, Message).

-spec multi_call(Scope :: atom(), GroupName :: any(), Message :: any()) ->
    {[{pid(), Reply :: any()}], [BadPid :: pid()]}.
multi_call(Scope, GroupName, Message) ->
    syn_groups:multi_call(Scope, GroupName, Message).

-spec multi_call(Scope :: atom(), GroupName :: any(), Message :: any(), Timeout :: non_neg_integer()) ->
    {[{pid(), Reply :: any()}], [BadPid :: pid()]}.
multi_call(Scope, GroupName, Message, Timeout) ->
    syn_groups:multi_call(Scope, GroupName, Message, Timeout).

-spec multi_call_reply(CallerPid :: pid(), Reply :: any()) -> {syn_multi_call_reply, pid(), Reply :: any()}.
multi_call_reply(CallerPid, Reply) ->
    syn_groups:multi_call_reply(CallerPid, Reply).
