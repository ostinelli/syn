-module(syn_backbone).
-behaviour(gen_server).

%% API
-export([start_link/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% records
-record(state, {}).

%% include
-include("syn.hrl").


%% ===================================================================
%% API
%% ===================================================================
-spec start_link() -> {ok, pid()} | {error, any()}.
start_link() ->
    Options = [],
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], Options).

%% ===================================================================
%% Callbacks
%% ===================================================================

%% ----------------------------------------------------------------------------------------------------------
%% Init
%% ----------------------------------------------------------------------------------------------------------
-spec init([]) ->
    {ok, #state{}} |
    {ok, #state{}, Timeout :: non_neg_integer()} |
    ignore |
    {stop, Reason :: any()}.
init([]) ->
    %% init
    case initdb() of
        ok ->
            {ok, #state{}};
        Other ->
            {stop, Other}
    end.

%% ----------------------------------------------------------------------------------------------------------
%% Call messages
%% ----------------------------------------------------------------------------------------------------------
-spec handle_call(Request :: any(), From :: any(), #state{}) ->
    {reply, Reply :: any(), #state{}} |
    {reply, Reply :: any(), #state{}, Timeout :: non_neg_integer()} |
    {noreply, #state{}} |
    {noreply, #state{}, Timeout :: non_neg_integer()} |
    {stop, Reason :: any(), Reply :: any(), #state{}} |
    {stop, Reason :: any(), #state{}}.

handle_call(Request, From, State) ->
    error_logger:warning_msg("Received from ~p an unknown call message: ~p", [Request, From]),
    {reply, undefined, State}.

%% ----------------------------------------------------------------------------------------------------------
%% Cast messages
%% ----------------------------------------------------------------------------------------------------------
-spec handle_cast(Msg :: any(), #state{}) ->
    {noreply, #state{}} |
    {noreply, #state{}, Timeout :: non_neg_integer()} |
    {stop, Reason :: any(), #state{}}.

handle_cast(Msg, State) ->
    error_logger:warning_msg("Received an unknown cast message: ~p", [Msg]),
    {noreply, State}.

%% ----------------------------------------------------------------------------------------------------------
%% All non Call / Cast messages
%% ----------------------------------------------------------------------------------------------------------
-spec handle_info(Info :: any(), #state{}) ->
    {noreply, #state{}} |
    {noreply, #state{}, Timeout :: non_neg_integer()} |
    {stop, Reason :: any(), #state{}}.

handle_info(Info, State) ->
    error_logger:warning_msg("Received an unknown info message: ~p", [Info]),
    {noreply, State}.

%% ----------------------------------------------------------------------------------------------------------
%% Terminate
%% ----------------------------------------------------------------------------------------------------------
-spec terminate(Reason :: any(), #state{}) -> terminated.
terminate(Reason, _State) ->
    error_logger:info_msg("Terminating syn with reason: ~p", [Reason]),
    terminated.

%% ----------------------------------------------------------------------------------------------------------
%% Convert process state when code is changed.
%% ----------------------------------------------------------------------------------------------------------
-spec code_change(OldVsn :: any(), #state{}, Extra :: any()) -> {ok, #state{}}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ===================================================================
%% Internal
%% ===================================================================
-spec initdb() -> ok | {error, any()}.
initdb() ->
    %% ensure all nodes are added - this covers when mnesia is in ram only mode
    mnesia:change_config(extra_db_nodes, [node() | nodes()]),
    %% ensure table exists
    case mnesia:create_table(syn_processes_table, [
        {type, set},
        {ram_copies, [node() | nodes()]},
        {attributes, record_info(fields, syn_processes_table)},
        {index, [#syn_processes_table.pid]},
        {storage_properties, [{ets, [{read_concurrency, true}]}]}
    ]) of
        {atomic, ok} ->
            error_logger:info_msg("syn_processes_table was successfully created."),
            ok;
        {aborted, {already_exists, syn_processes_table}} ->
            %% table already exists, try to add current node as copy
            add_table_copy_to_local_node();
        Other ->
            error_logger:error_msg("Error while creating syn_processes_table: ~p", [Other]),
            {error, Other}
    end.

-spec add_table_copy_to_local_node() -> ok | {error, any()}.
add_table_copy_to_local_node() ->
    case mnesia:add_table_copy(syn_processes_table, node(), ram_copies) of
        {atomic, ok} ->
            error_logger:info_msg("Copy of syn_processes_table was successfully added to current node."),
            ok;
        {aborted, {already_exists, syn_processes_table}} ->
            %% a copy of syn_processes_table is already added to current node
            ok;
        {aborted, Reason} ->
            error_logger:error_msg("Error while creating copy of syn_processes_table: ~p", [Reason]),
            {error, Reason}
    end.
