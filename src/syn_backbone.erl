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
-export([initdb/0]).
-export([register/2, register/3]).
-export([unregister/1]).
-export([find_by_key/1, find_by_key/2]).
-export([find_by_pid/1, find_by_pid/2]).
-export([count/0, count/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% records
-record(state, {
    process_exit_callback_module = undefined :: atom(),
    process_exit_callback_function = undefined :: atom()
}).

%% include
-include("syn.hrl").


%% ===================================================================
%% API
%% ===================================================================
-spec start_link() -> {ok, pid()} | {error, any()}.
start_link() ->
    Options = [],
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], Options).

-spec initdb() -> ok | {error, any()}.
initdb() ->
    initdb_do().

-spec find_by_key(Key :: any()) -> pid() | undefined.
find_by_key(Key) ->
    case i_find_by_key(on_connected_node, Key) of
        undefined -> undefined;
        Process -> Process#syn_processes_table.pid
    end.

-spec find_by_key(Key :: any(), with_meta) -> {pid(), Meta :: any()} | undefined.
find_by_key(Key, with_meta) ->
    case i_find_by_key(on_connected_node, Key) of
        undefined -> undefined;
        Process -> {Process#syn_processes_table.pid, Process#syn_processes_table.meta}
    end.

-spec find_by_pid(Pid :: pid()) -> Key :: any() | undefined.
find_by_pid(Pid) ->
    case i_find_by_pid(on_connected_node, Pid) of
        undefined -> undefined;
        Process -> Process#syn_processes_table.key
    end.

-spec find_by_pid(Pid :: pid(), with_meta) -> {Key :: any(), Meta :: any()} | undefined.
find_by_pid(Pid, with_meta) ->
    case i_find_by_pid(on_connected_node, Pid) of
        undefined -> undefined;
        Process -> {Process#syn_processes_table.key, Process#syn_processes_table.meta}
    end.

-spec register(Key :: any(), Pid :: pid()) -> ok | {error, taken | pid_already_registered}.
register(Key, Pid) ->
    register(Key, Pid, undefined).

-spec register(Key :: any(), Pid :: pid(), Meta :: any()) -> ok | {error, taken | pid_already_registered}.
register(Key, Pid, Meta) ->
    Node = node(Pid),
    gen_server:call({?MODULE, Node}, {register_on_node, Key, Pid, Meta}).

-spec unregister(Key :: any()) -> ok | {error, undefined}.
unregister(Key) ->
    case i_find_by_key(Key) of
        undefined ->
            {error, undefined};
        Process ->
            Node = Process#syn_processes_table.node,
            gen_server:call({?MODULE, Node}, {unregister_on_node, Key})
    end.

-spec count() -> non_neg_integer().
count() ->
    mnesia:table_info(syn_processes_table, size).

-spec count(Node :: atom()) -> non_neg_integer().
count(Node) ->
    %% build match specs
    MatchHead = #syn_processes_table{node = '$2', _ = '_'},
    Guard = {'=:=', '$2', Node},
    Result = '$2',
    %% select
    Processes = mnesia:dirty_select(syn_processes_table, [{MatchHead, [Guard], [Result]}]),
    length(Processes).

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

    %% get options
    {ok, [ProcessExitCallbackModule, ProcessExitCallbackFunction]} = syn_utils:get_env_value(
        process_exit_callback,
        [undefined, undefined]
    ),

    %% build state
    {ok, #state{
        process_exit_callback_module = ProcessExitCallbackModule,
        process_exit_callback_function = ProcessExitCallbackFunction
    }}.

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

handle_call({register_on_node, Key, Pid, Meta}, _From, State) ->
    %% check & register in gen_server process to ensure atomicity at node level without transaction lock
    %% atomicity is obviously not at cluster level, which is covered by syn_consistency.
    case i_find_by_pid(Pid) of
        undefined ->
            %% add to table
            mnesia:dirty_write(#syn_processes_table{
                key = Key,
                pid = Pid,
                node = node(),
                meta = Meta
            }),
            %% link
            erlang:link(Pid),
            %% return
            {reply, ok, State};
        _ ->
            {reply, {error, pid_already_registered}, State}
    end;

handle_call({unregister_on_node, Key}, _From, State) ->
    %% we check again for key to return the correct response regardless of race conditions
    case i_find_by_key(Key) of
        undefined ->
            {reply, {error, undefined}, State};
        Process ->
            %% remove from table
            remove_process_by_key(Key),
            %% unlink
            Pid = Process#syn_processes_table.pid,
            erlang:unlink(Pid),
            %% reply
            {reply, ok, State}
    end;

handle_call({unlink_process, Pid}, _From, State) ->
    erlang:unlink(Pid),
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

