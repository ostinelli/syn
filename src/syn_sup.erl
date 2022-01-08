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
-module(syn_sup).
-behaviour(supervisor).

%% API
-export([start_link/0]).
-export([node_scopes/0, add_node_to_scope/1]).

%% supervisor callbacks
-export([init/1]).

%% includes
-include("syn.hrl").

%% ===================================================================
%% API
%% ===================================================================
-spec start_link() -> {ok, pid()} | {already_started, pid()} | shutdown.
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

-spec node_scopes() -> [atom()].
node_scopes() ->
    application:get_env(syn, scopes, []).

-spec add_node_to_scope(Scope :: atom()) -> ok.
add_node_to_scope(Scope) when is_atom(Scope) ->
    error_logger:info_msg("SYN[~s] Adding node to scope <~s>", [node(), Scope]),
    Scopes0 = node_scopes(),
    case lists:member(Scope, Scopes0) of
        true ->
            %% nothing to do
            ok;

        false ->
            %% add scope
            Scopes = [Scope | Scopes0],
            %% save to ENV (failsafe if sup is restarted)
            application:set_env(syn, scopes, Scopes),
            %% start child
            supervisor:start_child(?MODULE, child_spec(Scope)),
            ok
    end.

%% ===================================================================
%% Callbacks
%% ===================================================================
-spec init([]) ->
    {ok, {{supervisor:strategy(), non_neg_integer(), pos_integer()}, [supervisor:child_spec()]}}.
init([]) ->
    %% backbone
    BackboneChildSpec = #{
        id => syn_backbone,
        start => {syn_backbone, start_link, []},
        type => worker,
        shutdown => 10000,
        restart => permanent,
        modules => [syn_backbone]
    },

    %% build children
    Children = [BackboneChildSpec] ++
        %% add scopes sup
        lists:foldl(fun(Scope, Acc) ->
            %% add to specs
            [child_spec(Scope) | Acc]
        end, [], node_scopes()),

    %% return
    {ok, {{one_for_one, 10, 10}, Children}}.

%% ===================================================================
%% Internals
%% ===================================================================
-spec child_spec(Scope :: atom()) -> supervisor:child_spec().
child_spec(Scope) ->
    #{
        id => {syn_scope_sup, Scope},
        start => {syn_scope_sup, start_link, [Scope]},
        type => supervisor,
        shutdown => 10000,
        restart => permanent,
        modules => [syn_scope_sup]
    }.
