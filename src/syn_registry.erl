%% ==========================================================================================================
%% Syn - A global Process Registry and Process Group manager.
%%
%% The MIT License (MIT)
%%
%% Copyright (c) 2015-2026 Roberto Ostinelli <roberto@ostinelli.net> and Neato Robotics, Inc.
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
-module(syn_registry).
-behaviour(syn_gen_scope).

%% API
-export([start_link/1]).
-export([subcluster_nodes/1]).
-export([lookup/2]).
-export([register/4]).
-export([update/3]).
-export([unregister/2]).
-export([count/1, count/2]).

%% syn_gen_scope callbacks
-export([
    init/1,
    handle_call/3,
    handle_info/2,
    save_remote_data/3,
    get_local_data/1,
    purge_local_data_for_node/2
]).

%% macros
-define(MODULE_LOG_NAME, registry).

%% tests
-ifdef(TEST).
-export([add_to_local_table/7, remove_from_local_table/4]).
-endif.

%% includes
-include("syn.hrl").

-include_lib("kernel/include/logger.hrl").

%% ===================================================================
%% API
%% ===================================================================
-spec start_link(Scope :: atom()) ->
    {ok, Pid :: pid()} | {error, {already_started, Pid :: pid()}} | {error, Reason :: term()}.
start_link(Scope) when is_atom(Scope) ->
    syn_gen_scope:start_link(?MODULE, ?MODULE_LOG_NAME, Scope).

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
                {Name, Pid, Meta, _, _, Node} ->
                    % This read can be initiated prior to registration, by a
                    % supervisor or supervisor-like process trying to restart a
                    % stopped process in response to a 'DOWN', while the 'DOWN'
                    % handler in this module is yet to update TableByName.
                    %
                    % Verifying aliveness avoids confusing already_started
                    % errors while restarting registered processes.
                    % The aliveness check is only necessary when the Pid is
                    % local.
                    case Node =:= node() andalso not is_process_alive(Pid) of
                        true -> undefined;
                        false -> {Pid, Meta}
                    end
            end
    end.

-spec register(Scope :: atom(), Name :: term(), Pid :: pid(), Meta :: term()) -> ok | {error, Reason :: term()}.
register(Scope, Name, Pid, Meta) ->
    case register_or_update(Scope, Name, Pid, Meta) of
        {ok, _} -> ok;
        {error, Reason} -> {error, Reason}
    end.

-spec update(Scope :: atom(), Name :: term(), Fun :: function()) ->
    {ok, {Pid :: pid(), Meta :: term()}} | {error, Reason :: term()}.
update(Scope, Name, Fun) ->
    case syn_backbone:get_table_name(syn_registry_by_name, Scope) of
        undefined ->
            error({invalid_scope, Scope});

        TableByName ->
            % get process' node
            case find_registry_entry_by_name(Name, TableByName) of
                undefined ->
                    {error, undefined};

                {Name, Pid, _, _, _, _} ->
                    register_or_update(Scope, Name, Pid, Fun)
            end
    end.

-spec register_or_update(Scope :: atom(), Name :: term(), Pid :: pid(), MetaOrFun :: term() | function()) ->
    {ok, {Pid :: pid(), Meta :: term()}} | {error, Reason :: term()}.
register_or_update(Scope, Name, Pid, MetaOrFun) ->
    case syn_backbone:is_strict_mode() of
        true when Pid =/= self() ->
            {error, not_self};

        _ ->
            Node = node(Pid),
            case Node =/= node() andalso not syn_gen_scope:is_scope_process(?MODULE, Scope) of
                true -> register_or_update_ordered(Scope, Node, Name, Pid, MetaOrFun);
                false -> register_or_update_direct(Scope, Node, Name, Pid, MetaOrFun)
            end
    end.

%% the scope process of this node applies the result, in order with everything else the process' node sends it,
%% and replies once it has: a lookup on this node right after the call sees it
-spec register_or_update_ordered(Scope :: atom(), Node :: node(), Name :: term(), Pid :: pid(), MetaOrFun :: term() | function()) ->
    {ok, {Pid :: pid(), Meta :: term()}} | {error, Reason :: term()}.
