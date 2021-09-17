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
-export([get_subcluster_nodes/1]).
-export([lookup/1, lookup/2]).
-export([register/2, register/3, register/4]).
-export([unregister/1, unregister/2]).
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

%% tests
-ifdef(TEST).
-export([add_to_local_table/6, remove_from_local_table/3]).
-endif.

%% includes
-include("syn.hrl").

%% ===================================================================
%% API
%% ===================================================================
-spec start_link(Scope :: atom()) ->
    {ok, Pid :: pid()} | {error, {already_started, Pid :: pid()}} | {error, Reason :: any()}.
start_link(Scope) when is_atom(Scope) ->
    syn_gen_scope:start_link(?MODULE, Scope, [Scope]).

-spec get_subcluster_nodes(#state{}) -> [node()].
get_subcluster_nodes(State) ->
    syn_gen_scope:get_subcluster_nodes(?MODULE, State).

-spec lookup(Name :: any()) -> {pid(), Meta :: any()} | undefined.
lookup(Name) ->
    lookup(default, Name).

-spec lookup(Scope :: atom(), Name :: any()) -> {pid(), Meta :: any()} | undefined.
lookup(Scope, Name) ->
    try find_registry_entry_by_name(Scope, Name) of
        undefined -> undefined;
        {{Name, Pid}, Meta, _, _, _} -> {Pid, Meta}
    catch
        error:badarg -> error({invalid_scope, Scope})
    end.

-spec register(Name :: any(), Pid :: pid()) -> ok | {error, Reason :: any()}.
register(Name, Pid) ->
    register(default, Name, Pid, undefined).

-spec register(NameOrScope :: any(), PidOrName :: any(), MetaOrPid :: any()) -> ok | {error, Reason :: any()}.
register(Name, Pid, Meta) when is_pid(Pid) ->
    register(default, Name, Pid, Meta);

register(Scope, Name, Pid) when is_pid(Pid) ->
    register(Scope, Name, Pid, undefined).

-spec register(Scope :: atom(), Name :: any(), Pid :: pid(), Meta :: any()) -> ok | {error, Reason :: any()}.
register(Scope, Name, Pid, Meta) ->
    Node = node(Pid),
    try syn_gen_scope:call(?MODULE, Node, Scope, {register_on_owner, node(), Name, Pid, Meta}) of
        {ok, {TablePid, TableMeta, Time}} when Node =/= node() ->
            %% update table on caller node immediately so that subsequent calls have an updated registry
            add_to_local_table(Scope, Name, Pid, Meta, Time, undefined),
            %% callback
            syn_event_handler:do_on_process_registered(Scope, Name, {TablePid, TableMeta}, {Pid, Meta}),
            %% return
            ok;

        {Response, _} ->
            Response
    catch
        exit:{noproc, {gen_server, call, _}} -> error({invalid_scope, Scope})
    end.

-spec unregister(Name :: any()) -> ok | {error, Reason :: any()}.
unregister(Name) ->
    unregister(default, Name).

-spec unregister(Scope :: atom(), Name :: any()) -> ok | {error, Reason :: any()}.
unregister(Scope, Name) ->
    % get process' node
    try find_registry_entry_by_name(Scope, Name) of
        undefined ->
            {error, undefined};

        {{Name, Pid}, Meta, _, _, _} ->
            Node = node(Pid),
            case syn_gen_scope:call(?MODULE, Node, Scope, {unregister_on_owner, node(), Name, Pid}) of
                ok when Node =/= node() ->
                    %% remove table on caller node immediately so that subsequent calls have an updated registry
                    remove_from_local_table(Scope, Name, Pid),
                    %% callback
                    syn_event_handler:do_on_process_unregistered(Scope, Name, Pid, Meta),
                    %% return
                    ok;

                Response ->
                    Response
            end
    catch
        exit:{noproc, {gen_server, call, _}} -> error({invalid_scope, Scope});
        error:badarg -> error({invalid_scope, Scope})
    end.

-spec count(Scope :: atom()) -> non_neg_integer().
count(Scope) ->
    case ets:info(syn_backbone:get_table_name(syn_registry_by_name, Scope), size) of
        undefined -> error({invalid_scope, Scope});
        Value -> Value
    end.

-spec count(Scope :: atom(), Node :: node()) -> non_neg_integer().
count(Scope, Node) ->
    case catch ets:select_count(syn_backbone:get_table_name(syn_registry_by_name, Scope), [{
        {{'_', '_'}, '_', '_', '_', Node},
        [],
        [true]
    }]) of
        {'EXIT', {badarg, [{ets, select_count, _, _} | _]}} -> error({invalid_scope, Scope});
        Value -> Value
    end.

%% ===================================================================
%% Callbacks
%% ===================================================================

%% ----------------------------------------------------------------------------------------------------------
%% Init
%% ----------------------------------------------------------------------------------------------------------
-spec init(Args :: term()) -> {ok, State :: term()}.
init([Scope]) ->
    HandlerState = #{},
    %% rebuild
    rebuild_monitors(Scope),
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
handle_call({register_on_owner, RequesterNode, Name, Pid, Meta}, _From, #state{
    scope = Scope
} = State) ->
    case is_process_alive(Pid) of
        true ->
            case find_registry_entry_by_name(Scope, Name) of
                undefined ->
                    %% available
                    MRef = case find_monitor_for_pid(Scope, Pid) of
                        undefined -> erlang:monitor(process, Pid);  %% process is not monitored yet, add
                        MRef0 -> MRef0
                    end,
                    %% add to local table
                    Time = erlang:system_time(),
                    add_to_local_table(Scope, Name, Pid, Meta, Time, MRef),
                    %% callback
                    syn_event_handler:do_on_process_registered(Scope, Name, {undefined, undefined}, {Pid, Meta}),
                    %% broadcast
                    syn_gen_scope:broadcast({'3.0', sync_register, Scope, Name, Pid, Meta, Time}, [RequesterNode], State),
                    %% return
                    {reply, {ok, {undefined, undefined, Time}}, State};

                {{Name, Pid}, TableMeta, _TableTime, MRef, _TableNode} ->
                    %% same pid, possibly new meta or time, overwrite
                    Time = erlang:system_time(),
                    add_to_local_table(Scope, Name, Pid, Meta, Time, MRef),
                    %% callback
                    syn_event_handler:do_on_process_registered(Scope, Name, {Pid, TableMeta}, {Pid, Meta}),
                    %% broadcast
                    syn_gen_scope:broadcast({'3.0', sync_register, Scope, Name, Pid, Meta, Time}, State),
                    %% return
                    {reply, {ok, {Pid, TableMeta, Time}}, State};

                _ ->
                    {reply, {{error, taken}, undefined}, State}
            end;

        false ->
            {reply, {{error, not_alive}, undefined}, State}
    end;

