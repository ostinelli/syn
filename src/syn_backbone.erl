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
-module(syn_backbone).
-behaviour(gen_server).

%% API
-export([start_link/0]).
-export([create_tables_for_scope/1]).
-export([get_table_name/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% includes
-include("syn.hrl").

%% ===================================================================
%% API
%% ===================================================================
-spec start_link() -> {ok, pid()} | {error, any()}.
start_link() ->
    Options = [],
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], Options).

-spec create_tables_for_scope(Scope :: atom()) -> ok.
create_tables_for_scope(Scope) ->
    gen_server:call(?MODULE, {create_tables_for_scope, Scope}).

-spec get_table_name(TableName :: atom(), Scope :: atom()) -> atom().
get_table_name(TableName, Scope) ->
    TableNameBin = atom_to_binary(TableName),
    ScopeBin = atom_to_binary(Scope),
    binary_to_atom(<<TableNameBin/binary, "_", ScopeBin/binary>>).

%% ===================================================================
%% Callbacks
%% ===================================================================

%% ----------------------------------------------------------------------------------------------------------
%% Init
%% ----------------------------------------------------------------------------------------------------------
-spec init([]) ->
    {ok, State :: map()} |
    {ok, State :: map(), Timeout :: non_neg_integer()} |
    ignore |
    {stop, Reason :: any()}.
init([]) ->
    %% init
    {ok, #{}}.

%% ----------------------------------------------------------------------------------------------------------
%% Call messages
%% ----------------------------------------------------------------------------------------------------------
-spec handle_call(Request :: any(), From :: any(), State :: map()) ->
    {reply, Reply :: any(), State :: map()} |
    {reply, Reply :: any(), State :: map(), Timeout :: non_neg_integer()} |
    {noreply, State :: map()} |
    {noreply, State :: map(), Timeout :: non_neg_integer()} |
    {stop, Reason :: any(), Reply :: any(), State :: map()} |
    {stop, Reason :: any(), State :: map()}.
handle_call({create_tables_for_scope, Scope}, _From, State) ->
    error_logger:info_msg("SYN[~p] Creating tables for scope: ~p", [node(), Scope]),
    ensure_table_exists(get_table_name(syn_registry_by_name, Scope)),
    ensure_table_exists(get_table_name(syn_registry_by_pid, Scope)),
    ensure_table_exists(get_table_name(syn_groups_by_name, Scope)),
    ensure_table_exists(get_table_name(syn_groups_by_pid, Scope)),
    {reply, ok, State};

handle_call(Request, From, State) ->
    error_logger:warning_msg("SYN[~p] Received from ~p an unknown call message: ~p", [node(), Request, From]),
    {reply, undefined, State}.

%% ----------------------------------------------------------------------------------------------------------
%% Cast messages
%% ----------------------------------------------------------------------------------------------------------
-spec handle_cast(Msg :: any(), State :: map()) ->
    {noreply, State :: map()} |
    {noreply, State :: map(), Timeout :: non_neg_integer()} |
    {stop, Reason :: any(), State :: map()}.
handle_cast(Msg, State) ->
    error_logger:warning_msg("SYN[~p] Received an unknown cast message: ~p", [node(), Msg]),
    {noreply, State}.

%% ----------------------------------------------------------------------------------------------------------
%% All non Call / Cast messages
%% ----------------------------------------------------------------------------------------------------------
-spec handle_info(Info :: any(), State :: map()) ->
    {noreply, State :: map()} |
    {noreply, State :: map(), Timeout :: non_neg_integer()} |
    {stop, Reason :: any(), State :: map()}.
handle_info(Info, State) ->
    error_logger:warning_msg("SYN[~p] Received an unknown info message: ~p", [node(), Info]),
    {noreply, State}.

%% ----------------------------------------------------------------------------------------------------------
%% Terminate
%% ----------------------------------------------------------------------------------------------------------
-spec terminate(Reason :: any(), State :: map()) -> terminated.
terminate(Reason, _State) ->
    error_logger:info_msg("SYN[~p] Terminating with reason: ~p", [node(), Reason]),
    %% return
    terminated.

%% ----------------------------------------------------------------------------------------------------------
%% Convert process state when code is changed.
%% ----------------------------------------------------------------------------------------------------------
-spec code_change(OldVsn :: any(), State :: map(), Extra :: any()) -> {ok, State :: map()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ===================================================================
%% Internal
%% ===================================================================
-spec ensure_table_exists(Name :: atom()) -> atom().
ensure_table_exists(Name) ->
    case ets:whereis(Name) of
        undefined ->
            %% regarding decentralized_counters: <https://blog.erlang.org/scalable-ets-counters/>
            ets:new(Name, [
                ordered_set, public, named_table,
                {read_concurrency, true}, {write_concurrency, true}, {decentralized_counters, true}
            ]);

        _ ->
            ok
    end.