register_or_update_ordered(Scope, Node, Name, Pid, MetaOrFun) ->
    case syn_gen_scope:call(?MODULE, Node, Scope, {'3.0', register_or_update_on_node_ordered, node(), Name, Pid, MetaOrFun}) of
        {ok, {Pid, Meta}} ->
            {ok, {Pid, Meta}};

        {error, Reason} ->
            {error, Reason};

        {raise, Class, Reason, Stacktrace} ->
            erlang:raise(Class, Reason, Stacktrace);

        undefined ->
            %% the process' node runs a version that doesn't know this call
            register_or_update_direct(Scope, Node, Name, Pid, MetaOrFun)
    end.

%% the process' node replies to the caller directly: used for local processes, from the scope process itself
%% (which can't wait for its own reply) and with nodes that don't know the ordered call
-spec register_or_update_direct(Scope :: atom(), Node :: node(), Name :: term(), Pid :: pid(), MetaOrFun :: term() | function()) ->
    {ok, {Pid :: pid(), Meta :: term()}} | {error, Reason :: term()}.
register_or_update_direct(Scope, Node, Name, Pid, MetaOrFun) ->
    case syn_gen_scope:call(?MODULE, Node, Scope, {'3.0', register_or_update_on_node, node(), Name, Pid, MetaOrFun}) of
        {ok, {CallbackMethod, PreviousMeta, Meta, Time, TableByName, TableByPid}} when Node =/= node() ->
            %% update table on caller node immediately so that subsequent calls have an updated registry,
            %% marked so that a snapshot sent before this change doesn't remove it
            add_to_local_table(Name, Pid, Meta, Time, caller, TableByName, TableByPid),
            %% callback
            syn_event_handler:call_event_handler(CallbackMethod, [Scope, Name, Pid, Meta, normal]),
            syn_event_handler:call_event_handler(CallbackMethod, [Scope, Name, Pid, PreviousMeta, Meta, normal]),
            %% return
            {ok, {Pid, Meta}};

        {ok, {_, _, Meta, _, _, _}} ->
            {ok, {Pid, Meta}};

        {noop, Meta} ->
            {ok, {Pid, Meta}};

        {error, Reason} ->
            {error, Reason};

        {raise, Class, Reason, Stacktrace} ->
            erlang:raise(Class, Reason, Stacktrace)
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
                    case Node =/= node() andalso not syn_gen_scope:is_scope_process(?MODULE, Scope) of
                        true -> unregister_ordered(Scope, Node, Name, Pid, Meta, TableByName);
                        false -> unregister_direct(Scope, Node, Name, Pid, Meta, TableByName)
                    end
            end
    end.

-spec unregister_ordered(Scope :: atom(), Node :: node(), Name :: term(), Pid :: pid(), Meta :: term(), TableByName :: atom()) ->
    ok | {error, Reason :: term()}.
unregister_ordered(Scope, Node, Name, Pid, Meta, TableByName) ->
    case syn_gen_scope:call(?MODULE, Node, Scope, {'3.0', unregister_on_node_ordered, node(), Name, Pid}) of
        ok ->
            ok;

        {error, Reason} ->
            {error, Reason};

        undefined ->
            %% the process' node runs a version that doesn't know this call
            unregister_direct(Scope, Node, Name, Pid, Meta, TableByName)
    end.

-spec unregister_direct(Scope :: atom(), Node :: node(), Name :: term(), Pid :: pid(), Meta :: term(), TableByName :: atom()) ->
    ok | {error, Reason :: term()}.
unregister_direct(Scope, Node, Name, Pid, Meta, TableByName) ->
    case syn_gen_scope:call(?MODULE, Node, Scope, {'3.0', unregister_on_node, node(), Name, Pid}) of
        {ok, TableByPid} when Node =/= node() ->
            %% remove table on caller node immediately so that subsequent calls have an updated registry
            remove_from_local_table(Name, Pid, TableByName, TableByPid),
            %% callback
            syn_event_handler:call_event_handler(on_process_unregistered, [Scope, Name, Pid, Meta, normal]),
            %% return
            ok;

        {ok, _} ->
            ok;

        {error, Reason} ->
            {error, Reason}
    end.

-spec count(Scope :: atom()) -> non_neg_integer().
count(Scope) ->
    case syn_backbone:get_table_name(syn_registry_by_name, Scope) of
        undefined ->
            error({invalid_scope, Scope});

        TableByName ->
            ets:info(TableByName, size)
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
init(#state{
    scope = Scope,
    table_by_name = TableByName,
    table_by_pid = TableByPid
}) ->
    %% purge remote & rebuild
    purge_registry_for_remote_nodes(Scope, TableByName, TableByPid),
    rebuild_monitors(Scope, TableByName, TableByPid),
    %% init
    HandlerState = #{},
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
handle_call({'3.0', register_or_update_on_node, RequesterNode, Name, Pid, MetaOrFun}, _From, #state{
    table_by_name = TableByName,
    table_by_pid = TableByPid
} = State) ->
    case register_or_update_on_node(RequesterNode, Name, Pid, MetaOrFun, State) of
        {ok, {CallbackMethod, PreviousMeta, Meta, Time}} ->
            {reply, {ok, {CallbackMethod, PreviousMeta, Meta, Time, TableByName, TableByPid}}, State};

        {noop, Meta, _Time} ->
            {reply, {noop, Meta}, State};

        Error ->
            {reply, Error, State}
    end;

