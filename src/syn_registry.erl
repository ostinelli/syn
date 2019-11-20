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
-export([start_link/0]).
-export([register/2, register/3]).
-export([unregister/1]).
-export([whereis/1, whereis/2]).
-export([count/0, count/1]).

%% sync API
-export([sync_get_local_registry_tuples/1]).
-export([add_to_local_table/4]).
-export([remove_from_local_table/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% records
-record(state, {
    custom_event_handler = undefined :: module()
}).

%% includes
-include("syn.hrl").

%% ===================================================================
%% API
%% ===================================================================
-spec start_link() -> {ok, pid()} | {error, any()}.
start_link() ->
    Options = [],
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], Options).

-spec register(Name :: any(), Pid :: pid()) -> ok | {error, Reason :: any()}.
register(Name, Pid) ->
    register(Name, Pid, undefined).

-spec register(Name :: any(), Pid :: pid(), Meta :: any()) -> ok | {error, Reason :: any()}.
register(Name, Pid, Meta) when is_pid(Pid) ->
    Node = node(Pid),
    gen_server:call({?MODULE, Node}, {register_on_node, Name, Pid, Meta}).

-spec unregister(Name :: any()) -> ok | {error, Reason :: any()}.
unregister(Name) ->
    % get process' node
    case find_process_entry_by_name(Name) of
        undefined ->
            {error, undefined};
        Entry ->
            Node = node(Entry#syn_registry_table.pid),
            gen_server:call({?MODULE, Node}, {unregister_on_node, Name})
    end.

-spec whereis(Name :: any()) -> pid() | undefined.
whereis(Name) ->
    case find_process_entry_by_name(Name) of
        undefined -> undefined;
        Entry -> Entry#syn_registry_table.pid
    end.

-spec whereis(Name :: any(), with_meta) -> {pid(), Meta :: any()} | undefined.
whereis(Name, with_meta) ->
    case find_process_entry_by_name(Name) of
        undefined -> undefined;
        Entry -> {Entry#syn_registry_table.pid, Entry#syn_registry_table.meta}
    end.

-spec count() -> non_neg_integer().
count() ->
    mnesia:table_info(syn_registry_table, size).

-spec count(Node :: node()) -> non_neg_integer().
count(Node) ->
    RegistryTuples = get_registry_tuples_for_node(Node),
    length(RegistryTuples).

-spec sync_get_local_registry_tuples(FromNode :: node()) -> [syn_registry_tuple()].
sync_get_local_registry_tuples(FromNode) ->
    error_logger:info_msg("Syn(~p): Received request of local registry tuples from remote node: ~p~n", [node(), FromNode]),
    get_registry_tuples_for_node(node()).

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
    %% rebuild monitors (if coming after a crash)
    rebuild_monitors(),
    %% monitor nodes
    ok = net_kernel:monitor_nodes(true),
    %% get handler
    CustomEventHandler = syn_backbone:get_event_handler_module(),
    %% init
    {ok, #state{
        custom_event_handler = CustomEventHandler
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

handle_call({register_on_node, Name, Pid, Meta}, _From, State) ->
    %% check if pid is alive
    case is_process_alive(Pid) of
        true ->
            %% check if name available
            case find_process_entry_by_name(Name) of
                undefined ->
                    register_on_node(Name, Pid, Meta),
                    %% multicast
                    multicast_register(Name, Pid, Meta),
                    %% return
                    {reply, ok, State};

                Entry when Entry#syn_registry_table.pid == Pid ->
                    register_on_node(Name, Pid, Meta),
                    %% multicast
                    multicast_register(Name, Pid, Meta),
                    %% return
                    {reply, ok, State};

                _ ->
                    {reply, {error, taken}, State}
            end;
        _ ->
            {reply, {error, not_alive}, State}
    end;

handle_call({unregister_on_node, Name}, _From, State) ->
    case unregister_on_node(Name) of
        ok ->
            multicast_unregister(Name),
            %% return
            {reply, ok, State};
        {error, Reason} ->
            %% return
            {reply, {error, Reason}, State}
    end;

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

handle_cast(Msg, State) ->
    error_logger:warning_msg("Syn(~p): Received an unknown cast message: ~p~n", [node(), Msg]),
    {noreply, State}.

%% ----------------------------------------------------------------------------------------------------------
%% All non Call / Cast messages
%% ----------------------------------------------------------------------------------------------------------
-spec handle_info(Info :: any(), #state{}) ->
    {noreply, #state{}} |
    {noreply, #state{}, Timeout :: non_neg_integer()} |
    {stop, Reason :: any(), #state{}}.

handle_info({'DOWN', _MonitorRef, process, Pid, Reason}, State) ->
    case find_processes_entry_by_pid(Pid) of
        [] ->
            %% handle
            handle_process_down(undefined, Pid, undefined, Reason, State);

        Entries ->
            lists:foreach(fun(Entry) ->
                %% get process info
                Name = Entry#syn_registry_table.name,
                Pid = Entry#syn_registry_table.pid,
                Meta = Entry#syn_registry_table.meta,
                %% handle
                handle_process_down(Name, Pid, Meta, Reason, State),
                %% remove from table
                remove_from_local_table(Name),
                %% multicast
                multicast_unregister(Name)
            end, Entries)
    end,
    %% return
    {noreply, State};

handle_info({nodeup, RemoteNode}, State) ->
    error_logger:info_msg("Syn(~p): Node ~p has joined the cluster~n", [node(), RemoteNode]),
    global:trans({{?MODULE, auto_merge_registry}, self()},
        fun() ->
            error_logger:warning_msg("Syn(~p): REGISTRY AUTOMERGE ----> Initiating for remote node ~p~n", [node(), RemoteNode]),
            %% get registry tuples from remote node
            RegistryTuples = rpc:call(RemoteNode, ?MODULE, sync_get_local_registry_tuples, [node()]),
            error_logger:warning_msg(
                "Syn(~p): Received ~p registry entrie(s) from remote node ~p, writing to local~n",
                [node(), length(RegistryTuples), RemoteNode]
            ),
            sync_registry_tuples(RemoteNode, RegistryTuples, State),
            %% exit
            error_logger:warning_msg("Syn(~p): REGISTRY AUTOMERGE <---- Done for remote node ~p~n", [node(), RemoteNode])
        end
    ),
    %% resume
    {noreply, State};

handle_info({nodedown, RemoteNode}, #state{
    custom_event_handler = CustomEventHandler
}=State) ->
    error_logger:warning_msg("Syn(~p): Node ~p has left the cluster, removing registry entries on local~n", [node(), RemoteNode]),
    purge_registry_entries_for_remote_node(RemoteNode, CustomEventHandler),
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
-spec multicast_register(Name :: any(), Pid :: pid(), Meta :: any()) -> pid().
multicast_register(Name, Pid, Meta) ->
    spawn_link(fun() ->
        rpc:eval_everywhere(nodes(), ?MODULE, add_to_local_table, [Name, Pid, Meta, undefined])
    end).

-spec multicast_unregister(Name :: any()) -> pid().
multicast_unregister(Name) ->
    spawn_link(fun() ->
        rpc:eval_everywhere(nodes(), ?MODULE, remove_from_local_table, [Name])
    end).

-spec register_on_node(Name :: any(), Pid :: pid(), Meta :: any()) -> ok.
register_on_node(Name, Pid, Meta) ->
    MonitorRef = case find_processes_entry_by_pid(Pid) of
        [] ->
            %% process is not monitored yet, add
            erlang:monitor(process, Pid);
        [Entry | _] ->
            Entry#syn_registry_table.monitor_ref
    end,
    %% add to table
    add_to_local_table(Name, Pid, Meta, MonitorRef).

-spec unregister_on_node(Name :: any()) -> ok | {error, Reason :: any()}.
unregister_on_node(Name) ->
    case find_process_entry_by_name(Name) of
        undefined ->
            {error, undefined};

        Entry when Entry#syn_registry_table.monitor_ref =/= undefined ->
            %% demonitor
            erlang:demonitor(Entry#syn_registry_table.monitor_ref),
            %% remove from table
            remove_from_local_table(Name)
    end.

-spec add_to_local_table(Name :: any(), Pid :: pid(), Meta :: any(), MonitorRef :: undefined | reference()) -> ok.
add_to_local_table(Name, Pid, Meta, MonitorRef) ->
    mnesia:dirty_write(#syn_registry_table{
        name = Name,
        pid = Pid,
        node = node(Pid),
        meta = Meta,
        monitor_ref = MonitorRef
    }).

-spec remove_from_local_table(Name :: any()) -> ok.
remove_from_local_table(Name) ->
    mnesia:dirty_delete(syn_registry_table, Name).

-spec find_processes_entry_by_pid(Pid :: pid()) -> Entries :: [#syn_registry_table{}].
find_processes_entry_by_pid(Pid) when is_pid(Pid) ->
    mnesia:dirty_index_read(syn_registry_table, Pid, #syn_registry_table.pid).

-spec find_process_entry_by_name(Name :: any()) -> Entry :: #syn_registry_table{} | undefined.
find_process_entry_by_name(Name) ->
    case mnesia:dirty_read(syn_registry_table, Name) of
        [Entry] -> Entry;
        _ -> undefined
    end.

-spec get_registry_tuples_for_node(Node :: node()) -> [syn_registry_tuple()].
get_registry_tuples_for_node(Node) ->
    %% build match specs
    MatchHead = #syn_registry_table{name = '$1', pid = '$2', node = '$3', meta = '$4', _ = '_'},
    Guard = {'=:=', '$3', Node},
    RegistryTupleFormat = {{'$1', '$2', '$4'}},
    %% select
    mnesia:dirty_select(syn_registry_table, [{MatchHead, [Guard], [RegistryTupleFormat]}]).

-spec handle_process_down(Name :: any(), Pid :: pid(), Meta :: any(), Reason :: any(), #state{}) -> ok.
handle_process_down(Name, Pid, Meta, Reason, #state{
    custom_event_handler = CustomEventHandler
}) ->
    case Name of
        undefined ->
            error_logger:warning_msg(
                "Syn(~p): Received a DOWN message from an unmonitored process ~p with reason: ~p~n",
                [node(), Pid, Reason]
            );
        _ ->
            syn_event_handler:do_on_process_exit(Name, Pid, Meta, Reason, CustomEventHandler)
    end.

-spec sync_registry_tuples(RemoteNode :: node(), RegistryTuples :: [syn_registry_tuple()], #state{}) -> ok.
sync_registry_tuples(RemoteNode, RegistryTuples, #state{
    custom_event_handler = CustomEventHandler
}) ->
    %% ensure that registry doesn't have any joining node's entries (here again for race conditions)
    purge_registry_entries_for_remote_node(RemoteNode,
                                           CustomEventHandler),
    %% loop
    F = fun({Name, RemotePid, RemoteMeta}) ->
        %% check if same name is registered
        case find_process_entry_by_name(Name) of
            undefined ->
                %% no conflict
                register_on_node(Name, RemotePid, RemoteMeta);

            Entry ->
                LocalPid = Entry#syn_registry_table.pid,
                LocalMeta = Entry#syn_registry_table.meta,

                error_logger:warning_msg(
                    "Syn(~p): Conflicting name process found for: ~p, processes are ~p, ~p~n",
                    [node(), Name, LocalPid, RemotePid]
                ),

                %% call conflict resolution
                {PidToKeep, KillOther} = syn_event_handler:do_resolve_registry_conflict(
                    Name,
                    {LocalPid, LocalMeta},
                    {RemotePid, RemoteMeta},
                    CustomEventHandler
                ),

                %% keep chosen one
                case PidToKeep of
                    LocalPid ->
                        %% keep local
                        ok = rpc:call(RemoteNode, syn_registry, remove_from_local_table, [Name]),
                        case KillOther of
                            true -> exit(RemotePid, kill);
                            _ -> ok
                        end;

                    RemotePid ->
                        %% keep remote
                        remove_from_local_table(Name),
                        add_to_local_table(Name, RemotePid, RemoteMeta, undefined),
                        case KillOther of
                            true -> exit(LocalPid, kill);
                            _ -> ok
                        end;

                    Other ->
                        error_logger:error_msg(
                            "Syn(~p): Custom handler returned ~p, valid options were ~p and ~p",
                            [node(), Other, LocalPid, RemotePid]
                        )
                end
        end
    end,
    %% add to table
    lists:foreach(F, RegistryTuples).

-spec purge_registry_entries_for_remote_node(Node :: atom(),
                                             CustomEventHandler ::
                                             module()) -> ok.
purge_registry_entries_for_remote_node(Node, CustomEventHandler) when Node =/= node() ->
    %% NB: no demonitoring is done, hence why this needs to run for a remote node
    %% build match specs
    MatchHead = #syn_registry_table{name = '$1', node = '$2', _ = '_'},
    Guard = {'=:=', '$2', Node},
    IdFormat = '$1',
    %% delete
    NodePids = mnesia:dirty_select(syn_registry_table, [{MatchHead, [Guard], [IdFormat]}]),
    DelF = fun(Id) -> mnesia:dirty_delete({syn_registry_table, Id}) end,
    lists:foreach(DelF, NodePids),
    syn_event_handler:do_notify_remote_node_entries_deleted(Node,
                                                            NodePids,
                                                            CustomEventHandler).

-spec rebuild_monitors() -> ok.
rebuild_monitors() ->
    RegistryTuples = get_registry_tuples_for_node(node()),
    lists:foreach(fun({Name, Pid, Meta}) ->
        case is_process_alive(Pid) of
            true ->
                MonitorRef = erlang:monitor(process, Pid),
                add_to_local_table(Name, Pid, Meta, MonitorRef);
            _ ->
                remove_from_local_table(Name)
        end
    end, RegistryTuples).
