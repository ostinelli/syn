%% ==========================================================================================================
%% Syn - A global process registry.
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

%% global
-export([register/2, register/3]).
-export([unregister/1]).
-export([find_by_key/1, find_by_key/2]).
-export([find_by_pid/1, find_by_pid/2]).
-export([registry_count/0, registry_count/1]).

%% PG
-export([add_to_pg/2]).
-export([pids_of_pg/1]).

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
    syn_global:register(Key, Pid).

-spec register(Key :: any(), Pid :: pid(), Meta :: any()) -> ok | {error, taken | pid_already_registered}.
register(Key, Pid, Meta) ->
    syn_global:register(Key, Pid, Meta).

-spec unregister(Key :: any()) -> ok | {error, undefined}.
unregister(Key) ->
    syn_global:unregister(Key).

-spec find_by_key(Key :: any()) -> pid() | undefined.
find_by_key(Key) ->
    syn_global:find_by_key(Key).

-spec find_by_key(Key :: any(), with_meta) -> {pid(), Meta :: any()} | undefined.
find_by_key(Key, with_meta) ->
    syn_global:find_by_key(Key, with_meta).

-spec find_by_pid(Pid :: pid()) -> Key :: any() | undefined.
find_by_pid(Pid) ->
    syn_global:find_by_pid(Pid).

-spec find_by_pid(Pid :: pid(), with_meta) -> {Key :: any(), Meta :: any()} | undefined.
find_by_pid(Pid, with_meta) ->
    syn_global:find_by_pid(Pid, with_meta).

-spec registry_count() -> non_neg_integer().
registry_count() ->
    syn_global:count().

-spec registry_count(Node :: atom()) -> non_neg_integer().
registry_count(Node) ->
    syn_global:count(Node).

-spec add_to_pg(Name :: any(), Pid :: pid()) -> ok | {error, pid_already_in_group}.
add_to_pg(Name, Pid) ->
    syn_pg:add_to_pg(Name, Pid).

-spec pids_of_pg(Name :: any()) -> [pid()].
pids_of_pg(Name) ->
    syn_pg:pids_of_pg(Name).

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
