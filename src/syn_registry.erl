%% ==========================================================================================================
%% Syn - A global Process Registry and Process Group manager.
%%
%% The MIT License (MIT)
%%
%% Copyright (c) 2015-2019 Roberto Ostinelli <roberto@ostinelli.net> and Neato Robotics, Inc.
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
-export([start_link/2]).
-export([register/2, register/3]).
-export([unregister_and_register/2, unregister_and_register/3]).
-export([unregister/1]).
-export([whereis/1, whereis/2]).
-export([count/0, count/1]).

%% sync API
-export([sync_register/6, sync_unregister/3]).
-export([sync_demonitor_and_kill_on_node/5]).
-export([sync_get_local_registry_tuples/2]).
-export([force_cluster_sync/0]).
-export([add_to_local_table/5, remove_from_local_table/2]).
-export([find_monitor_for_pid/2]).

%% internal
-export([multicast_loop/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% records
-record(state, {
    process_name :: atom(),
    syn_registry_by_name_ets :: atom(),
    custom_event_handler :: undefined | module(),
    anti_entropy_interval_ms :: undefined | non_neg_integer(),
    anti_entropy_interval_max_deviation_ms :: undefined | non_neg_integer(),
    multicast_pid :: undefined | pid()
}).

%% includes
-include("syn.hrl").

%% ===================================================================
%% API
%% ===================================================================
-spec start_link(ProcessName :: atom(), Id :: integer()) -> {ok, pid()} | {error, any()}.
start_link(ProcessName, Id) ->
    Options = [],
    gen_server:start_link({local, ProcessName}, ?MODULE, {ProcessName, Id}, Options).

-spec register(Name :: any(), Pid :: pid()) -> ok | {error, Reason :: any()}.
register(Name, Pid) ->
    register(Name, Pid, undefined).

-spec register(Name :: any(), Pid :: pid(), Meta :: any()) -> ok | {error, Reason :: any()}.
register(Name, Pid, Meta) when is_pid(Pid) ->
    Node = node(Pid),
    ProcessName = syn_backbone:get_process_name(syn_registry, syn_backbone:get_shard(Name)),
    gen_server:call({ProcessName, Node}, {register_on_node, ProcessName, Name, Pid, Meta, false}).

-spec unregister_and_register(Name :: any(), Pid :: pid()) -> ok | {error, Reason :: any()}.
unregister_and_register(Name, Pid) ->
    unregister_and_register(Name, Pid, undefined).

-spec unregister_and_register(Name :: any(), Pid :: pid(), Meta :: any()) -> ok | {error, Reason :: any()}.
unregister_and_register(Name, Pid, Meta) when is_pid(Pid) ->
    Node = node(Pid),
    ProcessName = syn_backbone:get_process_name(syn_registry, syn_backbone:get_shard(Name)),
    gen_server:call({ProcessName, Node}, {register_on_node, ProcessName, Name, Pid, Meta, true}).

-spec unregister(Name :: any()) -> ok | {error, Reason :: any()}.
unregister(Name) ->
    % get process' node
    case find_registry_tuple_by_name(Name) of
        undefined ->
            {error, undefined};
        {Name, Pid, _, _} ->
            Node = node(Pid),
            ProcessName = syn_backbone:get_process_name(syn_registry, syn_backbone:get_shard(Name)),
            gen_server:call({ProcessName, Node}, {unregister_on_node, ProcessName, Name})
    end.

-spec whereis(Name :: any()) -> pid() | undefined.
whereis(Name) ->
    case find_registry_tuple_by_name(Name) of
        undefined -> undefined;
        {Name, Pid, _, _} -> Pid
    end.

-spec whereis(Name :: any(), with_meta) -> {pid(), Meta :: any()} | undefined.
whereis(Name, with_meta) ->
    case find_registry_tuple_by_name(Name) of
        undefined -> undefined;
        {Name, Pid, Meta, _} -> {Pid, Meta}
    end.

-spec count() -> non_neg_integer().
count() ->
    SynShards = application:get_env(syn, syn_shards, 1),
    lists:foldl(fun(ShardId, Acc) ->
        SynRegistryByNameEts = maps:get(syn_registry_by_name, syn_backbone:ets_names(ShardId)),
        ets:info(SynRegistryByNameEts, size) + Acc
    end, 0, lists:seq(1, SynShards)).

-spec count(Node :: node()) -> non_neg_integer().
count(Node) ->
    SynShards = application:get_env(syn, syn_shards, 1),
    lists:foldl(fun(ShardId, Acc) ->
        SynRegistryByNameEts = maps:get(syn_registry_by_name, syn_backbone:ets_names(ShardId)),
        NodeSize = ets:select_count(SynRegistryByNameEts, [{
            {{'_', '_'}, '_', '_', '_', Node},
            [],
            [true]
        }]),
        NodeSize + Acc
    end, 0, lists:seq(1, SynShards)).

-spec sync_register(
    RemoteNode :: node(),
    Name :: any(),
    RemotePid :: pid(),
    RemoteMeta :: any(),
    RemoteTime :: integer(),
    Force :: boolean()
) ->
    ok.
sync_register(RemoteNode, Name, RemotePid, RemoteMeta, RemoteTime, Force) ->
    ProcessName = syn_backbone:get_process_name(syn_registry, syn_backbone:get_shard(Name)),
    gen_server:cast({ProcessName, RemoteNode}, {sync_register, Name, RemotePid, RemoteMeta, RemoteTime, Force}).

-spec sync_unregister(RemoteNode :: node(), Name :: any(), Pid :: pid()) -> ok.
sync_unregister(RemoteNode, Name, Pid) ->
    ProcessName = syn_backbone:get_process_name(syn_registry, syn_backbone:get_shard(Name)),
    gen_server:cast({ProcessName, RemoteNode}, {sync_unregister, Name, Pid}).

-spec sync_demonitor_and_kill_on_node(
    Name :: any(),
    Pid :: pid(),
    Meta :: any(),
    MonitorRef :: reference(),
    Kill :: boolean()
) -> ok.
sync_demonitor_and_kill_on_node(Name, Pid, Meta, MonitorRef, Kill) ->
    RemoteNode = node(Pid),
    ProcessName = syn_backbone:get_process_name(syn_registry, syn_backbone:get_shard(Name)),
    gen_server:cast({ProcessName, RemoteNode}, {sync_demonitor_and_kill_on_node, Name, Pid, Meta, MonitorRef, Kill}).

-spec sync_get_local_registry_tuples(FromNode :: node(), SynRegistryByNameEts :: atom()) -> [syn_registry_tuple()].
sync_get_local_registry_tuples(FromNode, SynRegistryByNameEts) ->
    error_logger:info_msg(
        "Syn(~p): Received request of local registry tuples ~p from remote node ~p~n",
        [node(), SynRegistryByNameEts, FromNode]
    ),
    get_registry_tuples_for_node(node(), SynRegistryByNameEts).

-spec force_cluster_sync() -> ok.
force_cluster_sync() ->
    SynShards = application:get_env(syn, syn_shards, 1),
    lists:foreach(
        fun(Id) ->
            ModuleName = syn_backbone:get_process_name(syn_registry, Id),
            do_force_cluster_sync(ModuleName)
        end,
        lists:seq(1, SynShards)
    ).

-spec do_force_cluster_sync(ModuleName :: atom()) -> ok.
do_force_cluster_sync(ModuleName) ->
    lists:foreach(fun(RemoteNode) ->
        gen_server:cast({ModuleName, RemoteNode}, force_cluster_sync)
    end, [node() | nodes()]).

%% ===================================================================
%% Callbacks
%% ===================================================================

%% ----------------------------------------------------------------------------------------------------------
%% Init
%% ----------------------------------------------------------------------------------------------------------
-spec init({ProcessName :: atom(), Id :: integer()}) ->
    {ok, #state{}} |
    {ok, #state{}, Timeout :: non_neg_integer()} |
    ignore |
    {stop, Reason :: any()}.
init({ProcessName, Id}) ->
    EtsTables = syn_backbone:ets_names(Id),
    %% monitor nodes
    ok = net_kernel:monitor_nodes(true),
    %% rebuild monitors (if coming after a crash)
    SynRegistryByNameEts = maps:get(syn_registry_by_name, EtsTables),
    rebuild_monitors(SynRegistryByNameEts),
    %% start multicast process
    MulticastPid = spawn_link(?MODULE, multicast_loop, []),
    %% get handler
    CustomEventHandler = syn_backbone:get_event_handler_module(),
    %% get anti-entropy interval
    {AntiEntropyIntervalMs, AntiEntropyIntervalMaxDeviationMs} = syn_backbone:get_anti_entropy_settings(registry),
    %% build state
    State = #state{
        process_name = ProcessName,
        syn_registry_by_name_ets = SynRegistryByNameEts,
        custom_event_handler = CustomEventHandler,
        anti_entropy_interval_ms = AntiEntropyIntervalMs,
        anti_entropy_interval_max_deviation_ms = AntiEntropyIntervalMaxDeviationMs,
        multicast_pid = MulticastPid
    },
    %% send message to initiate full cluster sync
    timer:send_after(0, self(), sync_from_full_cluster),
    %% start anti-entropy
    set_timer_for_anti_entropy(State),
    %% init
    {ok, State}.

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

handle_call({register_on_node, ProcessName, Name, Pid, Meta, Force}, _From, State) ->
    %% check if pid is alive
    case is_process_alive(Pid) of
        true ->
            %% check if name available
            case find_registry_tuple_by_name(Name) of
                undefined ->
                    %% available
                    {ok, Time} = register_on_node(ProcessName, Name, Pid, Meta),
                    %% multicast
                    multicast_register(Name, Pid, Meta, Time, false, State),
                    %% return
                    {reply, ok, State};

                {Name, Pid, _, _} ->
                    % same pid, overwrite
                    {ok, Time} = register_on_node(ProcessName, Name, Pid, Meta),
                    %% multicast
                    multicast_register(Name, Pid, Meta, Time, false, State),
                    %% return
                    {reply, ok, State};

                {Name, TablePid, _, _} ->
                    %% same name, different pid
                    case Force of
                        true ->
                            demonitor_if_local(ProcessName, TablePid),
                            %% force register
                            {ok, Time} = register_on_node(ProcessName, Name, Pid, Meta),
                            %% multicast
                            multicast_register(Name, Pid, Meta, Time, true, State),
                            %% return
                            {reply, ok, State};

                        _ ->
                            {reply, {error, taken}, State}
                    end
            end;
        _ ->
            {reply, {error, not_alive}, State}
    end;

handle_call({unregister_on_node, ProcessName, Name}, _From, State) ->
    case unregister_on_node(ProcessName, Name) of
        {ok, RemovedPid} ->
            multicast_unregister(Name, RemovedPid, State),
            %% return
            {reply, ok, State};
        {error, Reason} ->
            %% return
            {reply, {error, Reason}, State}
    end;

handle_call(Request, From, #state{process_name = ProcessName} = State) ->
    error_logger:warning_msg(
        "Syn(~p ~p): Received from ~p an unknown call message: ~p~n",
        [node(), ProcessName, Request, From]
    ),
    {reply, undefined, State}.

%% ----------------------------------------------------------------------------------------------------------
%% Cast messages
%% ----------------------------------------------------------------------------------------------------------
-spec handle_cast(Msg :: any(), #state{}) ->
    {noreply, #state{}} |
    {noreply, #state{}, Timeout :: non_neg_integer()} |
    {stop, Reason :: any(), #state{}}.

handle_cast({sync_register, Name, RemotePid, RemoteMeta, RemoteTime, Force},
    #state{process_name = ProcessName} = State) ->
    %% check for conflicts
    case find_registry_tuple_by_name(Name) of
        undefined ->
            %% no conflict
            add_to_local_table(Name, RemotePid, RemoteMeta, RemoteTime, undefined);

        {Name, RemotePid, _, _} ->
            %% same process, no conflict, overwrite
            add_to_local_table(Name, RemotePid, RemoteMeta, RemoteTime, undefined);

        {Name, TablePid, _, _} when Force =:= true ->
            demonitor_if_local(ProcessName, TablePid),
            %% overwrite
            add_to_local_table(Name, RemotePid, RemoteMeta, RemoteTime, undefined);

        {Name, TablePid, TableMeta, TableTime} when Force =:= false ->
            %% different pid, we have a conflict
            global:trans({{ProcessName, {inconsistent_name, Name}}, self()},
                fun() ->
                    error_logger:warning_msg(
                        "Syn(~p ~p): REGISTRY INCONSISTENCY (name: ~p for ~p and ~p) ----> Received from remote node ~p~n",
                        [node(), ProcessName, Name,
                            {TablePid, TableMeta, TableTime},
                            {RemotePid, RemoteMeta, RemoteTime},
                            node(RemotePid)
                        ]
                    ),

                    case resolve_conflict(Name, {TablePid, TableMeta, TableTime}, {RemotePid, RemoteMeta, RemoteTime}, State) of
                        {TablePid, KillOtherPid} ->
                            %% keep table
                            %% demonitor
                            MonitorRef = rpc:call(node(RemotePid), syn_registry, find_monitor_for_pid, [ProcessName, RemotePid]),
                            sync_demonitor_and_kill_on_node(Name, RemotePid, RemoteMeta, MonitorRef, KillOtherPid),
                            %% overwrite local data to all remote nodes, except TablePid's node
                            NodesExceptLocalAndTablePidNode = nodes() -- [node(TablePid)],
                            lists:foreach(fun(RNode) ->
                                ok = rpc:call(RNode,
                                    syn_registry, add_to_local_table,
                                    [Name, TablePid, TableMeta, TableTime, undefined]
                                )
                            end, NodesExceptLocalAndTablePidNode);

                        {RemotePid, KillOtherPid} ->
                            %% keep remote
                            %% demonitor
                            MonitorRef = rpc:call(node(TablePid), syn_registry, find_monitor_for_pid, [ProcessName, TablePid]),
                            sync_demonitor_and_kill_on_node(Name, TablePid, TableMeta, MonitorRef, KillOtherPid),
                            %% overwrite remote data to all other nodes (including local), except RemotePid's node
                            NodesExceptRemoteNode = [node() | nodes()] -- [node(RemotePid)],
                            lists:foreach(fun(RNode) ->
                                ok = rpc:call(RNode,
                                    syn_registry, add_to_local_table,
                                    [Name, RemotePid, RemoteMeta, RemoteTime, undefined]
                                )
                            end, NodesExceptRemoteNode);

                        undefined ->
                            AllNodes = [node() | nodes()],
                            %% both are dead, remove from all nodes
                            lists:foreach(fun(RNode) ->
                                ok = rpc:call(RNode, syn_registry, remove_from_local_table, [Name, RemotePid])
                            end, AllNodes)
                    end,

                    error_logger:info_msg(
                        "Syn(~p ~p): REGISTRY INCONSISTENCY (name: ~p)  <---- Done on all cluster~n",
                        [node(), ProcessName, Name]
                    )
                end
            )
    end,
    %% return
    {noreply, State};

handle_cast({sync_unregister, Name, Pid}, State) ->
    %% remove
    remove_from_local_table(Name, Pid),
    %% return
    {noreply, State};

handle_cast(force_cluster_sync, #state{process_name = ProcessName} = State) ->
    error_logger:info_msg(
        "Syn(~p ~p): Initiating full cluster FORCED registry sync for nodes: ~p~n",
        [node(), ProcessName, nodes()]
    ),
    do_sync_from_full_cluster(State),
    {noreply, State};

handle_cast(
    {sync_demonitor_and_kill_on_node, Name, Pid, Meta, MonitorRef, Kill},
    #state{process_name = ProcessName} = State
) ->
    error_logger:info_msg("Syn(~p ~p): Sync demonitoring pid ~p~n", [node(), ProcessName, Pid]),
    %% demonitor
    catch erlang:demonitor(MonitorRef, [flush]),
    %% kill
    case Kill of
        true ->
            exit(Pid, {syn_resolve_kill, Name, Meta});

        _ ->
            ok
    end,
    {noreply, State};

handle_cast(Msg, #state{process_name = ProcessName} = State) ->
    error_logger:warning_msg("Syn(~p ~p): Received an unknown cast message: ~p~n", [node(), ProcessName, Msg]),
    {noreply, State}.

%% ----------------------------------------------------------------------------------------------------------
%% All non Call / Cast messages
%% ----------------------------------------------------------------------------------------------------------
-spec handle_info(Info :: any(), #state{}) ->
    {noreply, #state{}} |
    {noreply, #state{}, Timeout :: non_neg_integer()} |
    {stop, Reason :: any(), #state{}}.

handle_info({'DOWN', _MonitorRef, process, Pid, Reason}, #state{process_name = ProcessName} = State) ->
    case find_registry_tuples_by_pid(ProcessName, Pid) of
        [] ->
            %% handle
            handle_process_down(undefined, Pid, undefined, Reason, State);

        Entries ->
            lists:foreach(fun({Name, _Pid, Meta, _Time}) ->
                %% handle
                handle_process_down(Name, Pid, Meta, Reason, State),
                %% remove from table
                remove_from_local_table(Name, Pid),
                %% multicast
                multicast_unregister(Name, Pid, State)
            end, Entries)
    end,
    %% return
    {noreply, State};

handle_info({nodeup, RemoteNode}, #state{process_name = ProcessName} = State) ->
    error_logger:info_msg(
        "Syn(~p ~p): Node ~p has joined the cluster~n",
        [node(), ProcessName, RemoteNode]
    ),
    registry_automerge(RemoteNode, State),
    %% resume
    {noreply, State};

handle_info(
    {nodedown, RemoteNode},
    #state{syn_registry_by_name_ets = SynRegistryByNameEts, process_name = ProcessName} = State
) ->
    error_logger:warning_msg(
        "Syn(~p ~p): Node ~p has left the cluster, removing registry entries on local~n",
        [node(), ProcessName, RemoteNode]
    ),
    raw_purge_registry_entries_for_remote_node(RemoteNode, SynRegistryByNameEts, ProcessName),
    {noreply, State};

handle_info(sync_from_full_cluster, #state{process_name = ProcessName} = State) ->
    error_logger:info_msg(
        "Syn(~p ~p): Initiating full cluster registry sync for nodes: ~p~n",
        [node(), ProcessName, nodes()]
    ),
    do_sync_from_full_cluster(State),
    {noreply, State};

handle_info(sync_anti_entropy, #state{process_name = ProcessName} = State) ->
    %% sync
    RemoteNodes = nodes(),
    case length(RemoteNodes) > 0 of
        true ->
            RandomRemoteNode = lists:nth(rand:uniform(length(RemoteNodes)), RemoteNodes),
            error_logger:info_msg(
                "Syn(~p ~p): Initiating anti-entropy sync for node ~p ~n",
                [node(), ProcessName, RandomRemoteNode]
            ),
            registry_automerge(RandomRemoteNode, State);

        _ ->
            ok
    end,
    %% set timer
    set_timer_for_anti_entropy(State),
    %% return
    {noreply, State};

handle_info(Info, #state{process_name = ProcessName} = State) ->
    error_logger:warning_msg("Syn(~p ~p) ~p: Received an unknown info message: ~p~n", [node(), ProcessName, Info]),
    {noreply, State}.

%% ----------------------------------------------------------------------------------------------------------
%% Terminate
%% ----------------------------------------------------------------------------------------------------------
-spec terminate(Reason :: any(), #state{}) -> terminated.
terminate(Reason, #state{
    multicast_pid = MulticastPid,
    process_name = ProcessName
}) ->
    error_logger:info_msg("Syn(~p ~p) : Terminating with reason: ~p~n", [node(), ProcessName, Reason]),
    MulticastPid ! terminate,
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
-spec multicast_register(
    Name :: any(),
    Pid :: pid(),
    Meta :: any(),
    Time :: integer(),
    Force :: boolean(),
    #state{}
) -> any().
multicast_register(Name, Pid, Meta, Time, Force, #state{
    multicast_pid = MulticastPid
}) ->
    MulticastPid ! {multicast_register, Name, Pid, Meta, Time, Force}.

-spec multicast_unregister(Name :: any(), Pid :: pid(), #state{}) -> any().
multicast_unregister(Name, Pid, #state{
    multicast_pid = MulticastPid
}) ->
    MulticastPid ! {multicast_unregister, Name, Pid}.

-spec register_on_node(ProcessName :: atom(), Name :: any(), Pid :: pid(), Meta :: any()) -> {ok, Time :: integer()}.
register_on_node(ProcessName, Name, Pid, Meta) ->
    MonitorRef = case find_monitor_for_pid(ProcessName, Pid) of
        undefined ->
            %% process is not monitored yet, add
            erlang:monitor(process, Pid);

        MRef ->
            MRef
    end,
    %% add to table
    Time = erlang:system_time(),
    add_to_local_table(Name, Pid, Meta, Time, MonitorRef),
    {ok, Time}.

-spec unregister_on_node(ProcessName :: atom(), Name :: any()) ->
    {ok, RemovedPid :: pid()} | {error, Reason :: any()}.
unregister_on_node(ProcessName, Name) ->
    case find_registry_entry_by_name(Name) of
        undefined ->
            {error, undefined};

        {{Name, Pid}, _Meta, _Clock, MonitorRef, _Node} when MonitorRef =/= undefined ->
            %% demonitor if the process is not registered under other names
            maybe_demonitor(ProcessName, Pid),
            %% remove from table
            remove_from_local_table(Name, Pid),
            %% return
            {ok, Pid};

        {{Name, Pid}, _Meta, _Clock, _MonitorRef, Node} = RegistryEntry when Node =:= node() ->
            error_logger:error_msg(
                "Syn(~p): INTERNAL ERROR | Registry entry ~p has no monitor but it's running on node~n",
                [node(), RegistryEntry]
            ),
            %% remove from table
            remove_from_local_table(Name, Pid),
            %% return
            {ok, Pid};

        RegistryEntry ->
            %% race condition: un-registration request but entry in table is not a local pid (has no monitor)
            %% sync messages will take care of it
            error_logger:info_msg(
                "Syn(~p): Registry entry ~p is not monitored and it's not running on node~n",
                [node(), RegistryEntry]
            ),
            {error, remote_pid}
    end.

-spec maybe_demonitor(ProcessName :: atom(), Pid :: pid()) -> ok.
maybe_demonitor(ProcessName, Pid) ->
    %% try to retrieve 2 items
    %% if only 1 is returned it means that no other aliases exist for the Pid
    case ets:select(syn_registry_by_pid, [{
        {{ProcessName, Pid, '_'}, '_', '_', '$5', '_'},
        [],
        ['$5']
    }], 2) of
        {[MonitorRef], _} ->
            %% no other aliases, demonitor
            erlang:demonitor(MonitorRef, [flush]),
            ok;
        _ ->
            ok
    end.

-spec add_to_local_table(
    Name :: any(),
    Pid :: pid(),
    Meta :: any(),
    Time :: integer(),
    MonitorRef :: undefined | reference()
) -> ok.
add_to_local_table(Name, Pid, Meta, Time, MonitorRef) ->
    %% remove entry if previous exists
    case find_registry_tuple_by_name(Name) of
        undefined ->
            undefined;

        {Name, PreviousPid, _, _} ->
            remove_from_local_table(Name, PreviousPid)
    end,
    {ProcessName, SynRegistryByNameEts} = syn_backbone:get_procname_ets(Name, syn_registry),
    %% overwrite & add
    ets:insert(SynRegistryByNameEts, {{Name, Pid}, Meta, Time, MonitorRef, node(Pid)}),
    ets:insert(syn_registry_by_pid, {{ProcessName, Pid, Name}, Meta, Time, MonitorRef, node(Pid)}),
    ok.

-spec remove_from_local_table(Name :: any(), Pid :: pid()) -> ok.
remove_from_local_table(Name, Pid) ->
    {ProcessName, SynRegistryByNameEts} = syn_backbone:get_procname_ets(Name, syn_registry),
    ets:delete(SynRegistryByNameEts, {Name, Pid}),
    ets:delete(syn_registry_by_pid, {ProcessName, Pid, Name}),
    ok.

-spec find_registry_tuple_by_name(Name :: any()) -> RegistryTuple :: syn_registry_tuple() | undefined.
find_registry_tuple_by_name(Name) ->
    SynRegistryByNameEts = syn_backbone:get_ets(Name, syn_registry_by_name),
    case ets:select(SynRegistryByNameEts, [{
        {{Name, '$2'}, '$3', '$4', '_', '_'},
        [],
        [{{{const, Name}, '$2', '$3', '$4'}}]
    }]) of
        [RegistryTuple] -> RegistryTuple;
        _ -> undefined
    end.

-spec find_registry_entry_by_name(Name :: any()) -> Entry :: syn_registry_entry() | undefined.
find_registry_entry_by_name(Name) ->
    SynRegistryByNameEts = syn_backbone:get_ets(Name, syn_registry_by_name),
    case ets:select(SynRegistryByNameEts, [{
        {{Name, '$2'}, '$3', '_', '_', '_'},
        [],
        ['$_']
    }]) of
        [RegistryTuple] -> RegistryTuple;
        _ -> undefined
    end.

-spec find_monitor_for_pid(ProcessName :: atom(), Pid :: pid()) -> reference() | undefined.
find_monitor_for_pid(ProcessName, Pid) when is_pid(Pid) ->
    case ets:select(syn_registry_by_pid, [{
        {{ProcessName, Pid, '_'}, '_', '_', '$5', '_'},
        [],
        ['$5']
    }], 1) of
        {[MonitorRef], _} -> MonitorRef;
        _ -> undefined
    end.

-spec find_registry_tuples_by_pid(ProcessName :: atom(), Pid :: pid()) -> RegistryTuples :: [syn_registry_tuple()].
find_registry_tuples_by_pid(ProcessName, Pid) when is_pid(Pid) ->
    ets:select(syn_registry_by_pid, [{
        {{ProcessName, Pid, '$2'}, '$3', '$4', '_', '_'},
        [],
        [{{'$2', Pid, '$3', '$4'}}]
    }]).

-spec get_registry_tuples_for_node(Node :: node(), SynRegistryByNameEts :: atom()) -> [syn_registry_tuple()].
get_registry_tuples_for_node(Node, SynRegistryByNameEts) ->
    ets:select(SynRegistryByNameEts, [{
        {{'$1', '$2'}, '$3', '$4', '_', Node},
        [],
        [{{'$1', '$2', '$3', '$4'}}]
    }]).

-spec handle_process_down(Name :: any(), Pid :: pid(), Meta :: any(), Reason :: any(), #state{}) -> ok.
handle_process_down(Name, Pid, Meta, Reason, #state{
    custom_event_handler = CustomEventHandler,
    process_name = ProcessName
}) ->
    case Name of
        undefined ->
            case Reason of
                {syn_resolve_kill, KillName, KillMeta} ->
                    syn_event_handler:do_on_process_exit(KillName, Pid, KillMeta, syn_resolve_kill, CustomEventHandler);

                _ ->
                    error_logger:warning_msg(
                        "Syn(~p ~p): Received a DOWN message from an unregistered process ~p with reason: ~p~n",
                        [node(), ProcessName, Pid, Reason]
                    )
            end;

        _ ->
            syn_event_handler:do_on_process_exit(Name, Pid, Meta, Reason, CustomEventHandler)
    end.

-spec registry_automerge(RemoteNode :: node(), #state{}) -> ok.
registry_automerge(RemoteNode, #state{
    process_name = ProcessName,
    syn_registry_by_name_ets = SynRegistryByNameEts
} = State) ->
    global:trans({{ProcessName, auto_merge_registry}, self()},
        fun() ->
            error_logger:info_msg(
                "Syn(~p ~p): REGISTRY AUTOMERGE ----> Initiating for remote node ~p~n",
                [node(), ProcessName, RemoteNode]
            ),
            %% get registry tuples from remote node
            case rpc:call(RemoteNode, ?MODULE, sync_get_local_registry_tuples, [node(), SynRegistryByNameEts]) of
                {badrpc, _} ->
                    error_logger:info_msg(
                        "Syn(~p ~p): REGISTRY AUTOMERGE <---- Syn not ready on remote node ~p, postponing~n",
                        [node(), ProcessName, RemoteNode]
                    );

                RegistryTuples ->
                    error_logger:info_msg(
                        "Syn(~p ~p): Received ~p registry tuple(s) from remote node ~p~n",
                        [node(), ProcessName, length(RegistryTuples), RemoteNode]
                    ),
                    %% ensure that registry doesn't have any joining node's entries (here again for race conditions)
                    raw_purge_registry_entries_for_remote_node(RemoteNode, SynRegistryByNameEts, ProcessName),
                    %% loop
                    F = fun({Name, RemotePid, RemoteMeta, RemoteTime}) ->
                        resolve_tuple_in_automerge(Name, RemotePid, RemoteMeta, RemoteTime, State)
                    end,
                    %% add to table
                    lists:foreach(F, RegistryTuples),
                    %% exit
                    error_logger:info_msg(
                        "Syn(~p ~p): REGISTRY AUTOMERGE <---- Done for remote node ~p~n",
                        [node(), ProcessName, RemoteNode]
                    )
            end
        end
    ).

-spec resolve_tuple_in_automerge(
    Name :: any(),
    RemotePid :: pid(),
    RemoteMeta :: any(),
    RemoteTime :: integer(),
    #state{}
) -> any().
resolve_tuple_in_automerge(
    Name, RemotePid, RemoteMeta, RemoteTime,
    #state{process_name = ProcessName} = State
) ->
    %% check if same name is registered
    case find_registry_tuple_by_name(Name) of
        undefined ->
            %% no conflict
            add_to_local_table(Name, RemotePid, RemoteMeta, RemoteTime, undefined);

        {Name, TablePid, TableMeta, TableTime} ->
            error_logger:warning_msg(
                "Syn(~p ~p): Conflicting name in auto merge for: ~p, processes are ~p, ~p~n",
                [node(), ProcessName, Name, {TablePid, TableMeta, TableTime}, {RemotePid, RemoteMeta, RemoteTime}]
            ),

            case resolve_conflict(Name, {TablePid, TableMeta, TableTime}, {RemotePid, RemoteMeta, RemoteTime}, State) of
                {TablePid, KillOtherPid} ->
                    %% keep local
                    %% demonitor
                    MonitorRef = rpc:call(node(RemotePid), syn_registry, find_monitor_for_pid, [ProcessName, RemotePid]),
                    sync_demonitor_and_kill_on_node(Name, RemotePid, RemoteMeta, MonitorRef, KillOtherPid),
                    %% remote data still on remote node, remove there
                    ok = rpc:call(node(RemotePid), syn_registry, remove_from_local_table, [Name, RemotePid]);

                {RemotePid, KillOtherPid} ->
                    %% keep remote
                    %% demonitor
                    MonitorRef = rpc:call(node(TablePid), syn_registry, find_monitor_for_pid, [ProcessName, TablePid]),
                    sync_demonitor_and_kill_on_node(Name, TablePid, TableMeta, MonitorRef, KillOtherPid),
                    %% overwrite remote data to local
                    add_to_local_table(Name, RemotePid, RemoteMeta, RemoteTime, undefined);

                undefined ->
                    %% both are dead, remove from local & remote
                    remove_from_local_table(Name, TablePid),
                    ok = rpc:call(node(RemotePid), syn_registry, remove_from_local_table, [Name, RemotePid])
            end
    end.

-spec resolve_conflict(
    Name :: any(),
    {TablePid :: pid(), TableMeta :: any(), TableTime :: integer()},
    {RemotePid :: pid(), RemoteMeta :: any(), RemoteTime :: integer()},
    #state{}
) -> {PidToKeep :: pid(), KillOtherPid :: boolean() | undefined} | undefined.
resolve_conflict(
    Name,
    {TablePid, TableMeta, TableTime},
    {RemotePid, RemoteMeta, RemoteTime},
    #state{custom_event_handler = CustomEventHandler, process_name = ProcessName}
) ->
    TablePidAlive = rpc:call(node(TablePid), erlang, is_process_alive, [TablePid]),
    RemotePidAlive = rpc:call(node(RemotePid), erlang, is_process_alive, [RemotePid]),

    %% check if pids are alive (race conditions if pid dies during resolution)
    {PidToKeep, KillOtherPid} = case {TablePidAlive, RemotePidAlive} of
        {true, true} ->
            %% call conflict resolution
            syn_event_handler:do_resolve_registry_conflict(
                Name,
                {TablePid, TableMeta, TableTime},
                {RemotePid, RemoteMeta, RemoteTime},
                CustomEventHandler
            );

        {true, false} ->
            %% keep only alive process
            {TablePid, false};

        {false, true} ->
            %% keep only alive process
            {RemotePid, false};

        {false, false} ->
            %% remove both
            {undefined, false}
    end,

    %% keep chosen one
    case PidToKeep of
        TablePid ->
            %% keep local
            error_logger:info_msg(
                "Syn(~p ~p): Keeping process in table ~p over remote process ~p~n",
                [node(), ProcessName, TablePid, RemotePid]
            ),
            {TablePid, KillOtherPid};

        RemotePid ->
            %% keep remote
            error_logger:info_msg(
                "Syn(~p ~p): Keeping remote process ~p over process in table ~p~n",
                [node(), ProcessName, RemotePid, TablePid]
            ),
            {RemotePid, KillOtherPid};

        undefined ->
            error_logger:info_msg(
                "Syn(~p ~p): Removing both processes' ~p and ~p data from local and remote tables~n",
                [node(), ProcessName, RemotePid, TablePid]
            ),
            undefined;

        Other ->
            error_logger:error_msg(
                "Syn(~p ~p): Custom handler returned ~p, valid options were ~p and ~p, removing both~n",
                [node(), ProcessName, Other, TablePid, RemotePid]
            ),
            undefined
    end.

-spec do_sync_from_full_cluster(#state{}) -> ok.
do_sync_from_full_cluster(State) ->
    lists:foreach(fun(RemoteNode) ->
        registry_automerge(RemoteNode, State)
    end, nodes()).

-spec raw_purge_registry_entries_for_remote_node(
    Node :: atom(), SynRegistryByNameEts :: atom(), ProcessName :: atom()) -> ok.
raw_purge_registry_entries_for_remote_node(Node, SynRegistryByNameEts, ProcessName) when Node =/= node() ->
    %% NB: no demonitoring is done, this is why it's raw
    ets:match_delete(SynRegistryByNameEts, {'_', '_', '_', '_', Node}),
    ets:match_delete(syn_registry_by_pid, {{ProcessName, '_', '_'}, '_', '_', '_', Node}),
    ok;

raw_purge_registry_entries_for_remote_node(_Node, _SynRegistryByNameEts, _ProcessName) ->
    ok.

-spec rebuild_monitors(SynRegistryByNameEts :: atom()) -> ok.
rebuild_monitors(SynRegistryByNameEts) ->
    RegistryTuples = get_registry_tuples_for_node(node(), SynRegistryByNameEts),
    lists:foreach(fun({Name, Pid, Meta, Time}) ->
        case is_process_alive(Pid) of
            true ->
                MonitorRef = erlang:monitor(process, Pid),
                %% overwrite
                add_to_local_table(Name, Pid, Meta, Time, MonitorRef);
            _ ->
                remove_from_local_table(Name, Pid)
        end
    end, RegistryTuples).

-spec set_timer_for_anti_entropy(#state{}) -> ok.
set_timer_for_anti_entropy(#state{anti_entropy_interval_ms = undefined}) -> ok;
set_timer_for_anti_entropy(#state{
    anti_entropy_interval_ms = AntiEntropyIntervalMs,
    anti_entropy_interval_max_deviation_ms = AntiEntropyIntervalMaxDeviationMs
}) ->
    IntervalMs = round(AntiEntropyIntervalMs + rand:uniform() * AntiEntropyIntervalMaxDeviationMs),
    {ok, _} = timer:send_after(IntervalMs, self(), sync_anti_entropy),
    ok.

-spec demonitor_if_local(atom(), pid()) -> ok.
demonitor_if_local(ProcessName, Pid) ->
    case node(Pid) =:= node() of
        true ->
            %% demonitor
            MonitorRef = syn_registry:find_monitor_for_pid(ProcessName, Pid),
            catch erlang:demonitor(MonitorRef, [flush]),
            ok;

        _ ->
            ok
    end.

-spec multicast_loop() -> terminated.
multicast_loop() ->
    receive
        {multicast_register, Name, Pid, Meta, Time, Force} ->
            lists:foreach(fun(RemoteNode) ->
                sync_register(RemoteNode, Name, Pid, Meta, Time, Force)
            end, nodes()),
            multicast_loop();

        {multicast_unregister, Name, Pid} ->
            lists:foreach(fun(RemoteNode) ->
                sync_unregister(RemoteNode, Name, Pid)
            end, nodes()),
            multicast_loop();

        terminate ->
            terminated
    end.
