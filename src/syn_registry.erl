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
-export([lookup/1]).
-export([register/2, register/3, register/4]).
-export([unregister/1, unregister/2]).

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
    case find_registry_entry_by_name(Scope, Name) of
        undefined -> undefined;
        {{Name, Pid}, Meta, _, _, _} -> {Pid, Meta}
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
    gen_server:call({ProcessName, Node}, {register_on_node, Name, Pid, Meta}).

-spec unregister(Name :: any()) -> ok | {error, Reason :: any()}.
unregister(Name) ->
    unregister(default, Name).

-spec unregister(Scope :: atom(), Name :: any()) -> ok | {error, Reason :: any()}.
unregister(Scope, Name) ->
    % get process' node
    case find_registry_entry_by_name(Scope, Name) of
        undefined ->
            {error, undefined};
        {{Name, Pid}, _, _, _, _} ->
            ProcessName = get_process_name_for_scope(Scope),
            Node = node(Pid),
            gen_server:call({ProcessName, Node}, {unregister_on_node, Name, Pid})
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

                {{Name, Pid}, _Meta, _Time, MRef, _Node} ->
                    %% same pid, possibly new meta, overwrite
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
        {{Name, Pid}, _Meta, _Clock, _MRef, _Node} ->
            %% demonitor if the process is not registered under other names
            maybe_demonitor(Scope, Pid),
            %% remove from table
            remove_from_local_table(Scope, Name, Pid),
            %% broadcast
            broadcast({'3.0', sync_unregister, Name, Pid}, State),
            %% return
            {reply, ok, State};

        {{Name, _TablePid}, _Meta, _Clock, _MRef, _Node} ->
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
    add_to_local_table(Scope, Name, Pid, Meta, Time, undefined),
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
    cast_to_node(RemoteScopeNode, {'3.0', sync, self(), []}, State),
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

handle_cast({'3.0', sync, RemoteScopePid, _Data}, #state{
    scope = Scope,
    nodes = Nodes
} = State) ->
    RemoteScopeNode = node(RemoteScopePid),
    error_logger:info_msg("SYN[~p] Received sync data from node ~p and scope ~p~n", [node(), RemoteScopeNode, Scope]),
    %% is this a new node?
    case maps:is_key(RemoteScopeNode, Nodes) of
        true ->
            %% already known, ignore
            {noreply, State};

        false ->
            %% if we don't know about the node, it is because it's the response to the first broadcast of announce message
            %% monitor
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
    PidNode = node(Pid),
    case maps:take(PidNode, Nodes) of
        {Pid, Nodes1} ->
            error_logger:warning_msg("SYN[~p] Scope Process ~p is DOWN on node ~p~n", [node(), Scope, PidNode]),
            %% TODO: remove data from node
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
            lists:foreach(fun({{Name, _Pid}, _Meta, _Time, _MRef, _Node}) ->
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

-spec find_registry_entry_by_name(Scope :: atom(), Name :: any()) -> Entry :: syn_registry_entry() | undefined.
find_registry_entry_by_name(Scope, Name) ->
    case ets:select(syn_backbone:get_table_name(syn_registry_by_name, Scope), [{
        {{Name, '_'}, '_', '_', '_', '_'},
        [],
        ['$_']
    }]) of
        [RegistryEntry] -> RegistryEntry;
        _ -> undefined
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
    TableName = syn_backbone:get_table_name(syn_registry_by_pid, Scope),
    case ets:select(TableName, [{
        {{Pid, '_'}, '_', '_', '$5', '_'},
        [],
        ['$5']
    }], 1) of
        {[MRef], _} -> MRef;
        _ -> undefined
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
        {[MRef], _} ->
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
    ets:insert(syn_backbone:get_table_name(syn_registry_by_name, Scope),
        {{Name, Pid}, Meta, Time, MRef, node(Pid)}
    ),
    ets:insert(syn_backbone:get_table_name(syn_registry_by_pid, Scope),
        {{Pid, Name}, Meta, Time, MRef, node(Pid)}
    ).

-spec remove_from_local_table(Scope :: atom(), Name :: any(), Pid :: pid()) -> true.
remove_from_local_table(Scope, Name, Pid) ->
    ets:delete(syn_backbone:get_table_name(syn_registry_by_name, Scope), {Name, Pid}),
    ets:delete(syn_backbone:get_table_name(syn_registry_by_pid, Scope), {Pid, Name}).