handle_call({unregister_on_owner, RequesterNode, Name, Pid}, _From, #state{scope = Scope} = State) ->
    case find_registry_entry_by_name(Scope, Name) of
        {{Name, Pid}, Meta, _Time, _MRef, _Node} ->
            %% demonitor if the process is not registered under other names
            maybe_demonitor(Scope, Pid),
            %% remove from table
            remove_from_local_table(Scope, Name, Pid),
            %% callback
            syn_event_handler:do_on_process_unregistered(Scope, Name, Pid, Meta),
            %% broadcast
            syn_gen_scope:broadcast({'3.0', sync_unregister, Name, Pid, Meta}, [RequesterNode], State),
            %% return
            {reply, ok, State};

        {{Name, _TablePid}, _Meta, _Time, _MRef, _Node} ->
            %% process is registered locally with another pid: race condition, wait for sync to happen & return error
            {reply, {error, race_condition}, State};

        undefined ->
            {reply, {error, undefined}, State}
    end;

handle_call(Request, From, State) ->
    error_logger:warning_msg("SYN[~s] Received from ~p an unknown call message: ~p", [node(), Request, From]),
    {reply, undefined, State}.

%% ----------------------------------------------------------------------------------------------------------
%% Info messages
%% ----------------------------------------------------------------------------------------------------------
-spec handle_info(Info :: timeout | term(), State :: term()) ->
    {noreply, NewState :: term()} |
    {noreply, NewState :: term(), timeout() | hibernate | {continue, term()}} |
    {stop, Reason :: term(), NewState :: term()}.
handle_info({'3.0', sync_register, Scope, Name, Pid, Meta, Time}, State) ->
    handle_registry_sync(Scope, Name, Pid, Meta, Time, State),
    {noreply, State};

handle_info({'3.0', sync_unregister, Name, Pid, Meta}, #state{scope = Scope} = State) ->
    remove_from_local_table(Scope, Name, Pid),
    %% callback
    syn_event_handler:do_on_process_unregistered(Scope, Name, Pid, Meta),
    %% return
    {noreply, State};
handle_info({'DOWN', _MRef, process, Pid, Reason}, #state{scope = Scope} = State) ->
    case find_registry_entries_by_pid(Scope, Pid) of
        [] ->
            error_logger:warning_msg(
                "SYN[~s] Received a DOWN message from an unknown process ~p with reason: ~p",
                [node(), Pid, Reason]
            );

        Entries ->
            lists:foreach(fun({{Name, _Pid}, Meta, _, _, _}) ->
                %% remove from table
                remove_from_local_table(Scope, Name, Pid),
                %% callback
                syn_event_handler:do_on_process_unregistered(Scope, Name, Pid, Meta),
                %% broadcast
                syn_gen_scope:broadcast({'3.0', sync_unregister, Name, Pid, Meta}, State)
            end, Entries)
    end,
    %% return
    {noreply, State};

handle_info(Info, State) ->
    error_logger:warning_msg("SYN[~s] Received an unknown info message: ~p", [node(), Info]),
    {noreply, State}.

%% ----------------------------------------------------------------------------------------------------------
%% Data
%% ----------------------------------------------------------------------------------------------------------
-spec get_local_data(State :: term()) -> {ok, Data :: any()} | undefined.
get_local_data(#state{scope = Scope}) ->
    {ok, get_registry_tuples_for_node(Scope, node())}.

-spec save_remote_data(RemoteScopePid :: pid(), RemoteData :: any(), State :: term()) -> any().
save_remote_data(RemoteScopePid, RegistryTuplesOfRemoteNode, #state{scope = Scope} = State) ->
    %% insert tuples
    lists:foreach(fun({Name, Pid, Meta, Time}) ->
        handle_registry_sync(Scope, Name, Pid, Meta, Time, State)
    end, RegistryTuplesOfRemoteNode).

-spec purge_local_data_for_node(Node :: node(), State :: term()) -> any().
purge_local_data_for_node(Node, #state{scope = Scope}) ->
    purge_registry_for_remote_node(Scope, Node).

%% ===================================================================
%% Internal
%% ===================================================================
-spec rebuild_monitors(Scope :: atom()) -> ok.
rebuild_monitors(Scope) ->
    RegistryTuples = get_registry_tuples_for_node(Scope, node()),
    lists:foreach(fun({Name, Pid, Meta, Time}) ->
        remove_from_local_table(Scope, Name, Pid),
        case is_process_alive(Pid) of
            true ->
                MRef = erlang:monitor(process, Pid),
                add_to_local_table(Scope, Name, Pid, Meta, Time, MRef);

            _ ->
                ok
        end
    end, RegistryTuples).

-spec get_registry_tuples_for_node(Scope :: atom(), Node :: node()) -> [syn_registry_tuple()].
get_registry_tuples_for_node(Scope, Node) ->
    ets:select(syn_backbone:get_table_name(syn_registry_by_name, Scope), [{
        {{'$1', '$2'}, '$3', '$4', '_', Node},
        [],
        [{{'$1', '$2', '$3', '$4'}}]
    }]).

-spec find_registry_entry_by_name(Scope :: atom(), Name :: any()) -> Entry :: syn_registry_entry() | undefined.
find_registry_entry_by_name(Scope, Name) ->
    case ets:select(syn_backbone:get_table_name(syn_registry_by_name, Scope), [{
        {{Name, '_'}, '_', '_', '_', '_'},
        [],
        ['$_']
    }]) of
        [RegistryEntry] -> RegistryEntry;
        [] -> undefined
    end.

-spec find_registry_entries_by_pid(Scope :: atom(), Pid :: pid()) -> RegistryEntries :: [syn_registry_entry()].
find_registry_entries_by_pid(Scope, Pid) when is_pid(Pid) ->
    ets:select(syn_backbone:get_table_name(syn_registry_by_pid, Scope), [{
        {{Pid, '$2'}, '$3', '$4', '$5', '$6'},
        [],
        [{{{{'$2', Pid}}, '$3', '$4', '$5', '$6'}}]
    }]).

-spec find_monitor_for_pid(Scope :: atom(), Pid :: pid()) -> reference() | undefined.
find_monitor_for_pid(Scope, Pid) when is_pid(Pid) ->
    case ets:select(syn_backbone:get_table_name(syn_registry_by_pid, Scope), [{
        {{Pid, '_'}, '_', '_', '$5', '_'},
        [],
        ['$5']
    }], 1) of
        {[MRef], _} -> MRef;
        '$end_of_table' -> undefined
    end.

-spec maybe_demonitor(Scope :: atom(), Pid :: pid()) -> ok.
maybe_demonitor(Scope, Pid) ->
    %% try to retrieve 2 items
    %% if only 1 is returned it means that no other aliases exist for the Pid
    case ets:select(syn_backbone:get_table_name(syn_registry_by_pid, Scope), [{
        {{Pid, '_'}, '_', '_', '$5', '_'},
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
    Scope :: atom(),
    Name :: any(),
    Pid :: pid(),
    Meta :: any(),
    Time :: integer(),
    MRef :: undefined | reference()
) -> true.
add_to_local_table(Scope, Name, Pid, Meta, Time, MRef) ->
    %% insert
    true = ets:insert(syn_backbone:get_table_name(syn_registry_by_name, Scope),
        {{Name, Pid}, Meta, Time, MRef, node(Pid)}
    ),
    true = ets:insert(syn_backbone:get_table_name(syn_registry_by_pid, Scope),
        {{Pid, Name}, Meta, Time, MRef, node(Pid)}
    ).

-spec remove_from_local_table(Scope :: atom(), Name :: any(), Pid :: pid()) -> true.
remove_from_local_table(Scope, Name, Pid) ->
    true = ets:delete(syn_backbone:get_table_name(syn_registry_by_name, Scope), {Name, Pid}),
    true = ets:delete(syn_backbone:get_table_name(syn_registry_by_pid, Scope), {Pid, Name}).

-spec update_local_table(
    Scope :: atom(),
    Name :: any(),
    PreviousPid :: pid(),
    {
        Pid :: pid(),
        Meta :: any(),
        Time :: integer(),
        MRef :: undefined | reference()
    }
) -> true.
update_local_table(Scope, Name, PreviousPid, {Pid, Meta, Time, MRef}) ->
    maybe_demonitor(Scope, PreviousPid),
    remove_from_local_table(Scope, Name, PreviousPid),
    add_to_local_table(Scope, Name, Pid, Meta, Time, MRef).

-spec purge_registry_for_remote_node(Scope :: atom(), Node :: atom()) -> true.
purge_registry_for_remote_node(Scope, Node) when Node =/= node() ->
    %% loop elements for callback in a separate process to free scope process
    RegistryTuples = get_registry_tuples_for_node(Scope, Node),
    spawn(fun() ->
        lists:foreach(fun({Name, Pid, Meta, _Time}) ->
            syn_event_handler:do_on_process_unregistered(Scope, Name, Pid, Meta)
        end, RegistryTuples)
    end),
    %% remove all from pid table
    true = ets:match_delete(syn_backbone:get_table_name(syn_registry_by_name, Scope), {{'_', '_'}, '_', '_', '_', Node}),
    true = ets:match_delete(syn_backbone:get_table_name(syn_registry_by_pid, Scope), {{'_', '_'}, '_', '_', '_', Node}).

-spec handle_registry_sync(
    Scope :: atom(),
    Name :: any(),
    Pid :: pid(),
    Meta :: any(),
    Time :: non_neg_integer(),
    #state{}
) -> any().
handle_registry_sync(Scope, Name, Pid, Meta, Time, State) ->
    case find_registry_entry_by_name(Scope, Name) of
        undefined ->
            %% no conflict
            add_to_local_table(Scope, Name, Pid, Meta, Time, undefined),
            %% callback
            syn_event_handler:do_on_process_registered(Scope, Name, {undefined, undefined}, {Pid, Meta});

        {{Name, Pid}, TableMeta, _TableTime, MRef, _TableNode} ->
            %% same pid, more recent (because it comes from the same node, which means that it's sequential)
            add_to_local_table(Scope, Name, Pid, Meta, Time, MRef),
            %% callback
            syn_event_handler:do_on_process_registered(Scope, Name, {Pid, TableMeta}, {Pid, Meta});

        {{Name, TablePid}, TableMeta, TableTime, TableMRef, _TableNode} when node(TablePid) =:= node() ->
            %% current node runs a conflicting process -> resolve
            %% * the conflict is resolved by the two nodes that own the conflicting processes
            %% * when a process is chosen, the time is updated
            %% * the node that runs the process that is kept sends the sync_register message
            %% * recipients check that the time is more recent that what they have to ensure that there are no race conditions
            resolve_conflict(Scope, Name, {Pid, Meta, Time}, {TablePid, TableMeta, TableTime, TableMRef}, State);

        {{Name, TablePid}, TableMeta, TableTime, _TableMRef, _TableNode} when TableTime < Time ->
            %% current node does not own any of the conflicting processes, update
            update_local_table(Scope, Name, TablePid, {Pid, Meta, Time, undefined}),
            %% callbacks
            syn_event_handler:do_on_process_unregistered(Scope, Name, TablePid, TableMeta),
            syn_event_handler:do_on_process_registered(Scope, Name, {TablePid, TableMeta}, {Pid, Meta});

        {{Name, _TablePid}, _TableMeta, _TableTime, _TableMRef, _TableNode} ->
            %% race condition: incoming data is older, ignore
            ok
    end.

-spec resolve_conflict(
    Scope :: atom(),
    Name :: any(),
    {Pid :: pid(), Meta :: any(), Time :: non_neg_integer()},
    {TablePid :: pid(), TableMeta :: any(), TableTime :: non_neg_integer(), TableMRef :: reference()},
    #state{}
) -> any().
resolve_conflict(Scope, Name, {Pid, Meta, Time}, {TablePid, TableMeta, TableTime, TableMRef}, State) ->
    %% call conflict resolution
    PidToKeep = syn_event_handler:do_resolve_registry_conflict(
        Scope,
        Name,
        {Pid, Meta, Time},
        {TablePid, TableMeta, TableTime}
    ),
    %% resolve
    case PidToKeep of
        Pid ->
            %% -> we keep the remote pid
            %% update locally, the incoming sync_register will update with the time coming from remote node
            update_local_table(Scope, Name, TablePid, {Pid, Meta, Time, undefined}),
            %% callbacks
            syn_event_handler:do_on_process_unregistered(Scope, Name, TablePid, TableMeta),
            syn_event_handler:do_on_process_registered(Scope, Name, {TablePid, TableMeta}, {Pid, Meta}),
            %% kill
            exit(TablePid, {syn_resolve_kill, Name, TableMeta}),
            error_logger:info_msg("SYN[~s] Registry CONFLICT for name ~p@~s: ~p ~p -> chosen: ~p",
                [node(), Name, Scope, Pid, TablePid, Pid]
            );

        TablePid ->
            %% -> we keep the local pid
            %% overwrite with updated time
            ResolveTime = erlang:system_time(),
            add_to_local_table(Scope, Name, TablePid, TableMeta, ResolveTime, TableMRef),
            %% broadcast
            syn_gen_scope:broadcast({'3.0', sync_register, Scope, Name, TablePid, TableMeta, ResolveTime}, State),
            error_logger:info_msg("SYN[~s] Registry CONFLICT for name ~p@~s: ~p ~p -> chosen: ~p",
                [node(), Name, Scope, Pid, TablePid, TablePid]
            );

        Invalid ->
            %% remove
            maybe_demonitor(Scope, TablePid),
            remove_from_local_table(Scope, Name, TablePid),
            %% callback
            syn_event_handler:do_on_process_unregistered(Scope, Name, TablePid, TableMeta),
            %% kill local, remote will be killed by other node performing the same resolve
            exit(TablePid, {syn_resolve_kill, Name, TableMeta}),
            error_logger:info_msg("SYN[~s] Registry CONFLICT for name ~p@~s: ~p ~p -> none chosen (got: ~p)",
                [node(), Name, Scope, Pid, TablePid, Invalid]
            )
    end.