handle_info({'EXIT', Pid, Reason}, #state{
    process_exit_callback_module = ProcessExitCallbackModule,
    process_exit_callback_function = ProcessExitCallbackFunction
} = State) ->
    %% do not lock backbone
    spawn(fun() ->
        %% check if pid is in table
        {Key, Meta} = case i_find_by_pid(Pid) of
            undefined ->
                %% log
                case Reason of
                    normal -> ok;
                    killed -> ok;
                    _ ->
                        error_logger:error_msg("Received an exit message from an unlinked process ~p with reason: ~p", [Pid, Reason])
                end,

                %% return
                {undefined, undefined};

            Process ->
                %% get process info
                Key0 = Process#syn_processes_table.key,
                Meta0 = Process#syn_processes_table.meta,

                %% log
                case Reason of
                    normal -> ok;
                    killed -> ok;
                    _ ->
                        error_logger:error_msg("Process with key ~p and pid ~p exited with reason: ~p", [Key0, Pid, Reason])
                end,

                %% delete from table
                remove_process_by_key(Key0),

                %% return
                {Key0, Meta0}
        end,

        %% callback
        case ProcessExitCallbackModule of
            undefined -> ok;
            _ -> ProcessExitCallbackModule:ProcessExitCallbackFunction(Key, Pid, Meta, Reason)
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
    error_logger:info_msg("Terminating syn backbone with reason: ~p", [Reason]),
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
-spec initdb_do() -> ok | {error, any()}.
initdb_do() ->
    %% get nodes
    CurrentNode = node(),
    ClusterNodes = [CurrentNode | nodes()],
    %% ensure all nodes are added
    mnesia:change_config(extra_db_nodes, ClusterNodes),
    %% ensure table exists
    case mnesia:create_table(syn_processes_table, [
        {type, set},
        {ram_copies, ClusterNodes},
        {attributes, record_info(fields, syn_processes_table)},
        {index, [#syn_processes_table.pid]},
        {storage_properties, [{ets, [{read_concurrency, true}]}]}
    ]) of
        {atomic, ok} ->
            error_logger:info_msg("syn_processes_table was successfully created"),
            ok;
        {aborted, {already_exists, syn_processes_table}} ->
            %% table already exists, try to add current node as copy
            add_table_copy_to_current_node();
        {aborted, {already_exists, syn_processes_table, CurrentNode}} ->
            %% table already exists, try to add current node as copy
            add_table_copy_to_current_node();
        Other ->
            error_logger:error_msg("Error while creating syn_processes_table: ~p", [Other]),
            {error, Other}
    end.

-spec add_table_copy_to_current_node() -> ok | {error, any()}.
add_table_copy_to_current_node() ->
    %% wait for table
    mnesia:wait_for_tables([syn_processes_table], 10000),
    %% add copy
    CurrentNode = node(),
    case mnesia:add_table_copy(syn_processes_table, CurrentNode, ram_copies) of
        {atomic, ok} ->
            error_logger:info_msg("Copy of syn_processes_table was successfully added to current node"),
            ok;
        {aborted, {already_exists, syn_processes_table}} ->
            error_logger:info_msg("Copy of syn_processes_table is already added to current node"),
            ok;
        {aborted, {already_exists, syn_processes_table, CurrentNode}} ->
            error_logger:info_msg("Copy of syn_processes_table is already added to current node"),
            ok;
        {aborted, Reason} ->
            error_logger:error_msg("Error while creating copy of syn_processes_table: ~p", [Reason]),
            {error, Reason}
    end.

-spec i_find_by_key(on_connected_node, Key :: any()) -> Process :: #syn_processes_table{} | undefined.
i_find_by_key(on_connected_node, Key) ->
    case i_find_by_key(Key) of
        undefined -> undefined;
        Process -> return_if_on_connected_node(Process)
    end.

-spec i_find_by_key(Key :: any()) -> Process :: #syn_processes_table{} | undefined.
i_find_by_key(Key) ->
    case mnesia:dirty_read(syn_processes_table, Key) of
        [Process] -> Process;
        _ -> undefined
    end.

-spec i_find_by_pid(on_connected_node, Pid :: pid()) -> Process :: #syn_processes_table{} | undefined.
i_find_by_pid(on_connected_node, Pid) ->
    case i_find_by_pid(Pid) of
        undefined -> undefined;
        Process -> return_if_on_connected_node(Process)
    end.

-spec i_find_by_pid(Pid :: pid()) -> Process :: #syn_processes_table{} | undefined.
i_find_by_pid(Pid) ->
    case mnesia:dirty_index_read(syn_processes_table, Pid, #syn_processes_table.pid) of
        [Process] -> Process;
        _ -> undefined
    end.

-spec return_if_on_connected_node(Process :: #syn_processes_table{}) -> Process :: #syn_processes_table{} | undefined.
return_if_on_connected_node(Process) ->
    case lists:member(Process#syn_processes_table.node, [node() | nodes()]) of
        true -> Process;
        _ -> undefined
    end.

-spec remove_process_by_key(Key :: any()) -> ok.
remove_process_by_key(Key) ->
    mnesia:dirty_delete(syn_processes_table, Key).
