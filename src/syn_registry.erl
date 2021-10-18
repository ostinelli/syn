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
-module(syn_registry).
-behaviour(syn_gen_scope).

%% API
-export([start_link/1]).
-export([subcluster_nodes/1]).
-export([lookup/2]).
-export([register/4]).
-export([unregister/2]).
-export([count/1, count/2]).

%% syn_gen_scope callbacks
-export([
    init/1,
    handle_call/3,
    handle_info/2,
    save_remote_data/2,
    get_local_data/1,
    purge_local_data_for_node/2
]).

%% tests
-ifdef(TEST).
-export([add_to_local_table/7, remove_from_local_table/4]).
-endif.

%% includes
-include("syn.hrl").

%% ===================================================================
%% API
%% ===================================================================
-spec start_link(Scope :: atom()) ->
    {ok, Pid :: pid()} | {error, {already_started, Pid :: pid()}} | {error, Reason :: term()}.
start_link(Scope) when is_atom(Scope) ->
    syn_gen_scope:start_link(?MODULE, Scope).

-spec subcluster_nodes(Scope :: atom()) -> [node()].
subcluster_nodes(Scope) ->
    syn_gen_scope:subcluster_nodes(?MODULE, Scope).

-spec lookup(Scope :: atom(), Name :: term()) -> {pid(), Meta :: term()} | undefined.
lookup(Scope, Name) ->
    case syn_backbone:get_table_name(syn_registry_by_name, Scope) of
        undefined ->
            error({invalid_scope, Scope});

        TableByName ->
            case find_registry_entry_by_name(Name, TableByName) of
                undefined -> undefined;
                {Name, Pid, Meta, _, _, _} -> {Pid, Meta}
            end
    end.

-spec register(Scope :: atom(), Name :: term(), Pid :: pid(), Meta :: term()) -> ok | {error, Reason :: term()}.
register(Scope, Name, Pid, Meta) ->
    Node = node(Pid),
    case syn_gen_scope:call(?MODULE, Node, Scope, {'3.0', register_on_node, node(), Name, Pid, Meta}) of
        {ok, {CallbackMethod, Time, TableByName, TableByPid}} when Node =/= node() ->
            %% update table on caller node immediately so that subsequent calls have an updated registry
            add_to_local_table(Name, Pid, Meta, Time, undefined, TableByName, TableByPid),
            %% callback
            syn_event_handler:call_event_handler(CallbackMethod, [Scope, Name, Pid, Meta, normal]),
            %% return
            ok;

        {Response, _} ->
            Response
    end.

-spec unregister(Scope :: atom(), Name :: term()) -> ok | {error, Reason :: term()}.
unregister(Scope, Name) ->
    case syn_backbone:get_table_name(syn_registry_by_name, Scope) of
        undefined ->
            error({invalid_scope, Scope});

        TableByName ->
            % get process' node
            case find_registry_entry_by_name(Name, TableByName) of
                undefined ->
                    {error, undefined};

                {Name, Pid, Meta, _, _, _} ->
                    Node = node(Pid),
                    case syn_gen_scope:call(?MODULE, Node, Scope, {'3.0', unregister_on_node, node(), Name, Pid}) of
                        {ok, TableByPid} when Node =/= node() ->
                            %% remove table on caller node immediately so that subsequent calls have an updated registry
                            remove_from_local_table(Name, Pid, TableByName, TableByPid),
                            %% callback
                            syn_event_handler:call_event_handler(on_process_unregistered, [Scope, Name, Pid, Meta, normal]),
                            %% return
                            ok;

                        {Response, _} ->
                            Response
                    end
            end
    end.

-spec count(Scope :: atom()) -> non_neg_integer().
count(Scope) ->
    TableByName = syn_backbone:get_table_name(syn_registry_by_name, Scope),
    case ets:info(TableByName, size) of
        undefined -> error({invalid_scope, Scope});
        Value -> Value
    end.

-spec count(Scope :: atom(), Node :: node()) -> non_neg_integer().
count(Scope, Node) ->
    case syn_backbone:get_table_name(syn_registry_by_name, Scope) of
        undefined ->
            error({invalid_scope, Scope});

        TableByName ->
            ets:select_count(TableByName, [{
                {'_', '_', '_', '_', '_', Node},
                [],
                [true]
            }])
    end.

