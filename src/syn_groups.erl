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
%% IMPLIED, INCLUDING BUT NOT LIMITED TO THxE WARRANTIES OF MERCHANTABILITY,
%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
%% THE SOFTWARE.
%% ==========================================================================================================
-module(syn_groups).
-behaviour(syn_gen_scope).

%% API
-export([start_link/1]).
-export([get_subcluster_nodes/1]).

%% syn_gen_scope callbacks
-export([
    init/1,
    handle_call/3,
    handle_info/2,
    save_remote_data/2,
    get_local_data/1,
    purge_local_data_for_node/2
]).

%% includes
-include("syn.hrl").

%% ===================================================================
%% API
%% ===================================================================
-spec start_link(Scope :: atom()) ->
    {ok, Pid :: pid()} | {error, {already_started, Pid :: pid()}} | {error, Reason :: any()}.
start_link(Scope) when is_atom(Scope) ->
    syn_gen_scope:start_link(?MODULE, Scope).

-spec get_subcluster_nodes(#state{}) -> [node()].
get_subcluster_nodes(State) ->
    syn_gen_scope:get_subcluster_nodes(?MODULE, State).

%% ===================================================================
%% Callbacks
%% ===================================================================

%% ----------------------------------------------------------------------------------------------------------
%% Init
%% ----------------------------------------------------------------------------------------------------------
-spec init(State :: term()) -> {ok, State :: term()}.
init(State) ->
    HandlerState = #{},
    %% init
    {ok, HandlerState}.

%% ----------------------------------------------------------------------------------------------------------
%% Call messages
%% ----------------------------------------------------------------------------------------------------------
-spec handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: term()) ->
    {reply, Reply :: term(), NewState :: term()} |
    {reply, Reply :: term(), NewState :: term(), timeout() | hibernate | {continue, term()}} |
    {noreply, NewState :: term()} |
    {noreply, NewState :: term(), timeout() | hibernate | {continue, term()}} |
    {stop, Reason :: term(), Reply :: term(), NewState :: term()} |
    {stop, Reason :: term(), NewState :: term()}.

handle_call(Request, From, State) ->
    error_logger:warning_msg("SYN[~s] Received from ~p an unknown call message: ~p", [node(), From, Request]),
    {reply, undefined, State}.

%% ----------------------------------------------------------------------------------------------------------
%% Info messages
%% ----------------------------------------------------------------------------------------------------------
-spec handle_info(Info :: timeout | term(), State :: term()) ->
    {noreply, NewState :: term()} |
    {noreply, NewState :: term(), timeout() | hibernate | {continue, term()}} |
    {stop, Reason :: term(), NewState :: term()}.

handle_info(Info, State) ->
    error_logger:warning_msg("SYN[~s] Received an unknown info message: ~p", [node(), Info]),
    {noreply, State}.

%% ----------------------------------------------------------------------------------------------------------
%% Data
%% ----------------------------------------------------------------------------------------------------------
-spec get_local_data(State :: term()) -> {ok, Data :: any()} | undefined.
get_local_data(#state{table_by_name = TableByName}) ->
    {ok, []}.

-spec save_remote_data(RemoteData :: any(), State :: term()) -> any().
save_remote_data(RegistryTuplesOfRemoteNode, #state{scope = Scope} = State) ->
    %% insert tuples
    ok.

-spec purge_local_data_for_node(Node :: node(), State :: term()) -> any().
purge_local_data_for_node(Node, #state{
    scope = Scope,
    table_by_name = TableByName,
    table_by_pid = TableByPid
}) ->
    ok.

%% ===================================================================
%% Internal
%% ===================================================================
