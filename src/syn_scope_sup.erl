%% ==========================================================================================================
%% Syn - A global Process Registry and Process Group manager.
%%
%% The MIT License (MIT)
%%
%% Copyright (c) 2015-2022 Roberto Ostinelli <roberto@ostinelli.net> and Neato Robotics, Inc.
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
%% @private
-module(syn_scope_sup).
-behaviour(supervisor).

%% API
-export([start_link/1]).

%% Supervisor callbacks
-export([init/1]).

%% ===================================================================
%% API
%% ===================================================================
-spec start_link(Scope :: atom()) -> {ok, pid()} | {already_started, pid()} | shutdown.
start_link(Scope) ->
    supervisor:start_link(?MODULE, [Scope]).

%% ===================================================================
%% Callbacks
%% ===================================================================
-spec init([Scope :: atom()]) ->
    {ok, {{supervisor:strategy(), non_neg_integer(), pos_integer()}, [supervisor:child_spec()]}}.
init([Scope]) ->
    %% create ETS tables
    ok = syn_backbone:create_tables_for_scope(Scope),
    %% set children
    Children = [
        scope_child_spec(syn_registry, Scope),
        scope_child_spec(syn_pg, Scope)
    ],
    {ok, {{one_for_one, 10, 10}, Children}}.

%% ===================================================================
%% Internals
%% ===================================================================
-spec scope_child_spec(module(), Scope :: atom()) -> supervisor:child_spec().
scope_child_spec(Module, Scope) ->
    #{
        id => {Module, Scope},
        start => {Module, start_link, [Scope]},
        type => worker,
        shutdown => 10000,
        restart => permanent,
        modules => [Module]
    }.
