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
-module(syn_registry).
-behaviour(gen_server).

%% API
-export([start_link/1]).
-export([get_subcluster_nodes/1]).
-export([lookup/1, lookup/2]).
-export([register/2, register/3, register/4]).
-export([unregister/1, unregister/2]).
-export([count/1, count/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% tests
-ifdef(TEST).
-export([add_to_local_table/6, remove_from_local_table/3]).
-endif.

%% records
-record(state, {
    scope = default :: atom(),
    process_name = syn_registry_default :: atom(),
    nodes = #{} :: #{node() => pid()}
}).

%% includes
-include("syn.hrl").

%% ===================================================================
%% API
%% ===================================================================
-spec start_link(Scope :: atom()) -> {ok, pid()} | {error, any()}.
start_link(Scope) when is_atom(Scope) ->
    ProcessName = get_process_name_for_scope(Scope),
    Args = [Scope, ProcessName],
    gen_server:start_link({local, ProcessName}, ?MODULE, Args, []).

-spec get_subcluster_nodes(Scope :: atom()) -> [node()].
get_subcluster_nodes(Scope) ->
    ProcessName = get_process_name_for_scope(Scope),
    gen_server:call(ProcessName, get_subcluster_nodes).

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
    ProcessName = get_process_name_for_scope(Scope),
    Node = node(Pid),
    try gen_server:call({ProcessName, Node}, {register_on_node, Name, Pid, Meta}) of
        Value -> Value
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

        {{Name, Pid}, _, _, _, _} ->
            ProcessName = get_process_name_for_scope(Scope),
            Node = node(Pid),
            gen_server:call({ProcessName, Node}, {unregister_on_node, Name, Pid})
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
-spec init([term()]) ->
    {ok, #state{}} |
    {ok, #state{}, Timeout :: non_neg_integer()} |
    ignore |
    {stop, Reason :: any()}.
init([Scope, ProcessName]) ->
    %% monitor nodes
    ok = net_kernel:monitor_nodes(true),
    %% rebuild monitors (if after crash)
    rebuild_monitors(Scope),
    %% build state
    State = #state{
        scope = Scope,
        process_name = ProcessName
    },
    %% init with 0 timeout
    {ok, State, 0}.

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
handle_call(get_subcluster_nodes, _From, #state{
    nodes = Nodes
} = State) ->
    {reply, Nodes, State};

handle_call({register_on_node, Name, Pid, Meta}, _From, #state{
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
                    %% broadcast
                    broadcast({'3.0', sync_register, Scope, Name, Pid, Meta, Time}, State),
                    %% return
                    {reply, ok, State};

                {{Name, Pid}, _TableMeta, _TableTime, MRef, _TableNode} ->
                    %% same pid, possibly new meta or time, overwrite
                    Time = erlang:system_time(),
                    add_to_local_table(Scope, Name, Pid, Meta, Time, MRef),
                    %% broadcast
                    broadcast({'3.0', sync_register, Scope, Name, Pid, Meta, Time}, State),
                    %% return
                    {reply, ok, State};

                _ ->
                    {reply, {error, taken}, State}
            end;

        false ->
            {reply, {error, not_alive}, State}
    end;

handle_call({unregister_on_node, Name, Pid}, _From, #state{scope = Scope} = State) ->
    case find_registry_entry_by_name(Scope, Name) of
        {{Name, Pid}, _Meta, _Time, _MRef, _Node} ->
            %% demonitor if the process is not registered under other names
            maybe_demonitor(Scope, Pid),
            %% remove from table
            remove_from_local_table(Scope, Name, Pid),
            %% broadcast
            broadcast({'3.0', sync_unregister, Name, Pid}, State),
            %% return
            {reply, ok, State};

        {{Name, _TablePid}, _Meta, _Time, _MRef, _Node} ->
            %% process is registered locally with another pid: race condition, wait for sync to happen & return error
            {reply, {error, race_condition}, State};

        undefined ->
            {reply, {error, undefined}, State}
    end;

handle_call(Request, From, State) ->
    error_logger:warning_msg("SYN[~p] Received from ~p an unknown call message: ~p~n", [node(), Request, From]),
    {reply, undefined, State}.

%% ----------------------------------------------------------------------------------------------------------
%% Cast messages
%% ----------------------------------------------------------------------------------------------------------
-spec handle_cast(Msg :: any(), #state{}) ->
    {noreply, #state{}} |
    {noreply, #state{}, Timeout :: non_neg_integer()} |
    {stop, Reason :: any(), #state{}}.
handle_cast({'3.0', sync_register, Scope, Name, Pid, Meta, Time}, State) ->
    handle_registry_sync(Scope, Name, Pid, Meta, Time, State),
    {noreply, State};

handle_cast({'3.0', sync_unregister, Name, Pid}, #state{scope = Scope} = State) ->
    remove_from_local_table(Scope, Name, Pid),
    {noreply, State};

handle_cast({'3.0', announce, RemoteScopePid}, #state{
    scope = Scope,
    nodes = Nodes
} = State) ->
    RemoteScopeNode = node(RemoteScopePid),
    error_logger:info_msg("SYN[~p] Received announce request from node ~p and scope ~p~n", [node(), RemoteScopeNode, Scope]),
    %% send data
    RegistryTuplesOfLocalNode = get_registry_tuples_for_node(Scope, node()),
    cast_to_node(RemoteScopeNode, {'3.0', sync, self(), RegistryTuplesOfLocalNode}, State),
    %% is this a new node?
    case maps:is_key(RemoteScopeNode, Nodes) of
        true ->
            %% already known, ignore
            {noreply, State};

        false ->
            %% monitor & announce
            _MRef = monitor(process, RemoteScopePid),
            cast_to_node(RemoteScopeNode, {'3.0', announce, self()}, State),
            {noreply, State#state{nodes = Nodes#{RemoteScopeNode => RemoteScopePid}}}
    end;

handle_cast({'3.0', sync, RemoteScopePid, RegistryTuplesOfRemoteNode}, #state{
    scope = Scope,
    nodes = Nodes
} = State) ->
    RemoteScopeNode = node(RemoteScopePid),
    error_logger:info_msg("SYN[~p] Received sync data (~p entries) from node ~p and scope ~p~n",
        [node(), length(RegistryTuplesOfRemoteNode), RemoteScopeNode, Scope]
    ),
    %% insert tuples
    lists:foreach(fun({Name, Pid, Meta, Time}) ->
        handle_registry_sync(Scope, Name, Pid, Meta, Time, State)
    end, RegistryTuplesOfRemoteNode),
    %% is this a new node?
    case maps:is_key(RemoteScopeNode, Nodes) of
        true ->
            %% already known, ignore
            {noreply, State};

        false ->
            %% if we don't know about the node, it is because it's the response to the first broadcast of announce message
            %% -> monitor
            _MRef = monitor(process, RemoteScopePid),
            {noreply, State#state{nodes = Nodes#{RemoteScopeNode => RemoteScopePid}}}
    end;

handle_cast(Msg, State) ->
    error_logger:warning_msg("SYN[~p] Received an unknown cast message: ~p~n", [node(), Msg]),
    {noreply, State}.

%% ----------------------------------------------------------------------------------------------------------
%% Info messages
%% ----------------------------------------------------------------------------------------------------------
-spec handle_info(Info :: any(), #state{}) ->
    {noreply, #state{}} |
    {noreply, #state{}, Timeout :: non_neg_integer()} |
    {stop, Reason :: any(), #state{}}.
handle_info(timeout, #state{
    scope = Scope
} = State) ->
    error_logger:info_msg("SYN[~p] Announcing to all nodes in the cluster with scope: ~p~n", [node(), Scope]),
    broadcast_all({'3.0', announce, self()}, State),
    {noreply, State};

handle_info({'DOWN', _MRef, process, Pid, _Reason}, #state{
    scope = Scope,
    nodes = Nodes
} = State) when node(Pid) =/= node() ->
    %% scope process down
    RemoteNode = node(Pid),
    case maps:take(RemoteNode, Nodes) of
        {Pid, Nodes1} ->
            error_logger:info_msg("SYN[~p] Scope Process ~p is DOWN on node ~p~n", [node(), Scope, RemoteNode]),
            purge_registry_for_remote_node(Scope, RemoteNode),
            {noreply, State#state{nodes = Nodes1}};

        error ->
            error_logger:warning_msg("SYN[~p] Received DOWN message from unknown pid: ~p~n", [node(), Pid]),
            {noreply, State}
    end;

handle_info({'DOWN', _MRef, process, Pid, Reason}, #state{scope = Scope} = State) ->
    case find_registry_entries_by_pid(Scope, Pid) of
        [] ->
            error_logger:warning_msg(
                "SYN[~p] Received a DOWN message from an unknown process ~p with reason: ~p~n",
                [node(), Pid, Reason]
            );

        Entries ->
            lists:foreach(fun({{Name, _Pid}, _, _, _, _}) ->
                %% remove from table
                remove_from_local_table(Scope, Name, Pid),
                %% broadcast
                broadcast({'3.0', sync_unregister, Name, Pid}, State)
            end, Entries)
    end,
    %% return
    {noreply, State};

handle_info({nodedown, _Node}, State) ->
    %% ignore & wait for monitor DOWN message
    {noreply, State};

handle_info({nodeup, RemoteNode}, State) ->
    error_logger:info_msg("SYN[~p] Node ~p has joined the cluster, sending announce message~n", [node(), RemoteNode]),
    cast_to_node(RemoteNode, {'3.0', announce, self()}, State),
    {noreply, State};

handle_info(Info, State) ->
    error_logger:warning_msg("SYN[~p] Received an unknown info message: ~p~n", [node(), Info]),
    {noreply, State}.

%% ----------------------------------------------------------------------------------------------------------
%% Terminate
%% ----------------------------------------------------------------------------------------------------------
-spec terminate(Reason :: any(), #state{}) -> terminated.
terminate(Reason, _State) ->
    error_logger:info_msg("SYN[~p] Terminating with reason: ~p~n", [node(), Reason]),
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
-spec get_process_name_for_scope(Scope :: atom()) -> atom().
get_process_name_for_scope(Scope) ->
    ModuleBin = atom_to_binary(?MODULE),
    ScopeBin = atom_to_binary(Scope),
    binary_to_atom(<<ModuleBin/binary, "_", ScopeBin/binary>>).

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

-spec broadcast(Message :: any(), #state{}) -> any().
broadcast(Message, #state{process_name = ProcessName, nodes = Nodes}) ->
    lists:foreach(fun(RemoteNode) -> gen_server:cast({ProcessName, RemoteNode}, Message) end, maps:keys(Nodes)).

-spec broadcast_all(Message :: any(), #state{}) -> any().
broadcast_all(Message, #state{process_name = ProcessName}) ->
    lists:foreach(fun(RemoteNode) -> gen_server:cast({ProcessName, RemoteNode}, Message) end, nodes()).

-spec cast_to_node(RemoteNode :: node(), Message :: any(), #state{}) -> any().
cast_to_node(RemoteNode, Message, #state{
    process_name = ProcessName
}) ->
    gen_server:cast({ProcessName, RemoteNode}, Message).

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
            add_to_local_table(Scope, Name, Pid, Meta, Time, undefined);

        {{Name, Pid}, _TableMeta, _TableTime, MRef, _TableNode} ->
            %% same pid, more recent (because it comes from the same node, which means that it's sequential)
            add_to_local_table(Scope, Name, Pid, Meta, Time, MRef);

        {{Name, TablePid}, TableMeta, TableTime, TableMRef, _TableNode} when node(TablePid) =:= node() ->
            %% current node runs a conflicting process -> resolve
            %% * the conflict is resolved by the two nodes that own the conflicting processes
            %% * when a process is chosen, the time is updated
            %% * the node that runs the process that is kept sends the sync_register message
            %% * recipients check that the time is more recent that what they have to ensure that there are no race conditions
            resolve_conflict(Scope, Name, {Pid, Meta, Time}, {TablePid, TableMeta, TableTime, TableMRef}, State);

        {{Name, TablePid}, _TableMeta, TableTime, _TableMRef, _TableNode} when TableTime < Time ->
            %% current node does not own any of the conflicting processes, update
            update_local_table(Scope, Name, TablePid, {Pid, Meta, Time, undefined});

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
) -> KeptPid :: pid().
resolve_conflict(Scope, Name, {Pid, Meta, Time}, {TablePid, TableMeta, TableTime, TableMRef}, State) ->
    CustomEventHandler = undefined,
    %% call conflict resolution
    PidToKeep = syn_event_handler:do_resolve_registry_conflict(
        Scope,
        Name,
        {Pid, Meta, Time},
        {TablePid, TableMeta, TableTime},
        CustomEventHandler
    ),
    %% resolve
    case PidToKeep of
        Pid ->
            %% -> we keep the remote pid
            %% update locally, the incoming sync_register will update with the time coming from remote node
            update_local_table(Scope, Name, TablePid, {Pid, Meta, Time, undefined}),
            %% kill
            exit(TablePid, {syn_resolve_kill, Name, TableMeta}),
            error_logger:info_msg("SYN[~p] Registry CONFLICT for name ~p@~p: ~p ~p -> chosen: ~p~n",
                [node(), Name, Scope, Pid, TablePid, Pid]
            );

        TablePid ->
            %% -> we keep the local pid
            %% overwrite with updated time
            ResolveTime = erlang:system_time(),
            add_to_local_table(Scope, Name, TablePid, TableMeta, ResolveTime, TableMRef),
            %% broadcast
            broadcast({'3.0', sync_register, Scope, Name, TablePid, TableMeta, ResolveTime}, State),
            error_logger:info_msg("SYN[~p] Registry CONFLICT for name ~p@~p: ~p ~p -> chosen: ~p~n",
                [node(), Name, Scope, Pid, TablePid, TablePid]
            );

        Invalid ->
            maybe_demonitor(Scope, TablePid),
            remove_from_local_table(Scope, Name, TablePid),
            %% kill local, remote will be killed by other node performing the resolve
            exit(TablePid, {syn_resolve_kill, Name, TableMeta}),
            error_logger:info_msg("SYN[~p] Registry CONFLICT for name ~p@~p: ~p ~p -> none chosen (got: ~p)~n",
                [node(), Name, Scope, Pid, TablePid, Invalid]
            )
    end.