%% ===================================================================
%% Callbacks
%% ===================================================================

%% ----------------------------------------------------------------------------------------------------------
%% Init
%% ----------------------------------------------------------------------------------------------------------
-spec init(#state{}) -> {ok, HandlerState :: term()}.
init(State) ->
    HandlerState = #{},
    %% rebuild
    rebuild_monitors(State),
    %% init
    {ok, HandlerState}.

%% ----------------------------------------------------------------------------------------------------------
%% Call messages
%% ----------------------------------------------------------------------------------------------------------
-spec handle_call(Request :: term(), From :: {pid(), Tag :: term()}, #state{}) ->
    {reply, Reply :: term(), #state{}} |
    {reply, Reply :: term(), #state{}, timeout() | hibernate | {continue, term()}} |
    {noreply, #state{}} |
    {noreply, #state{}, timeout() | hibernate | {continue, term()}} |
    {stop, Reason :: term(), Reply :: term(), #state{}} |
    {stop, Reason :: term(), #state{}}.
handle_call({'3.0', register_on_node, RequesterNode, Name, Pid, Meta}, _From, #state{
    table_by_name = TableByName,
    table_by_pid = TableByPid
} = State) ->
    case is_process_alive(Pid) of
        true ->
            case find_registry_entry_by_name(Name, TableByName) of
                undefined ->
                    %% available
                    MRef = case find_monitor_for_pid(Pid, TableByPid) of
                        undefined -> erlang:monitor(process, Pid);  %% process is not monitored yet, add
                        MRef0 -> MRef0
                    end,
                    do_register_on_node(Name, Pid, Meta, MRef, normal, RequesterNode, on_process_registered, State);

                {Name, Pid, Meta, _, _, _} ->
                    %% same pid, same meta
                    {reply, {ok, noop}, State};

                {Name, Pid, _, _, MRef, _} ->
                    do_register_on_node(Name, Pid, Meta, MRef, normal, RequesterNode, on_registry_process_updated, State);

                _ ->
                    {reply, {{error, taken}, undefined}, State}
            end;

        false ->
            {reply, {{error, not_alive}, undefined}, State}
    end;

handle_call({'3.0', unregister_on_node, RequesterNode, Name, Pid}, _From, #state{
    scope = Scope,
    table_by_name = TableByName,
    table_by_pid = TableByPid
} = State) ->
    case find_registry_entry_by_name(Name, TableByName) of
        undefined ->
            {reply, {{error, undefined}, undefined}, State};

        {Name, Pid, Meta, _, _, _} ->
            %% demonitor if the process is not registered under other names
            maybe_demonitor(Pid, TableByPid),
            %% remove from table
            remove_from_local_table(Name, Pid, TableByName, TableByPid),
            %% callback
            syn_event_handler:call_event_handler(on_process_unregistered, [Scope, Name, Pid, Meta, normal]),
            %% broadcast
            syn_gen_scope:broadcast({'3.0', sync_unregister, Name, Pid, Meta, normal}, [RequesterNode], State),
            %% return
            {reply, {ok, TableByPid}, State};

        _ ->
            %% process is registered locally with another pid: race condition, wait for sync to happen & return error
            {reply, {{error, race_condition}, undefined}, State}
    end;

handle_call(Request, From, #state{scope = Scope} = State) ->
    error_logger:warning_msg("SYN[~s<~s>] Received from ~p an unknown call message: ~p", [?MODULE, Scope, From, Request]),
    {reply, undefined, State}.

%% ----------------------------------------------------------------------------------------------------------
%% Info messages
%% ----------------------------------------------------------------------------------------------------------
-spec handle_info(Info :: timeout | term(), #state{}) ->
    {noreply, #state{}} |
    {noreply, #state{}, timeout() | hibernate | {continue, term()}} |
    {stop, Reason :: term(), #state{}}.
handle_info({'3.0', sync_register, Name, Pid, Meta, Time, Reason}, #state{nodes_map = NodesMap} = State) ->
    case maps:is_key(node(Pid), NodesMap) of
        true ->
            handle_registry_sync(Name, Pid, Meta, Time, Reason, State);

        false ->
            %% ignore, race condition
            ok
    end,
    {noreply, State};

handle_info({'3.0', sync_unregister, Name, Pid, Meta, Reason}, #state{
    scope = Scope,
    table_by_name = TableByName,
    table_by_pid = TableByPid
} = State) ->
    case find_registry_entry_by_name(Name, TableByName) of
        {_, Pid, _, _, _, _} ->
            remove_from_local_table(Name, Pid, TableByName, TableByPid),
            %% callback
            syn_event_handler:call_event_handler(on_process_unregistered, [Scope, Name, Pid, Meta, Reason]);

        _ ->
            %% not in table, nothing to do
            ok
    end,
    %% return
    {noreply, State};

handle_info({'DOWN', _MRef, process, Pid, Reason}, #state{
    scope = Scope,
    table_by_name = TableByName,
    table_by_pid = TableByPid
} = State) ->
    case find_registry_entries_by_pid(Pid, TableByPid) of
        [] ->
            error_logger:warning_msg(
                "SYN[~s<~s>] Received a DOWN message from an unknown process ~p with reason: ~p",
                [?MODULE, Scope, Pid, Reason]
            );

        Entries ->
            lists:foreach(fun({_, Name, Meta, _, _, _}) ->
                %% remove from table
                remove_from_local_table(Name, Pid, TableByName, TableByPid),
                %% callback
                syn_event_handler:call_event_handler(on_process_unregistered, [Scope, Name, Pid, Meta, Reason]),
                %% broadcast
                syn_gen_scope:broadcast({'3.0', sync_unregister, Name, Pid, Meta, Reason}, State)
            end, Entries)
    end,
    %% return
    {noreply, State};

handle_info(Info, #state{scope = Scope} = State) ->
    error_logger:warning_msg("SYN[~s<~s>] Received an unknown info message: ~p", [?MODULE, Scope, Info]),
    {noreply, State}.

%% ----------------------------------------------------------------------------------------------------------
%% Data callbacks
%% ----------------------------------------------------------------------------------------------------------
-spec get_local_data(#state{}) -> {ok, Data :: term()} | undefined.
get_local_data(#state{table_by_name = TableByName}) ->
    {ok, get_registry_tuples_for_node(node(), TableByName)}.

-spec save_remote_data(RemoteData :: term(), #state{}) -> any().
save_remote_data(RegistryTuplesOfRemoteNode, #state{scope = Scope} = State) ->
    %% insert tuples
    lists:foreach(fun({Name, Pid, Meta, Time}) ->
        handle_registry_sync(Name, Pid, Meta, Time, {syn_remote_scope_node_up, Scope, node(Pid)}, State)
    end, RegistryTuplesOfRemoteNode).

-spec purge_local_data_for_node(Node :: node(), #state{}) -> any().
purge_local_data_for_node(Node, #state{
    scope = Scope,
    table_by_name = TableByName,
    table_by_pid = TableByPid
}) ->
    purge_registry_for_remote_node(Scope, Node, TableByName, TableByPid).

%% ===================================================================
%% Internal
%% ===================================================================
-spec rebuild_monitors(#state{}) -> ok.
rebuild_monitors(#state{
    table_by_name = TableByName
} = State) ->
    RegistryTuples = get_registry_tuples_for_node(node(), TableByName),
    do_rebuild_monitors(RegistryTuples, #{}, State).

-spec do_rebuild_monitors([syn_registry_tuple()], #{pid() => reference()}, #state{}) -> ok.
do_rebuild_monitors([], _, _) -> ok;
do_rebuild_monitors([{Name, Pid, Meta, Time} | T], NewMonitorRefs, #state{
    table_by_name = TableByName,
    table_by_pid = TableByPid
} = State) ->
    remove_from_local_table(Name, Pid, TableByName, TableByPid),
    case is_process_alive(Pid) of
        true ->
            case maps:find(Pid, NewMonitorRefs) of
                error ->
                    MRef = erlang:monitor(process, Pid),
                    add_to_local_table(Name, Pid, Meta, Time, MRef, TableByName, TableByPid),
                    do_rebuild_monitors(T, maps:put(Pid, MRef, NewMonitorRefs), State);

                {ok, MRef} ->
                    add_to_local_table(Name, Pid, Meta, Time, MRef, TableByName, TableByPid),
                    do_rebuild_monitors(T, NewMonitorRefs, State)
            end;

        _ ->
            do_rebuild_monitors(T, NewMonitorRefs, State)
    end.

-spec do_register_on_node(
    Name :: term(),
    Pid :: pid(),
    Meta :: term(),
    MRef :: reference() | undefined,
    Reason :: term(),
    RequesterNode :: node(),
    CallbackMethod :: atom(),
    #state{}
) ->
    {
        reply,
        {ok, {
            CallbackMethod :: atom(),
            Time :: non_neg_integer(),
            TableByName :: atom(),
            TableByPid :: atom()
        }},
        #state{}
    }.
do_register_on_node(Name, Pid, Meta, MRef, Reason, RequesterNode, CallbackMethod, #state{
    scope = Scope,
    table_by_name = TableByName,
    table_by_pid = TableByPid
} = State) ->
    %% add to local table
    Time = erlang:system_time(),
    add_to_local_table(Name, Pid, Meta, Time, MRef, TableByName, TableByPid),
    %% callback
    syn_event_handler:call_event_handler(CallbackMethod, [Scope, Name, Pid, Meta, Reason]),
    %% broadcast
    syn_gen_scope:broadcast({'3.0', sync_register, Name, Pid, Meta, Time, Reason}, [RequesterNode], State),
    %% return
    {reply, {ok, {CallbackMethod, Time, TableByName, TableByPid}}, State}.

-spec get_registry_tuples_for_node(Node :: node(), TableByName :: atom()) -> [syn_registry_tuple()].
get_registry_tuples_for_node(Node, TableByName) ->
    ets:select(TableByName, [{
        {'$1', '$2', '$3', '$4', '_', Node},
        [],
        [{{'$1', '$2', '$3', '$4'}}]
    }]).

-spec find_registry_entry_by_name(Name :: term(), TableByName :: atom()) ->
    Entry :: syn_registry_entry() | undefined.
find_registry_entry_by_name(Name, TableByName) ->
    case ets:lookup(TableByName, Name) of
        [] -> undefined;
        [Entry] -> Entry
    end.

-spec find_registry_entries_by_pid(Pid :: pid(), TableByPid :: atom()) -> RegistryEntriesByPid :: [syn_registry_entry_by_pid()].
find_registry_entries_by_pid(Pid, TableByPid) when is_pid(Pid) ->
    ets:lookup(TableByPid, Pid).

-spec find_monitor_for_pid(Pid :: pid(), TableByPid :: atom()) -> reference() | undefined.
find_monitor_for_pid(Pid, TableByPid) when is_pid(Pid) ->
    %% we use select instead of lookup to limit the results and thus cover the case
    %% when a process is registered with a considerable amount of names
    case ets:select(TableByPid, [{
        {Pid, '_', '_', '_', '$5', '_'},
        [],
        ['$5']
    }], 1) of
        {[MRef], _} -> MRef;
        '$end_of_table' -> undefined
    end.

-spec maybe_demonitor(Pid :: pid(), TableByPid :: atom()) -> ok.
maybe_demonitor(Pid, TableByPid) ->
    %% select 2: if only 1 is returned it means that no other aliases exist for the Pid
    %% we use select instead of lookup to limit the results and thus cover the case
    %% when a process is registered with a considerable amount of names
    case ets:select(TableByPid, [{
        {Pid, '_', '_', '_', '$5', '_'},
        [],
        ['$5']
    }], 2) of
        {[MRef], _} when is_reference(MRef) ->
            %% no other aliases, demonitor
            erlang:demonitor(MRef, [flush]),
            ok;

        _ ->
            ok
    end.

-spec add_to_local_table(
    Name :: term(),
    Pid :: pid(),
    Meta :: term(),
    Time :: integer(),
    MRef :: undefined | reference(),
    TableByName :: atom(),
    TableByPid :: atom()
) -> true.
add_to_local_table(Name, Pid, Meta, Time, MRef, TableByName, TableByPid) ->
    %% insert
    true = ets:insert(TableByName, {Name, Pid, Meta, Time, MRef, node(Pid)}),
    %% since we use a table of type bag, we need to manually ensure that the key Pid, Name is unique
    true = ets:match_delete(TableByPid, {Pid, Name, '_', '_', '_', '_'}),
    true = ets:insert(TableByPid, {Pid, Name, Meta, Time, MRef, node(Pid)}).

-spec remove_from_local_table(
    Name :: term(),
    Pid :: pid(),
    TableByName :: atom(),
    TableByPid :: atom()
) -> true.
remove_from_local_table(Name, Pid, TableByName, TableByPid) ->
    true = ets:match_delete(TableByName, {Name, Pid, '_', '_', '_', '_'}),
    true = ets:match_delete(TableByPid, {Pid, Name, '_', '_', '_', '_'}).

-spec update_local_table(
    Name :: term(),
    PreviousPid :: pid(),
    {
        Pid :: pid(),
        Meta :: term(),
        Time :: integer(),
        MRef :: undefined | reference()
    },
    TableByName :: atom(),
    TableByPid :: atom()
) -> true.
update_local_table(Name, PreviousPid, {Pid, Meta, Time, MRef}, TableByName, TableByPid) ->
    maybe_demonitor(PreviousPid, TableByPid),
    remove_from_local_table(Name, PreviousPid, TableByName, TableByPid),
    add_to_local_table(Name, Pid, Meta, Time, MRef, TableByName, TableByPid).

-spec purge_registry_for_remote_node(Scope :: atom(), Node :: atom(), TableByName :: atom(), TableByPid :: atom()) -> true.
purge_registry_for_remote_node(Scope, Node, TableByName, TableByPid) when Node =/= node() ->
    %% loop elements for callback in a separate process to free scope process
    RegistryTuples = get_registry_tuples_for_node(Node, TableByName),
    spawn(fun() ->
        lists:foreach(fun({Name, Pid, Meta, _Time}) ->
            syn_event_handler:call_event_handler(on_process_unregistered,
                [Scope, Name, Pid, Meta, {syn_remote_scope_node_down, Scope, Node}]
            )
        end, RegistryTuples)
    end),
    %% remove all from pid table
    true = ets:match_delete(TableByName, {'_', '_', '_', '_', '_', Node}),
    true = ets:match_delete(TableByPid, {'_', '_', '_', '_', '_', Node}).

-spec handle_registry_sync(
    Name :: term(),
    Pid :: pid(),
    Meta :: term(),
    Time :: non_neg_integer(),
    Reason :: term(),
    #state{}
) -> any().
handle_registry_sync(Name, Pid, Meta, Time, Reason, #state{
    scope = Scope,
    table_by_name = TableByName,
    table_by_pid = TableByPid
} = State) ->
    case find_registry_entry_by_name(Name, TableByName) of
        undefined ->
            %% no conflict
            add_to_local_table(Name, Pid, Meta, Time, undefined, TableByName, TableByPid),
            %% callback
            syn_event_handler:call_event_handler(on_process_registered, [Scope, Name, Pid, Meta, Reason]);

        {_, Pid, TableMeta, _, MRef, _} ->
            %% same pid, more recent (because it comes from the same node, which means that it's sequential)
            %% maybe updated meta or time only
            add_to_local_table(Name, Pid, Meta, Time, MRef, TableByName, TableByPid),
            %% callback (call only if meta update)
            case TableMeta =/= Meta of
                true ->
                    syn_event_handler:call_event_handler(on_registry_process_updated, [Scope, Name, Pid, Meta, Reason]);
                _ -> ok
            end;

        {_, TablePid, TableMeta, TableTime, TableMRef, TableNode} when TableNode =:= node() ->
            %% current node runs a conflicting process -> resolve
            %% * the conflict is resolved by the two nodes that own the conflicting processes
            %% * when a process is chosen, the time is updated
            %% * the node that runs the process that is kept sends the sync_register message
            %% * recipients check that the time is more recent that what they have to ensure that there are no race conditions
            resolve_conflict(Scope, Name, {Pid, Meta, Time}, {TablePid, TableMeta, TableTime, TableMRef}, State);

        {_, TablePid, TableMeta, TableTime, _, _} when TableTime < Time ->
            %% current node does not own any of the conflicting processes, update
            update_local_table(Name, TablePid, {Pid, Meta, Time, undefined}, TableByName, TableByPid),
            %% callbacks
            syn_event_handler:call_event_handler(on_process_unregistered, [Scope, Name, TablePid, TableMeta, Reason]),
            syn_event_handler:call_event_handler(on_process_registered, [Scope, Name, Pid, Meta, Reason]);

        _ ->
            %% race condition: incoming data is older, ignore
            ok
    end.

-spec resolve_conflict(
    Scope :: atom(),
    Name :: term(),
    {Pid :: pid(), Meta :: term(), Time :: non_neg_integer()},
    {TablePid :: pid(), TableMeta :: term(), TableTime :: non_neg_integer(), TableMRef :: reference()},
    #state{}
) -> any().
resolve_conflict(Scope, Name, {Pid, Meta, Time}, {TablePid, TableMeta, TableTime, TableMRef}, #state{
    table_by_name = TableByName,
    table_by_pid = TableByPid
} = State) ->
    %% call conflict resolution
    {PidToKeep, KillOtherPid} = syn_event_handler:do_resolve_registry_conflict(
        Scope,
        Name,
        {Pid, Meta, Time},
        {TablePid, TableMeta, TableTime}
    ),
    %% resolve
    case PidToKeep of
        Pid ->
            %% -> we keep the remote pid
            error_logger:info_msg("SYN[~s<~s>] Registry CONFLICT for name ~p: ~p vs ~p -> keeping remote: ~p",
                [?MODULE, Scope, Name, Pid, TablePid, Pid]
            ),
            %% update locally, the incoming sync_register will update with the time coming from remote node
            update_local_table(Name, TablePid, {Pid, Meta, Time, undefined}, TableByName, TableByPid),
            %% kill
            case KillOtherPid of
                true -> exit(TablePid, {syn_resolve_kill, Name, TableMeta});
                false -> ok
            end,
            %% callbacks
            syn_event_handler:call_event_handler(on_process_unregistered, [Scope, Name, TablePid, TableMeta, syn_conflict_resolution]),
            syn_event_handler:call_event_handler(on_process_registered, [Scope, Name, Pid, Meta, syn_conflict_resolution]);

        TablePid ->
            %% -> we keep the local pid, remote pid will be killed by the other node in the conflict
            error_logger:info_msg("SYN[~s<~s>] Registry CONFLICT for name ~p: ~p vs ~p -> keeping local: ~p",
                [?MODULE, Scope, Name, Pid, TablePid, TablePid]
            ),
            %% overwrite with updated time
            ResolveTime = erlang:system_time(),
            add_to_local_table(Name, TablePid, TableMeta, ResolveTime, TableMRef, TableByName, TableByPid),
            %% broadcast to all (including remote node to update the time)
            syn_gen_scope:broadcast({'3.0', sync_register, Name, TablePid, TableMeta, ResolveTime, syn_conflict_resolution}, State);

        Invalid ->
            error_logger:info_msg("SYN[~s<~s>] Registry CONFLICT for name ~p: ~p vs ~p -> none chosen (got: ~p)",
                [?MODULE, Scope, Name, Pid, TablePid, Invalid]
            ),
            %% remove
            maybe_demonitor(TablePid, TableByPid),
            remove_from_local_table(Name, TablePid, TableByName, TableByPid),
            %% kill local, remote will be killed by other node performing the same resolve
            case KillOtherPid of
                true -> exit(TablePid, {syn_resolve_kill, Name, TableMeta});
                false -> ok
            end,
            %% callback
            syn_event_handler:call_event_handler(on_process_unregistered, [Scope, Name, TablePid, TableMeta, syn_conflict_resolution]),
            %% broadcast to all but remote node, which will remove it during conflict resolution
            syn_gen_scope:broadcast({'3.0', sync_unregister, Name, TablePid, TableMeta, syn_conflict_resolution}, [node(Pid)], State)
    end.