handle_call({'3.0', register_or_update_on_node_ordered, RequesterNode, Name, Pid, MetaOrFun}, From, State) ->
    case register_or_update_on_node(RequesterNode, Name, Pid, MetaOrFun, State) of
        {ok, {_, _, Meta, Time}} ->
            %% the requester's scope process applies it after everything sent to it before, then replies
            syn_gen_scope:send_to_node(RequesterNode, {'3.0', sync_register_reply, Name, Pid, Meta, Time, From}, State),
            {noreply, State};

        {noop, Meta, Time} ->
            %% sent anyway, the requester may be missing the entry
            syn_gen_scope:send_to_node(RequesterNode, {'3.0', sync_register_reply, Name, Pid, Meta, Time, From}, State),
            {noreply, State};

        Error ->
            {reply, Error, State}
    end;

handle_call({'3.0', unregister_on_node, RequesterNode, Name, Pid}, _From, #state{
    table_by_pid = TableByPid
} = State) ->
    case unregister_on_node(RequesterNode, Name, Pid, State) of
        {ok, _Meta} -> {reply, {ok, TableByPid}, State};
        {error, Reason} -> {reply, {error, Reason}, State}
    end;

handle_call({'3.0', unregister_on_node_ordered, RequesterNode, Name, Pid}, From, State) ->
    case unregister_on_node(RequesterNode, Name, Pid, State) of
        {ok, Meta} ->
            %% the requester's scope process applies it after everything sent to it before, then replies
            syn_gen_scope:send_to_node(RequesterNode, {'3.0', sync_unregister_reply, Name, Pid, Meta, From}, State),
            {noreply, State};

        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call(Request, From, #state{scope = Scope} = State) ->
    ?LOG_WARNING(#{handler => ?MODULE_LOG_NAME, scope => Scope,
                   event => unknown_call, from => From, msg => Request}),
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
            %% ignore, node not yet discovered (ack_sync not yet received)
            ok
    end,
    {noreply, State};

handle_info({'3.0', sync_register_reply, Name, Pid, Meta, Time, From}, #state{
    table_by_name = TableByName,
    nodes_map = NodesMap
} = State) ->
    Reply = case maps:is_key(node(Pid), NodesMap) of
        true ->
            handle_registry_sync(Name, Pid, Meta, Time, normal, State),
            case find_registry_entry_by_name(Name, TableByName) of
                {Name, Pid, _, _, _, _} ->
                    {ok, {Pid, Meta}};

                _ ->
                    %% a conflict resolved here did not keep it
                    {error, race_condition}
            end;

        false ->
            %% node not yet discovered, its ack_sync brings the entry
            {ok, {Pid, Meta}}
    end,
    gen_server:reply(From, Reply),
    {noreply, State};

