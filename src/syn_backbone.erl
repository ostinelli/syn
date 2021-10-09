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
-export([save_process_name/2, get_process_name/1]).

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

-spec save_process_name(Key :: any(), ProcessName :: atom()) -> true.
save_process_name(Key, ProcessName) ->
    true = ets:insert(syn_process_names, {Key, ProcessName}).

-spec get_process_name(Key :: any()) -> ProcessName :: atom().
get_process_name(Key) ->
    case ets:lookup(syn_process_names, Key) of
        [{_, ProcessName}] -> ProcessName;
        [] -> undefined
    end.

-spec get_table_name(TableId :: atom(), Scope :: atom()) -> TableName :: atom() | undefined.
get_table_name(TableId, Scope) ->
    case ets:lookup(syn_table_names, {TableId, Scope}) of
        [{_, TableName}] -> TableName;
        [] -> undefined
    end.

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
    %% create table names table
    ets:new(syn_table_names, [set, public, named_table, {read_concurrency, true}, {decentralized_counters, true}]),
    ets:new(syn_process_names, [set, public, named_table, {read_concurrency, true}, {decentralized_counters, true}]),
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
    error_logger:info_msg("SYN[~s] Creating tables for scope '~s'", [?MODULE, Scope]),
    ensure_table_existence(set, syn_registry_by_name, Scope),
    ensure_table_existence(bag, syn_registry_by_pid, Scope),
    ensure_table_existence(ordered_set, syn_groups_by_name, Scope),
    ensure_table_existence(ordered_set, syn_groups_by_pid, Scope),
    {reply, ok, State};

handle_call(Request, From, State) ->
    error_logger:warning_msg("SYN[~s] Received from ~p an unknown call message: ~p", [?MODULE, From, Request]),
    {reply, undefined, State}.

%% ----------------------------------------------------------------------------------------------------------
%% Cast messages
%% ----------------------------------------------------------------------------------------------------------
-spec handle_cast(Msg :: any(), State :: map()) ->
    {noreply, State :: map()} |
    {noreply, State :: map(), Timeout :: non_neg_integer()} |
    {stop, Reason :: any(), State :: map()}.
handle_cast(Msg, State) ->
    error_logger:warning_msg("SYN[~s] Received an unknown cast message: ~p", [?MODULE, Msg]),
    {noreply, State}.

%% ----------------------------------------------------------------------------------------------------------
%% All non Call / Cast messages
%% ----------------------------------------------------------------------------------------------------------
-spec handle_info(Info :: any(), State :: map()) ->
    {noreply, State :: map()} |
    {noreply, State :: map(), Timeout :: non_neg_integer()} |
    {stop, Reason :: any(), State :: map()}.
handle_info(Info, State) ->
    error_logger:warning_msg("SYN[~s] Received an unknown info message: ~p", [?MODULE, Info]),
    {noreply, State}.

%% ----------------------------------------------------------------------------------------------------------
%% Terminate
%% ----------------------------------------------------------------------------------------------------------
-spec terminate(Reason :: any(), State :: map()) -> terminated.
terminate(Reason, _State) ->
    error_logger:info_msg("SYN[~s] Terminating with reason: ~p", [?MODULE, Reason]),
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
-spec ensure_table_existence(Type :: ets:type(), TableId :: atom(), Scope :: atom()) -> ok.
ensure_table_existence(Type, TableId, Scope) ->
    %% build name
    TableIdBin = atom_to_binary(TableId),
    ScopeBin = atom_to_binary(Scope),
    TableName = binary_to_atom(<<TableIdBin/binary, "_", ScopeBin/binary>>),
    %% save to loopkup table
    true = ets:insert(syn_table_names, {{TableId, Scope}, TableName}),
    %% check or create
    case ets:whereis(TableName) of
        undefined ->
            %% regarding decentralized_counters: <https://blog.erlang.org/scalable-ets-counters/>
            ets:new(TableName, [
                Type, public, named_table,
                {read_concurrency, true}, {decentralized_counters, true}
            ]),
            ok;

        _ ->
            ok
    end.
