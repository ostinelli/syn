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
-module(syn_backbone).
-behaviour(gen_server).

%% API
-export([start_link/0]).
-export([register/2]).
-export([find_by_key/1, find_by_pid/1]).

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

-spec find_by_key(Key :: any()) -> pid() | undefined.
find_by_key(Key) ->
    case mnesia:dirty_read(syn_processes_table, Key) of
        [Process] -> return_pid_if_on_connected_node(Process);
        _ -> undefined
    end.

-spec find_by_pid(Pid :: pid()) -> Key :: any() | undefined.
find_by_pid(Pid) ->
    case mnesia:dirty_index_read(syn_processes_table, Pid, #syn_processes_table.pid) of
        [Process] -> return_key_if_on_connected_node(Process);
        _ -> undefined
    end.

-spec register(Key :: any(), Pid :: pid()) -> ok | {error, already_taken}.
register(Key, Pid) ->
    case find_by_key(Key) of
        undefined ->
            %% add to table
            mnesia:dirty_write(#syn_processes_table{
                key = Key,
                pid = Pid,
                node = node()
            }),
            %% link
            gen_server:call(?MODULE, {link_process, Pid});
        _ ->
            {error, already_taken}
    end.

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
    %% trap linked processes signal
    process_flag(trap_exit, true),
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

handle_call({link_process, Pid}, _From, State) ->
    erlang:link(Pid),
    {reply, ok, State};

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

handle_info({'EXIT', Pid, Reason}, State) ->
    %% do not lock backbone
    spawn(fun() ->
        %% check if pid is in table
        case find_by_pid(Pid) of
            undefined ->
                case Reason of
                    normal -> ok;
                    _ -> error_logger:warning_msg("Received a crash message from an unlinked process ~p with reason: ~p", [Pid, Reason])
                end;
            Key ->
                %% delete from table
                remove_process_by_key(Key),
                %% log
                case Reason of
                    normal -> ok;
                    killed -> ok;
                    _ -> error_logger:error_msg("Process with key ~p crashed with reason: ~p", [Key, Reason])
                end
        end
    end),
    %% return
    {noreply, State};

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
    CurrentNode = node(),
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
        {aborted, {already_exists, syn_processes_table, CurrentNode}} ->
            %% table already exists, try to add current node as copy
            add_table_copy_to_local_node();
        Other ->
            error_logger:error_msg("Error while creating syn_processes_table: ~p", [Other]),
            {error, Other}
    end.

-spec add_table_copy_to_local_node() -> ok | {error, any()}.
add_table_copy_to_local_node() ->
    CurrentNode = node(),
    case mnesia:add_table_copy(syn_processes_table, node(), ram_copies) of
        {atomic, ok} ->
            error_logger:info_msg("Copy of syn_processes_table was successfully added to current node."),
            ok;
        {aborted, {already_exists, syn_processes_table}} ->
            %% a copy of syn_processes_table is already added to current node
            ok;
        {aborted, {already_exists, syn_processes_table, CurrentNode}} ->
            %% a copy of syn_processes_table is already added to current node
            ok;
        {aborted, Reason} ->
            error_logger:error_msg("Error while creating copy of syn_processes_table: ~p", [Reason]),
            {error, Reason}
    end.

-spec return_pid_if_on_connected_node(Process :: #syn_processes_table{}) -> pid() | undefined.
return_pid_if_on_connected_node(Process) ->
    case lists:member(Process#syn_processes_table.node, [node() | nodes()]) of
        true -> Process#syn_processes_table.pid;
        _ -> undefined
    end.

-spec return_key_if_on_connected_node(Process :: #syn_processes_table{}) -> pid() | undefined.
return_key_if_on_connected_node(Process) ->
    case lists:member(Process#syn_processes_table.node, [node() | nodes()]) of
        true -> Process#syn_processes_table.key;
        _ -> undefined
    end.

-spec remove_process_by_key(Key :: any()) -> ok.
remove_process_by_key(Key) ->
    mnesia:dirty_delete(syn_processes_table, Key).
