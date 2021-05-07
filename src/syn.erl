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
-module(syn).

%% API
-export([start/0, stop/0]).
-export([register/2, register/3]).
-export([unregister_and_register/2, unregister_and_register/3]).
-export([unregister/1]).
-export([whereis/1, whereis/2]).
-export([registry_count/0, registry_count/1]).
-export([join/2, join/3]).
-export([leave/2]).
-export([get_members/1, get_members/2]).
-export([get_group_names/0]).
-export([member/2]).
-export([get_local_members/1, get_local_members/2]).
-export([local_member/2]).
-export([groups_count/0, groups_count/1]).
-export([publish/2]).
-export([publish_to_local/2]).
-export([multi_call/2, multi_call/3, multi_call_reply/2]).
-export([force_cluster_sync/1]).

%% gen_server via interface
-export([register_name/2, unregister_name/1, whereis_name/1, send/2]).

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

%% ----- \/ registry -------------------------------------------------
-spec register(Name :: any(), Pid :: pid()) -> ok | {error, Reason :: any()}.
register(Name, Pid) ->
    syn_registry:register(Name, Pid).

-spec register(Name :: any(), Pid :: pid(), Meta :: any()) -> ok | {error, Reason :: any()}.
register(Name, Pid, Meta) ->
    syn_registry:register(Name, Pid, Meta).

-spec unregister_and_register(Name :: any(), Pid :: pid()) -> ok | {error, Reason :: any()}.
unregister_and_register(Name, Pid) ->
    syn_registry:unregister_and_register(Name, Pid).

-spec unregister_and_register(Name :: any(), Pid :: pid(), Meta :: any()) -> ok | {error, Reason :: any()}.
unregister_and_register(Name, Pid, Meta) ->
    syn_registry:unregister_and_register(Name, Pid, Meta).

-spec unregister(Name :: any()) -> ok | {error, Reason :: any()}.
unregister(Name) ->
    syn_registry:unregister(Name).

-spec whereis(Name :: any()) -> pid() | undefined.
whereis(Name) ->
    syn_registry:whereis(Name).

-spec whereis(Name :: any(), with_meta) -> {pid(), Meta :: any()} | undefined.
whereis(Name, with_meta) ->
    syn_registry:whereis(Name, with_meta).

-spec registry_count() -> non_neg_integer().
registry_count() ->
    syn_registry:count().

-spec registry_count(Node :: atom()) -> non_neg_integer().
registry_count(Node) ->
    syn_registry:count(Node).

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
    syn_registry:whereis(Name).

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
-spec join(GroupName :: any(), Pid :: pid()) -> ok.
join(GroupName, Pid) ->
    syn_groups:join(GroupName, Pid).

-spec join(GroupName :: any(), Pid :: pid(), Meta :: any()) -> ok.
join(GroupName, Pid, Meta) ->
    syn_groups:join(GroupName, Pid, Meta).

-spec leave(GroupName :: any(), Pid :: pid()) -> ok | {error, Reason :: any()}.
leave(GroupName, Pid) ->
    syn_groups:leave(GroupName, Pid).

-spec get_members(GroupName :: any()) -> [pid()].
get_members(GroupName) ->
    syn_groups:get_members(GroupName).

-spec get_members(GroupName :: any(), with_meta) -> [{pid(), Meta :: any()}].
get_members(GroupName, with_meta) ->
    syn_groups:get_members(GroupName, with_meta).

-spec get_group_names() -> [GroupName :: any()].
get_group_names() ->
    syn_groups:get_group_names().

-spec member(Pid :: pid(), GroupName :: any()) -> boolean().
member(Pid, GroupName) ->
    syn_groups:member(Pid, GroupName).

-spec get_local_members(GroupName :: any()) -> [pid()].
get_local_members(GroupName) ->
    syn_groups:get_local_members(GroupName).

-spec get_local_members(GroupName :: any(), with_meta) -> [{pid(), Meta :: any()}].
get_local_members(GroupName, with_meta) ->
    syn_groups:get_local_members(GroupName, with_meta).

-spec local_member(Pid :: pid(), GroupName :: any()) -> boolean().
local_member(Pid, GroupName) ->
    syn_groups:local_member(Pid, GroupName).

-spec groups_count() -> non_neg_integer().
groups_count() ->
    syn_groups:count().

-spec groups_count(Node :: atom()) -> non_neg_integer().
groups_count(Node) ->
    syn_groups:count(Node).

-spec publish(GroupName :: any(), Message :: any()) -> {ok, RecipientCount :: non_neg_integer()}.
publish(GroupName, Message) ->
    syn_groups:publish(GroupName, Message).

-spec publish_to_local(GroupName :: any(), Message :: any()) -> {ok, RecipientCount :: non_neg_integer()}.
publish_to_local(GroupName, Message) ->
    syn_groups:publish_to_local(GroupName, Message).

-spec multi_call(GroupName :: any(), Message :: any()) ->
    {[{pid(), Reply :: any()}], [BadPid :: pid()]}.
multi_call(GroupName, Message) ->
    syn_groups:multi_call(GroupName, Message).

-spec multi_call(GroupName :: any(), Message :: any(), Timeout :: non_neg_integer()) ->
    {[{pid(), Reply :: any()}], [BadPid :: pid()]}.
multi_call(GroupName, Message, Timeout) ->
    syn_groups:multi_call(GroupName, Message, Timeout).

-spec multi_call_reply(CallerPid :: pid(), Reply :: any()) -> {syn_multi_call_reply, pid(), Reply :: any()}.
multi_call_reply(CallerPid, Reply) ->
    syn_groups:multi_call_reply(CallerPid, Reply).

%% ----- \/ anti entropy ---------------------------------------------
-spec force_cluster_sync(registry | groups) -> ok.
force_cluster_sync(registry) ->
    syn_registry:force_cluster_sync();
force_cluster_sync(groups) ->
    syn_groups:force_cluster_sync().
