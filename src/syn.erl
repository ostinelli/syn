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
-export([whereis/1, whereis/2]).
-export([register/2, register/3]).
-export([unregister/1]).
-export([registry_count/0, registry_count/1]).

%% ===================================================================
%% API
%% ===================================================================
-spec start() -> ok.
start() ->
    {ok, _} = application:ensure_all_started(syn),
    ok.

-spec stop() -> ok.
stop() ->
    ok = application:stop(syn).

-spec whereis(Name :: term()) -> pid() | undefined.
whereis(Name) ->
    syn_registry:whereis(Name).

-spec whereis(Name :: term(), with_meta) -> {pid(), Meta :: term()} | undefined.
whereis(Name, with_meta) ->
    syn_registry:whereis(Name, with_meta).

-spec register(Name :: term(), Pid :: pid()) -> ok | {error, Reason :: term()}.
register(Name, Pid) ->
    syn_registry:register(Name, Pid).

-spec register(Name :: term(), Pid :: pid(), Meta :: term()) -> ok | {error, Reason :: term()}.
register(Name, Pid, Meta) ->
    syn_registry:register(Name, Pid, Meta).

-spec unregister(Name :: term()) -> ok | {error, Reason :: term()}.
unregister(Name) ->
    syn_registry:unregister(Name).

-spec registry_count() -> non_neg_integer().
registry_count() ->
    syn_registry:count().

-spec registry_count(Node :: atom()) -> non_neg_integer().
registry_count(Node) ->
    syn_registry:count(Node).