handle_info({'3.0', sync_unregister, Name, Pid, Meta, Reason}, State) ->
    handle_registry_unregister_sync(Name, Pid, Meta, Reason, State),
    {noreply, State};

handle_info({'3.0', sync_unregister_reply, Name, Pid, Meta, From}, State) ->
    handle_registry_unregister_sync(Name, Pid, Meta, normal, State),
    gen_server:reply(From, ok),
    {noreply, State};

handle_info({'DOWN', _MRef, process, Pid, Reason}, #state{
    scope = Scope,
    table_by_name = TableByName,
    table_by_pid = TableByPid
} = State) ->
    case find_registry_entries_by_pid(Pid, TableByPid) of
        [] ->
            ?LOG_WARNING(#{handler => ?MODULE_LOG_NAME, scope => Scope,
                           event => unknown_down, pid => Pid, reason => Reason});

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
    ?LOG_WARNING(#{handler => ?MODULE_LOG_NAME, scope => Scope,
                   event => unknown_info, msg => Info}),
    {noreply, State}.

%% ----------------------------------------------------------------------------------------------------------
%% Data callbacks
%% ----------------------------------------------------------------------------------------------------------
-spec get_local_data(#state{}) -> {ok, Data :: term()} | undefined.
get_local_data(#state{table_by_name = TableByName}) ->
    {ok, get_registry_tuples_for_node(node(), TableByName)}.

-spec save_remote_data(RemoteNode :: node(), RemoteData :: term(), #state{}) -> any().
save_remote_data(RemoteNode, RegistryTuplesOfRemoteNode, #state{scope = Scope} = State) ->
    reconcile_remote_registry_snapshot(RemoteNode, RegistryTuplesOfRemoteNode, State),
    %% insert/update tuples
    lists:foreach(fun({Name, Pid, Meta, Time}) ->
        handle_registry_sync(Name, Pid, Meta, Time, {syn_remote_scope_node_up, Scope, RemoteNode}, State)
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
-spec rebuild_monitors(Scope :: atom(), TableByName :: atom(), TableByPid :: atom()) -> ok.
rebuild_monitors(Scope, TableByName, TableByPid) ->
    RegistryTuples = get_registry_tuples_for_node(node(), TableByName),
    do_rebuild_monitors(RegistryTuples, #{}, Scope, TableByName, TableByPid).

-spec do_rebuild_monitors(
    [syn_registry_tuple()],
    #{pid() => reference()},
    Scope :: atom(),
    TableByName :: atom(),
    TableByPid :: atom()
) -> ok.
do_rebuild_monitors([], _, _, _, _) -> ok;
do_rebuild_monitors([{Name, Pid, Meta, Time} | T], NewMRefs, Scope, TableByName, TableByPid) ->
    remove_from_local_table(Name, Pid, TableByName, TableByPid),
    case is_process_alive(Pid) of
        true ->
            case maps:find(Pid, NewMRefs) of
                error ->
                    MRef = erlang:monitor(process, Pid),
                    add_to_local_table(Name, Pid, Meta, Time, MRef, TableByName, TableByPid),
                    do_rebuild_monitors(T, maps:put(Pid, MRef, NewMRefs), Scope, TableByName, TableByPid);

                {ok, MRef} ->
                    add_to_local_table(Name, Pid, Meta, Time, MRef, TableByName, TableByPid),
                    do_rebuild_monitors(T, NewMRefs, Scope, TableByName, TableByPid)
            end;

        _ ->
            %% process died meanwhile, callback locally
            %% the remote callbacks will have been called when the scope process crash triggered them
            syn_event_handler:call_event_handler(on_process_unregistered, [Scope, Name, Pid, Meta, undefined]),
            %% loop
            do_rebuild_monitors(T, NewMRefs, Scope, TableByName, TableByPid)
    end.

-spec register_or_update_on_node(
    RequesterNode :: node(),
    Name :: term(),
    Pid :: pid(),
    MetaOrFun :: term() | function(),
    #state{}
) ->
    {ok, {CallbackMethod :: atom(), PreviousMeta :: term(), Meta :: term(), Time :: integer()}} |
    {noop, Meta :: term(), Time :: integer()} |
    {error, Reason :: term()} |
    {raise, Class :: atom(), Reason :: term(), Stacktrace :: list()}.
register_or_update_on_node(RequesterNode, Name, Pid, MetaOrFun, #state{
    table_by_name = TableByName,
    table_by_pid = TableByPid
} = State) ->
    case is_process_alive(Pid) of
        true ->
            case find_registry_entry_by_name(Name, TableByName) of
                undefined when is_function(MetaOrFun) ->
                    {error, undefined};

                undefined ->
                    %% available
                    MRef = case find_monitor_for_pid(Pid, TableByPid) of
                        undefined -> erlang:monitor(process, Pid);  %% process is not monitored yet, add
                        MRef0 -> MRef0
                    end,
                    do_register_on_node(Name, Pid, undefined, MetaOrFun, MRef, normal, RequesterNode, on_process_registered, State);

                {Name, Pid, TableMeta, TableTime, MRef, _} when is_function(MetaOrFun) ->
                    %% update with fun
                    try MetaOrFun(Pid, TableMeta) of
                        Meta when Meta =:= TableMeta ->
                            {noop, TableMeta, TableTime};

                        Meta ->
                            do_register_on_node(Name, Pid, TableMeta, Meta, MRef, normal, RequesterNode, on_registry_process_updated, State)

                    catch Class:Reason:Stacktrace ->
                              ?LOG_ERROR(#{event => callback_error,
                                           class => Class, reason => Reason,
                                           callback => {registry_update, [Pid, TableMeta]},
                                           stacktrace => Stacktrace}),
                        {raise, Class, Reason, Stacktrace}
                    end;

                {Name, Pid, MetaOrFun, TableTime, _, _} ->
                    %% same pid, same meta
                    {noop, MetaOrFun, TableTime};

                {Name, Pid, TableMeta, _, MRef, _} ->
                    %% same pid, different meta
                    do_register_on_node(Name, Pid, TableMeta, MetaOrFun, MRef, normal, RequesterNode, on_registry_process_updated, State);

                _ ->
                    {error, taken}
            end;

        false ->
            {error, not_alive}
    end.

-spec unregister_on_node(RequesterNode :: node(), Name :: term(), Pid :: pid(), #state{}) ->
    {ok, Meta :: term()} | {error, Reason :: term()}.
unregister_on_node(RequesterNode, Name, Pid, #state{
    scope = Scope,
    table_by_name = TableByName,
    table_by_pid = TableByPid
} = State) ->
    case find_registry_entry_by_name(Name, TableByName) of
        undefined ->
            {error, undefined};

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
            {ok, Meta};

        _ ->
            %% process is registered locally with another pid: race condition, wait for sync to happen & return error
            {error, race_condition}
    end.

-spec do_register_on_node(
    Name :: term(),
    Pid :: pid(),
    PreviousMeta :: term(),
    Meta :: term(),
    MRef :: reference() | undefined,
    Reason :: term(),
    RequesterNode :: node(),
    CallbackMethod :: atom(),
    #state{}
) ->
    {ok, {CallbackMethod :: atom(), PreviousMeta :: term(), Meta :: term(), Time :: integer()}}.
do_register_on_node(Name, Pid, PreviousMeta, Meta, MRef, Reason, RequesterNode, CallbackMethod, #state{
    scope = Scope,
    table_by_name = TableByName,
    table_by_pid = TableByPid
} = State) ->
    %% add to local table
    Time = erlang:system_time(),
    add_to_local_table(Name, Pid, Meta, Time, MRef, TableByName, TableByPid),
    %% callback
    syn_event_handler:call_event_handler(CallbackMethod, [Scope, Name, Pid, Meta, Reason]),
    syn_event_handler:call_event_handler(CallbackMethod, [Scope, Name, Pid, PreviousMeta, Meta, normal]),
    %% broadcast
    syn_gen_scope:broadcast({'3.0', sync_register, Name, Pid, Meta, Time, Reason}, [RequesterNode], State),
    %% return
    {ok, {CallbackMethod, PreviousMeta, Meta, Time}}.

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
    MRef :: undefined | reference() | caller,
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

-spec purge_registry_for_remote_nodes(Scope :: atom(), TableByName :: atom(), TableByPid :: atom()) -> any().
purge_registry_for_remote_nodes(Scope, TableByName, TableByPid) ->
    LocalNode = node(),
    RemoteNodesWithDoubles = ets:select(TableByName, [{
        {'_', '_', '_', '_', '_', '$6'},
        [{'=/=', '$6', LocalNode}],
        ['$6']
    }]),
    RemoteNodes = ordsets:from_list(RemoteNodesWithDoubles),
    ordsets:fold(fun(RemoteNode, _) ->
        purge_registry_for_remote_node(Scope, RemoteNode, TableByName, TableByPid)
    end, undefined, RemoteNodes).

-spec purge_registry_for_remote_node(Scope :: atom(), Node :: atom(), TableByName :: atom(), TableByPid :: atom()) -> true.
purge_registry_for_remote_node(Scope, Node, TableByName, TableByPid) when Node =/= node() ->
    %% loop elements for callback
    RegistryTuples = get_registry_tuples_for_node(Node, TableByName),
    lists:foreach(fun({Name, Pid, Meta, _Time}) ->
        syn_event_handler:call_event_handler(on_process_unregistered,
            [Scope, Name, Pid, Meta, {syn_remote_scope_node_down, Scope, Node}]
        )
    end, RegistryTuples),
    %% remove all from pid table
    true = ets:match_delete(TableByName, {'_', '_', '_', '_', '_', Node}),
    true = ets:match_delete(TableByPid, {'_', '_', '_', '_', '_', Node}).

-spec reconcile_remote_registry_snapshot(Node :: node(), [syn_registry_tuple()], #state{}) -> ok.
reconcile_remote_registry_snapshot(Node, RegistryTuplesOfRemoteNode, #state{
    scope = Scope,
    table_by_name = TableByName,
    table_by_pid = TableByPid
}) ->
    ExistingEntries = ets:select(TableByName, [{
        {'$1', '$2', '$3', '$4', '$5', Node},
        [],
        [{{'$1', '$2', '$3', '$4', '$5'}}]
    }]),
    case ExistingEntries of
        [] ->
            ok;

        _ ->
            %% compare pids too: an entry whose name the snapshot has with another pid is stale, whatever its time
            SnapshotPids = maps:from_list([{Name, Pid} || {Name, Pid, _Meta, _Time} <- RegistryTuplesOfRemoteNode]),
            SnapshotTime = lists:foldl(fun({_, _, _, Time}, Acc) -> max(Time, Acc) end, 0, RegistryTuplesOfRemoteNode),
            lists:foreach(fun({Name, Pid, Meta, Time, MRef}) ->
                case maps:get(Name, SnapshotPids, undefined) =:= Pid orelse is_newer_caller_entry(MRef, Time, SnapshotTime) of
                    true ->
                        ok;

                    false ->
                        remove_from_local_table(Name, Pid, TableByName, TableByPid),
                        syn_event_handler:call_event_handler(on_process_unregistered,
                            [Scope, Name, Pid, Meta, {syn_remote_scope_node_up, Scope, Node}]
                        )
                end
            end, ExistingEntries)
    end.

%% an entry this node wrote itself from the reply to its own call, newer than anything in the snapshot:
%% the snapshot may have been sent before the call was handled, so it can't know about it yet
-spec is_newer_caller_entry(MRef :: undefined | reference() | caller, Time :: integer(), SnapshotTime :: integer()) -> boolean().
is_newer_caller_entry(caller, Time, SnapshotTime) -> Time > SnapshotTime;
is_newer_caller_entry(_, _, _) -> false.

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

        {_, Pid, _, TableTime, caller, _} when Time < TableTime ->
            %% same pid, older than what this node wrote from the reply to its own call: ignore
            ok;

        {_, Pid, TableMeta, _, MRef, _} ->
            %% same pid, more recent (because it comes from the same node, which means that it's sequential)
            %% maybe updated meta or time only
            add_to_local_table(Name, Pid, Meta, Time, MRef, TableByName, TableByPid),
            %% callback (call only if meta update)
            case TableMeta =/= Meta of
                true ->
                    syn_event_handler:call_event_handler(on_registry_process_updated, [Scope, Name, Pid, Meta, Reason]),
                    syn_event_handler:call_event_handler(on_registry_process_updated, [Scope, Name, Pid, TableMeta, Meta, Reason]);
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

-spec handle_registry_unregister_sync(
    Name :: term(),
    Pid :: pid(),
    Meta :: term(),
    Reason :: term(),
    #state{}
) -> any().
handle_registry_unregister_sync(Name, Pid, Meta, Reason, #state{
    scope = Scope,
    table_by_name = TableByName,
    table_by_pid = TableByPid
}) ->
    case find_registry_entry_by_name(Name, TableByName) of
        {_, Pid, _, _, _, _} ->
            remove_from_local_table(Name, Pid, TableByName, TableByPid),
            %% callback
            syn_event_handler:call_event_handler(on_process_unregistered, [Scope, Name, Pid, Meta, Reason]);

        _ ->
            %% not in table, nothing to do
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
            ?LOG_NOTICE(#{handler => ?MODULE_LOG_NAME, scope => Scope,
                        event => registry_conflict, name => Name,
                        remote => {Pid, Meta}, local => {TablePid, TableMeta}, keep => remote}),
            %% update locally, the incoming sync_register will update with the time coming from remote node
            update_local_table(Name, TablePid, {Pid, Meta, Time, undefined}, TableByName, TableByPid),
            %% kill
            case KillOtherPid of
                true -> exit(TablePid, {syn_resolve_kill, Name, TableMeta});
                false -> ok
            end,
            %% callbacks
            syn_event_handler:call_event_handler(on_process_unregistered, [Scope, Name, TablePid, TableMeta, syn_conflict_resolution]),
            syn_event_handler:call_event_handler(on_process_registered, [Scope, Name, Pid, Meta, syn_conflict_resolution]),
            %% broadcast unregister for the losing local pid so other nodes clean up stale ack_sync data
            syn_gen_scope:broadcast({'3.0', sync_unregister, Name, TablePid, TableMeta, syn_conflict_resolution}, State);

        TablePid ->
            %% -> we keep the local pid, remote pid will be killed by the other node in the conflict
            ?LOG_NOTICE(#{handler => ?MODULE_LOG_NAME, scope => Scope,
                        event => registry_conflict, name => Name,
                        remote => {Pid, Meta}, local => {TablePid, TableMeta}, keep => local}),
            %% overwrite with updated time
            ResolveTime = erlang:system_time(),
            add_to_local_table(Name, TablePid, TableMeta, ResolveTime, TableMRef, TableByName, TableByPid),
            %% broadcast to all (including remote node to update the time)
            syn_gen_scope:broadcast({'3.0', sync_register, Name, TablePid, TableMeta, ResolveTime, syn_conflict_resolution}, State);

        Invalid ->
            ?LOG_NOTICE(#{handler => ?MODULE_LOG_NAME, scope => Scope,
                        event => registry_conflict, name => Name,
                        remote => {Pid, Meta}, local => {TablePid, TableMeta},
                        keep => {none, Invalid}}),
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
            %% broadcast to all, remote node included: if its process died before it could see the conflict,
            %% it has added ours from our snapshot and this removes it
            syn_gen_scope:broadcast({'3.0', sync_unregister, Name, TablePid, TableMeta, syn_conflict_resolution}, State)
    end.
