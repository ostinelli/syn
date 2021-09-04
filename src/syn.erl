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
-export([get_node_scopes/0, add_node_to_scope/1, add_node_to_scopes/1]).

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
-spec get_node_scopes() -> [atom()].
get_node_scopes() ->
    syn_scopes_sup:get_node_scopes().

-spec add_node_to_scope(Scope :: atom()) -> ok.
add_node_to_scope(Scope) ->
    syn_scopes_sup:add_node_to_scope(Scope).

-spec add_node_to_scopes(Scopes :: [atom()]) -> ok.
add_node_to_scopes(Scopes) ->
    lists:foreach(fun(Scope) ->
        syn_scopes_sup:add_node_to_scope(Scope)
    end, Scopes).
