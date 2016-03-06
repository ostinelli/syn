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
-module(syn).

%% API
-export([start/0, stop/0]).
-export([init/0]).

%% registry
-export([register/2, register/3]).
-export([unregister/1]).
-export([find_by_key/1, find_by_key/2]).
-export([find_by_pid/1, find_by_pid/2]).
-export([registry_count/0, registry_count/1]).

%% groups
-export([join/2]).
-export([leave/2]).
-export([member/2]).
-export([get_members/1]).
-export([publish/2]).

%% ===================================================================
%% API
%% ===================================================================
-spec start() -> ok.
start() ->
    ok = start_application(mnesia),
    ok = start_application(syn),
    ok.

-spec stop() -> ok.
stop() ->
    ok = application:stop(syn).

-spec init() -> ok.
init() ->
    ok = syn_backbone:initdb().

-spec register(Key :: any(), Pid :: pid()) -> ok | {error, taken | pid_already_registered}.
register(Key, Pid) ->
    syn_registry:register(Key, Pid).

-spec register(Key :: any(), Pid :: pid(), Meta :: any()) -> ok | {error, taken | pid_already_registered}.
register(Key, Pid, Meta) ->
    syn_registry:register(Key, Pid, Meta).

-spec unregister(Key :: any()) -> ok | {error, undefined}.
unregister(Key) ->
    syn_registry:unregister(Key).

-spec find_by_key(Key :: any()) -> pid() | undefined.
find_by_key(Key) ->
    syn_registry:find_by_key(Key).

-spec find_by_key(Key :: any(), with_meta) -> {pid(), Meta :: any()} | undefined.
find_by_key(Key, with_meta) ->
    syn_registry:find_by_key(Key, with_meta).

-spec find_by_pid(Pid :: pid()) -> Key :: any() | undefined.
find_by_pid(Pid) ->
    syn_registry:find_by_pid(Pid).

-spec find_by_pid(Pid :: pid(), with_meta) -> {Key :: any(), Meta :: any()} | undefined.
find_by_pid(Pid, with_meta) ->
    syn_registry:find_by_pid(Pid, with_meta).

-spec registry_count() -> non_neg_integer().
registry_count() ->
    syn_registry:count().

-spec registry_count(Node :: atom()) -> non_neg_integer().
registry_count(Node) ->
    syn_registry:count(Node).

-spec join(Name :: any(), Pid :: pid()) -> ok | {error, pid_already_in_group}.
join(Name, Pid) ->
    syn_groups:join(Name, Pid).

-spec leave(Name :: any(), Pid :: pid()) -> ok | {error, undefined | pid_not_in_group}.
leave(Name, Pid) ->
    syn_groups:leave(Name, Pid).

-spec member(Pid :: pid(), Name :: any()) -> boolean().
member(Pid, Name) ->
    syn_groups:member(Pid, Name).

-spec get_members(Name :: any()) -> [pid()].
get_members(Name) ->
    syn_groups:get_members(Name).

-spec publish(Name :: any(), Message :: any()) -> {ok, RecipientCount :: non_neg_integer()}.
publish(Name, Message) ->
    syn_groups:publish(Name, Message).

%% ===================================================================
%% Internal
%% ===================================================================
-spec start_application(atom()) -> ok | {error, any()}.
start_application(Application) ->
    case application:start(Application) of
        ok -> ok;
        {error, {already_started, Application}} -> ok;
        Error -> Error
    end.
