%% ==========================================================================================================
%% Syn - A global process registry.
%%
%% Copyright (C) 2015, Roberto Ostinelli <roberto@ostinelli.net>.
%% All rights reserved.
%%
%% The MIT License (MIT)
%%
%% Copyright (c) 2015 Roberto Ostinelli
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
-export([register/2, unregister/1]).
-export([find_by_key/1, find_by_pid/1]).
-export([count/0, count/1]).


%% ===================================================================
%% API
%% ===================================================================
-spec start() -> ok.
start() ->
    {ok, _} = application:ensure_all_started(mnesia),
    {ok, _} = application:ensure_all_started(syn),
    ok.

-spec stop() -> ok.
stop() ->
    ok = application:stop(syn).

-spec init() -> ok.
init() ->
    ok = syn_backbone:initdb().

-spec register(Key :: any(), Pid :: pid()) -> ok | {error, taken}.
register(Key, Pid) ->
    syn_backbone:register(Key, Pid).

-spec unregister(Key :: any()) -> ok | {error, undefined}.
unregister(Key) ->
    syn_backbone:unregister(Key).

-spec find_by_key(Key :: any()) -> pid() | undefined.
find_by_key(Key) ->
    syn_backbone:find_by_key(Key).

-spec find_by_pid(Pid :: pid()) -> Key :: any() | undefined.
find_by_pid(Pid) ->
    syn_backbone:find_by_pid(Pid).

-spec count() -> non_neg_integer().
count() ->
    syn_backbone:count().

-spec count(Node :: atom()) -> non_neg_integer().
count(Node) ->
    syn_backbone:count(Node).
