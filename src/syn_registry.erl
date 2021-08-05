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
-export([register/2, register/3, register/4]).
-export([unregister/1, unregister/2]).
-export([lookup/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% tests
-ifdef(TEST).
-export([get_nodes/1]).
-endif.

%% records
-record(state, {
    scope = default :: atom(),
    process_name = syn_registry_default :: atom(),
    nodes = #{} :: #{node() => pid()},
    remote_scope_monitors = #{} :: #{pid() => reference()}
}).

%% includes
-include("syn.hrl").

%% ===================================================================
%% API
%% ===================================================================
-spec start_link(Scope :: atom()) -> {ok, pid()} | {error, any()}.
start_link(Scope) when is_atom(Scope) ->
    ProcessName = get_process_name(Scope),
    Args = [Scope, ProcessName],
    gen_server:start_link({local, ProcessName}, ?MODULE, Args, []).

-spec register(Name :: any(), Pid :: pid()) -> ok | {error, Reason :: any()}.
register(Name, Pid) ->
    register(default, Name, Pid, undefined).

-spec register(Name :: any(), Pid :: pid(), Meta :: term()) -> ok | {error, Reason :: any()}.
register(Name, Pid, Meta) ->
    register(default, Name, Pid, Meta).

-spec register(Scope :: atom(), Name :: any(), Pid :: pid(), Meta :: any()) -> ok | {error, Reason :: any()}.
register(Scope, Name, Pid, Meta) when is_pid(Pid) ->
    ProcessName = get_process_name(Scope),
    Node = node(Pid),
    gen_server:call({ProcessName, Node}, {register_on_node, Name, Pid, Meta}).

-spec lookup(Name :: any()) -> {pid(), Meta :: any()} | undefined.
lookup(Name) ->
    lookup(default, Name).

-spec lookup(Scope :: atom(), Name :: any()) -> {pid(), Meta :: any()} | undefined.
lookup(Scope, Name) ->
    case find_registry_tuple_by_scope_and_name(Scope, Name) of
        undefined -> undefined;
        {Name, Pid, Meta, _} -> {Pid, Meta}
    end.

-spec unregister(Name :: any()) -> ok | {error, Reason :: any()}.
unregister(Name) ->
    unregister(default, Name).

-spec unregister(Scope :: atom(), Name :: any()) -> ok | {error, Reason :: any()}.
unregister(Scope, Name) ->
    % get process' node
    case find_registry_tuple_by_scope_and_name(Scope, Name) of
        undefined ->
            {error, undefined};
        {Name, Pid, _, _} ->
            ProcessName = get_process_name(Scope),
            Node = node(Pid),
            gen_server:call({ProcessName, Node}, {unregister_on_node, Name})
    end.

%% ----- \/ cluster API ----------------------------------------------
-spec sync_register(
    RemoteNode :: node(),
    Scope :: atom(),
    Name :: any(),
    RemotePid :: pid(),
    RemoteMeta :: any(),
    RemoteTime :: integer()
) -> ok.
sync_register(RemoteNode, Scope, Name, RemotePid, RemoteMeta, RemoteTime) ->
    ProcessName = get_process_name(Scope),
    gen_server:cast({ProcessName, RemoteNode}, {sync_register, Name, RemotePid, RemoteMeta, RemoteTime}).

-spec sync_unregister(RemoteNode :: node(), Scope :: atom(), Name :: any(), Pid :: pid()) -> ok.
sync_unregister(RemoteNode, Scope, Name, Pid) ->
    ProcessName = get_process_name(Scope),
    gen_server:cast({ProcessName, RemoteNode}, {sync_unregister, Name, Pid}).

%% ----- \/ TESTS ----------------------------------------------------
-ifdef(TEST).
get_nodes(Scope) ->
    ProcessName = get_process_name(Scope),
    gen_server:call(ProcessName, get_nodes).
-endif.

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
handle_call({register_on_node, Name, Pid, Meta}, _From, #state{scope = Scope} = State) ->
    %% available
    {ok, Time} = register_on_node(Scope, Name, Pid, Meta),
    %% multicast
    multicast_register(Scope, Name, Pid, Meta, Time, State),
    %% return
    {reply, ok, State};

handle_call({unregister_on_node, Name}, _From, #state{scope = Scope} = State) ->
    case unregister_on_node(Scope, Name) of
        {ok, RemovedPid} ->
            multicast_unregister(Scope, Name, RemovedPid, State),
            %% return
            {reply, ok, State};

        {error, Reason} ->
            %% return
            {reply, {error, Reason}, State}
    end;

handle_call(get_nodes, _From, #state{
    nodes = Nodes
} = State) ->
    {reply, Nodes, State};

handle_call(Request, From, State) ->
    error_logger:warning_msg("Syn(~p): Received from ~p an unknown call message: ~p~n", [node(), Request, From]),
    {reply, undefined, State}.

%% ----------------------------------------------------------------------------------------------------------
%% Cast messages
%% ----------------------------------------------------------------------------------------------------------
-spec handle_cast(Msg :: any(), #state{}) ->
    {noreply, #state{}} |
    {noreply, #state{}, Timeout :: non_neg_integer()} |
    {stop, Reason :: any(), #state{}}.
handle_cast({sync_register, Name, RemotePid, RemoteMeta, RemoteTime}, #state{scope = Scope} = State) ->
    % check for conflicts
    case find_registry_tuple_by_scope_and_name(Scope, Name) of
        undefined ->
            %% no conflict
            add_to_local_table(Scope, Name, RemotePid, RemoteMeta, RemoteTime, undefined);

        {Name, RemotePid, _, _} ->
            %% same process, no conflict, overwrite
            add_to_local_table(Scope, Name, RemotePid, RemoteMeta, RemoteTime, undefined)
    end,
    {noreply, State};

handle_cast({sync_unregister, Name, Pid}, #state{scope = Scope} = State) ->
    %% remove
    remove_from_local_table(Scope, Name, Pid),
    %% return
    {noreply, State};

handle_cast(Msg, State) ->
    error_logger:warning_msg("Syn(~p): Received an unknown cast message: ~p~n", [node(), Msg]),
    {noreply, State}.

%% ----------------------------------------------------------------------------------------------------------
%% Info messages
%% ----------------------------------------------------------------------------------------------------------
-spec handle_info(Info :: any(), #state{}) ->
    {noreply, #state{}} |
    {noreply, #state{}, Timeout :: non_neg_integer()} |
    {stop, Reason :: any(), #state{}}.
handle_info(timeout, #state{
    scope = Scope,
    process_name = ProcessName
} = State) ->
    error_logger:info_msg("Syn(~p): Discovering nodes in the cluster with scope: ~p~n", [node(), Scope]),
    lists:foreach(fun(RemoteNode) ->
        %% send discover message to identically named process on other node
        {ProcessName, RemoteNode} ! {discover, self()}
    end, nodes()),
    {noreply, State};

handle_info({discover, RemoteScopePid}, #state{
    scope = Scope
} = State) ->
    error_logger:info_msg("Syn(~p): Received discover REQ from node ~p with scope: ~p~n",
        [node(), node(RemoteScopePid), Scope]
    ),
    case add_remote_scope_process(RemoteScopePid, State) of
        {true, State1} ->
            %% new remote scope process, send sync data back
            %% TODO: add data to send
            RemoteScopePid ! {sync, self(), []},
            %% return
            {noreply, State1};

        {false, State1} ->
            %% known scope process, do not sync
            %% return
            {noreply, State1}
    end;

handle_info({sync, RemoteScopePid, _Data}, #state{
    scope = Scope
} = State) ->
    error_logger:info_msg("Syn(~p): Received SYNC from node ~p with scope: ~p~n",
        [node(), node(RemoteScopePid), Scope]
    ),
    case add_remote_scope_process(RemoteScopePid, State) of
        {true, State1} ->
            %% new remote scope process, send sync data back
            %% TODO: add data to send
            RemoteScopePid ! {sync, self(), []},
            %% return
            {noreply, State1};

        {false, State1} ->
            %% known scope process, do not sync
            %% return
            {noreply, State1}
    end;

handle_info({'DOWN', _MonitorRef, process, Pid, Reason}, #state{scope = Scope} = State) ->
    case find_registry_tuples_by_scope_and_pid(Scope, Pid) of
        [] ->
            %% handle
            handle_process_down(Scope, undefined, Pid, undefined, Reason, State);

        Entries ->
            lists:foreach(fun({Name, _Pid, Meta, _Time}) ->
                %% handle
                handle_process_down(Scope, Name, Pid, Meta, Reason, State),
                %% remove from table
                remove_from_local_table(Scope, Name, Pid),
                %% multicast
                multicast_unregister(Scope, Name, Pid, State)
            end, Entries)
    end,
    %% return
    {noreply, State};

handle_info(Info, State) ->
    error_logger:warning_msg("Syn(~p): Received an unknown info message: ~p~n", [node(), Info]),
    {noreply, State}.

%% ----------------------------------------------------------------------------------------------------------
%% Terminate
%% ----------------------------------------------------------------------------------------------------------
-spec terminate(Reason :: any(), #state{}) -> terminated.
terminate(Reason, _State) ->
    error_logger:info_msg("Syn(~p): Terminating with reason: ~p~n", [node(), Reason]),
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
-spec get_process_name(Scope :: atom()) -> atom().
get_process_name(Scope) ->
    ModuleBin = atom_to_binary(?MODULE),
    ScopeBin = atom_to_binary(Scope),
    binary_to_atom(<<ModuleBin/binary, "_", ScopeBin/binary>>).

-spec get_table_name(TableName :: atom(), Scope :: atom()) -> atom().
get_table_name(TableName, Scope) ->
    TableNameBin = atom_to_binary(TableName),
    ScopeBin = atom_to_binary(Scope),
    binary_to_atom(<<TableNameBin/binary, "_", ScopeBin/binary>>).

-spec add_remote_scope_process(RemoteScopePid :: pid(), #state{}) -> {IsNew :: boolean(), #state{}}.
add_remote_scope_process(RemoteScopePid, #state{
    nodes = Nodes,
    remote_scope_monitors = RemoteScopeMonitors
} = State) ->
    %% add remote node (always update in case of race-conditions, when new pid is received)
    Nodes1 = maps:put(node(RemoteScopePid), RemoteScopePid, Nodes),

    %% add monitor if necessary
    case maps:find(RemoteScopePid, RemoteScopeMonitors) of
        error ->
            %% monitor does not exist, add
            MonitorRef = monitor(process, RemoteScopePid),
            RemoteScopeMonitors1 = maps:put(RemoteScopePid, MonitorRef, RemoteScopeMonitors),
            %% update state
            {true, State#state{nodes = Nodes1, remote_scope_monitors = RemoteScopeMonitors1}};

        {ok, _Ref} ->
            %% monitor already exists, return existing map
            {false, State#state{nodes = Nodes1}}
    end.

-spec find_registry_tuple_by_scope_and_name(Scope :: atom(), Name :: any()) ->
    RegistryTuple :: syn_registry_tuple() | undefined.
find_registry_tuple_by_scope_and_name(Scope, Name) ->
    TableName = get_table_name(syn_registry_by_name, Scope),
    case ets:select(TableName, [{
        {{Name, '$2'}, '$3', '$4', '_', '_'},
        [],
        [{{{const, Name}, '$2', '$3', '$4'}}]
    }]) of
        [RegistryTuple] -> RegistryTuple;
        _ -> undefined
    end.

-spec find_registry_entry_by_scope_and_name(Scope :: atom(), Name :: any()) -> Entry :: syn_registry_entry() | undefined.
find_registry_entry_by_scope_and_name(Scope, Name) ->
    TableName = get_table_name(syn_registry_by_name, Scope),
    case ets:select(TableName, [{
        {{Name, '$2'}, '$3', '_', '_', '_'},
        [],
        ['$_']
    }]) of
        [RegistryTuple] -> RegistryTuple;
        _ -> undefined
    end.

-spec find_registry_tuples_by_scope_and_pid(Scope :: atom(), Pid :: pid()) -> RegistryTuples :: [syn_registry_tuple()].
find_registry_tuples_by_scope_and_pid(Scope, Pid) when is_pid(Pid) ->
    TableName = get_table_name(syn_registry_by_pid, Scope),
    ets:select(TableName, [{
        {{Pid, '$2'}, '$3', '$4', '_', '_'},
        [],
        [{{'$2', Pid, '$3', '$4'}}]
    }]).

-spec find_monitor_for_scope_and_pid(Scope :: atom(), Pid :: pid()) -> reference() | undefined.
find_monitor_for_scope_and_pid(Scope, Pid) when is_pid(Pid) ->
    TableName = get_table_name(syn_registry_by_pid, Scope),
    case ets:select(TableName, [{
        {{Pid, '_'}, '_', '_', '$5', '_'},
        [],
        ['$5']
    }], 1) of
        {[MonitorRef], _} -> MonitorRef;
        _ -> undefined
    end.

-spec register_on_node(Scope :: atom(), Name :: any(), Pid :: pid(), Meta :: any()) -> {ok, Time :: integer()}.
register_on_node(Scope, Name, Pid, Meta) ->
    MonitorRef = case find_monitor_for_scope_and_pid(Scope, Pid) of
        undefined ->
            %% process is not monitored yet, add
            erlang:monitor(process, Pid);

        MRef ->
            MRef
    end,
    %% add to table
    Time = erlang:system_time(),
    add_to_local_table(Scope, Name, Pid, Meta, Time, MonitorRef),
    {ok, Time}.

-spec unregister_on_node(Scope :: atom(), Name :: any()) -> {ok, RemovedPid :: pid()} | {error, Reason :: any()}.
unregister_on_node(Scope, Name) ->
    case find_registry_entry_by_scope_and_name(Scope, Name) of
        undefined ->
            {error, undefined};

        {{Name, Pid}, _Meta, _Clock, MonitorRef, _Node} when MonitorRef =/= undefined ->
            %% demonitor if the process is not registered under other names
            maybe_demonitor(Scope, Pid),
            %% remove from table
            remove_from_local_table(Scope, Name, Pid),
            %% return
            {ok, Pid};

        {{Name, Pid}, _Meta, _Clock, _MonitorRef, Node} = RegistryEntry when Node =:= node() ->
            error_logger:error_msg(
                "Syn(~p): INTERNAL ERROR | Registry entry ~p has no monitor but it's running on node~n",
                [node(), RegistryEntry]
            ),
            %% remove from table
            remove_from_local_table(Scope, Name, Pid),
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

-spec handle_process_down(
    Scope :: atom(),
    Name :: any(),
    Pid :: pid(),
    Meta :: any(),
    Reason :: any(),
    #state{}
) -> ok.
handle_process_down(Scope, Name, Pid, Meta, Reason, _State) ->
    case Name of
        undefined ->
            case Reason of
                {syn_resolve_kill, KillName, KillMeta} ->
                    syn_event_handler:on_process_unregistered(Scope, KillName, Pid, KillMeta, syn_resolve_kill);

                _ ->
                    error_logger:warning_msg(
                        "Syn(~p): Received a DOWN message from an unregistered process ~p with reason: ~p~n",
                        [node(), Pid, Reason]
                    )
            end;

        _ ->
            syn_event_handler:on_process_unregistered(Scope, Name, Pid, Meta, Reason)
    end.

-spec maybe_demonitor(Scope :: atom(), Pid :: pid()) -> ok.
maybe_demonitor(Scope, Pid) ->
    %% try to retrieve 2 items
    %% if only 1 is returned it means that no other aliases exist for the Pid
    TableName = get_table_name(syn_registry_by_pid, Scope),
    case ets:select(TableName, [{
        {{Pid, '_'}, '_', '_', '$5', '_'},
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
    Scope :: atom(),
    Name :: any(),
    Pid :: pid(),
    Meta :: any(),
    Time :: integer(),
    MonitorRef :: undefined | reference()
) -> ok.
add_to_local_table(Scope, Name, Pid, Meta, Time, MonitorRef) ->
    ets:insert(get_table_name(syn_registry_by_name, Scope), {{Name, Pid}, Meta, Time, MonitorRef, node(Pid)}),
    ets:insert(get_table_name(syn_registry_by_pid, Scope), {{Pid, Name}, Meta, Time, MonitorRef, node(Pid)}),
    ok.

-spec remove_from_local_table(Scope :: atom(), Name :: any(), Pid :: pid()) -> ok.
remove_from_local_table(Scope, Name, Pid) ->
    ets:delete(get_table_name(syn_registry_by_name, Scope), {Name, Pid}),
    ets:delete(get_table_name(syn_registry_by_pid, Scope), {Pid, Name}),
    ok.

%% ----- \/ multicast ------------------------------------------------
-spec multicast_register(
    Scope :: atom(),
    Name :: any(),
    Pid :: pid(),
    Meta :: any(),
    Time :: integer(),
    #state{}
) -> any().
multicast_register(Scope, Name, Pid, Meta, Time, #state{
    nodes = Nodes
}) ->
    lists:foreach(fun(RemoteNode) ->
        sync_register(RemoteNode, Scope, Name, Pid, Meta, Time)
    end, maps:keys(Nodes)),
    ok.

-spec multicast_unregister(
    Scope :: atom(),
    Name :: any(),
    Pid :: pid(),
    #state{}
) -> any().
multicast_unregister(Scope, Name, Pid, #state{
    nodes = Nodes
}) ->
    lists:foreach(fun(RemoteNode) ->
        sync_unregister(RemoteNode, Scope, Name, Pid)
    end, maps:keys(Nodes)),
    ok.
