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
-module(syn_groups).
-behaviour(gen_server).

%% API
-export([start_link/0]).
-export([join/2, join/3]).
-export([leave/2]).
-export([get_members/1, get_members/2]).
-export([get_group_names/0]).
-export([member/2]).
-export([get_local_members/1, get_local_members/2]).
-export([local_member/2]).
-export([count/0, count/1]).
-export([publish/2]).
-export([publish_to_local/2]).
-export([multi_call/2, multi_call/3, multi_call_reply/2]).

%% sync API
-export([sync_join/4, sync_leave/3]).
-export([sync_get_local_groups_tuples/1]).
-export([force_cluster_sync/0]).
-export([remove_from_local_table/2]).

%% internal
-export([multicast_loop/0]).

%% tests
-ifdef(TEST).
-export([add_to_local_table/4]).
-endif.

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% internal
-export([multi_call_and_receive/4]).

%% records
-record(state, {
    custom_event_handler :: undefined | module(),
    anti_entropy_interval_ms :: undefined | non_neg_integer(),
    anti_entropy_interval_max_deviation_ms :: undefined | non_neg_integer(),
    multicast_pid :: undefined | pid()
}).

%% macros
-define(DEFAULT_MULTI_CALL_TIMEOUT_MS, 5000).

%% includes
-include("syn.hrl").

%% ===================================================================
%% API
%% ===================================================================
-spec start_link() -> {ok, pid()} | {error, any()}.
start_link() ->
    Options = [],
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], Options).

-spec join(GroupName :: any(), Pid :: pid()) -> ok.
join(GroupName, Pid) ->
    join(GroupName, Pid, undefined).

-spec join(GroupName :: any(), Pid :: pid(), Meta :: any()) -> ok.
join(GroupName, Pid, Meta) when is_pid(Pid) ->
    Node = node(Pid),
    gen_server:call({?MODULE, Node}, {join_on_node, GroupName, Pid, Meta}).

-spec leave(GroupName :: any(), Pid :: pid()) -> ok | {error, Reason :: any()}.
leave(GroupName, Pid) ->
    case find_groups_entry_by_name_and_pid(GroupName, Pid) of
        undefined ->
            {error, not_in_group};
        _ ->
            Node = node(Pid),
            gen_server:call({?MODULE, Node}, {leave_on_node, GroupName, Pid})
    end.

-spec get_members(Name :: any()) -> [pid()].
get_members(GroupName) ->
    ets:select(syn_groups_by_name, [{
        {{GroupName, '$2'}, '_', '_', '_'},
        [],
        ['$2']
    }]).

-spec get_members(GroupName :: any(), with_meta) -> [{pid(), Meta :: any()}].
get_members(GroupName, with_meta) ->
    ets:select(syn_groups_by_name, [{
        {{GroupName, '$2'}, '$3', '_', '_'},
        [],
        [{{'$2', '$3'}}]
    }]).

-spec get_group_names() -> [GroupName :: any()].
get_group_names() ->
    Groups = ets:select(syn_groups_by_name, [{
      {{'$1', '_'}, '_', '_', '_'},
      [],
      ['$1']
    }]),
    Set = sets:from_list(Groups),
    sets:to_list(Set).

-spec member(Pid :: pid(), GroupName :: any()) -> boolean().
member(Pid, GroupName) ->
    case find_groups_entry_by_name_and_pid(GroupName, Pid) of
        undefined -> false;
        _ -> true
    end.

-spec get_local_members(Name :: any()) -> [pid()].
get_local_members(GroupName) ->
    Node = node(),
    ets:select(syn_groups_by_name, [{
        {{GroupName, '$2'}, '_', '_', Node},
        [],
        ['$2']
    }]).

-spec get_local_members(GroupName :: any(), with_meta) -> [{pid(), Meta :: any()}].
get_local_members(GroupName, with_meta) ->
    Node = node(),
    ets:select(syn_groups_by_name, [{
        {{GroupName, '$2'}, '$3', '_', Node},
        [],
        [{{'$2', '$3'}}]
    }]).

-spec local_member(Pid :: pid(), GroupName :: any()) -> boolean().
local_member(Pid, GroupName) ->
    case find_groups_entry_by_name_and_pid(GroupName, Pid) of
        {GroupName, Pid, _Meta, _MonitorRef, Node} when Node =:= node() ->
            true;

        _ ->
            false
    end.

-spec count() -> non_neg_integer().
count() ->
    Entries = ets:select(syn_groups_by_name, [{
        {{'$1', '_'}, '_', '_',  '_'},
        [],
        ['$1']
    }]),
    Set = sets:from_list(Entries),
    sets:size(Set).

-spec count(Node :: node()) -> non_neg_integer().
count(Node) ->
    Entries = ets:select(syn_groups_by_name, [{
        {{'$1', '_'}, '_', '_',  Node},
        [],
        ['$1']
    }]),
    Set = sets:from_list(Entries),
    sets:size(Set).

-spec publish(GroupName :: any(), Message :: any()) -> {ok, RecipientCount :: non_neg_integer()}.
publish(GroupName, Message) ->
    MemberPids = get_members(GroupName),
    FSend = fun(Pid) ->
        Pid ! Message
    end,
    lists:foreach(FSend, MemberPids),
    {ok, length(MemberPids)}.

-spec publish_to_local(GroupName :: any(), Message :: any()) -> {ok, RecipientCount :: non_neg_integer()}.
publish_to_local(GroupName, Message) ->
    MemberPids = get_local_members(GroupName),
    FSend = fun(Pid) ->
        Pid ! Message
    end,
    lists:foreach(FSend, MemberPids),
    {ok, length(MemberPids)}.

-spec multi_call(GroupName :: any(), Message :: any()) -> {[{pid(), Reply :: any()}], [BadPid :: pid()]}.
multi_call(GroupName, Message) ->
    multi_call(GroupName, Message, ?DEFAULT_MULTI_CALL_TIMEOUT_MS).

-spec multi_call(GroupName :: any(), Message :: any(), Timeout :: non_neg_integer()) ->
    {[{pid(), Reply :: any()}], [BadPid :: pid()]}.
multi_call(GroupName, Message, Timeout) ->
    Self = self(),
    MemberPids = get_members(GroupName),
    FSend = fun(Pid) ->
        spawn_link(?MODULE, multi_call_and_receive, [Self, Pid, Message, Timeout])
    end,
    lists:foreach(FSend, MemberPids),
    collect_replies(MemberPids).

-spec multi_call_reply(CallerPid :: pid(), Reply :: any()) -> {syn_multi_call_reply, pid(), Reply :: any()}.
multi_call_reply(CallerPid, Reply) ->
    CallerPid ! {syn_multi_call_reply, self(), Reply}.

-spec sync_join(RemoteNode :: node(), GroupName :: any(), Pid :: pid(), Meta :: any()) -> ok.
sync_join(RemoteNode, GroupName, Pid, Meta) ->
    gen_server:cast({?MODULE, RemoteNode}, {sync_join, GroupName, Pid, Meta}).

-spec sync_leave(RemoteNode :: node(), GroupName :: any(), Pid :: pid()) -> ok.
sync_leave(RemoteNode, GroupName, Pid) ->
    gen_server:cast({?MODULE, RemoteNode}, {sync_leave, GroupName, Pid}).

-spec sync_get_local_groups_tuples(FromNode :: node()) -> list(syn_groups_tuple()).
sync_get_local_groups_tuples(FromNode) ->
    error_logger:info_msg("Syn(~p): Received request of local group tuples from remote node: ~p~n", [node(), FromNode]),
    get_groups_tuples_for_node(node()).

-spec force_cluster_sync() -> ok.
force_cluster_sync() ->
    lists:foreach(fun(RemoteNode) ->
        gen_server:cast({?MODULE, RemoteNode}, force_cluster_sync)
    end, [node() | nodes()]).

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
    %% monitor nodes
    ok = net_kernel:monitor_nodes(true),
    %% rebuild
    rebuild_monitors(),
    %% start multicast process
    MulticastPid = spawn_link(?MODULE, multicast_loop, []),
    %% get handler
    CustomEventHandler = syn_backbone:get_event_handler_module(),
    %% get anti-entropy interval
    {AntiEntropyIntervalMs, AntiEntropyIntervalMaxDeviationMs} = syn_backbone:get_anti_entropy_settings(groups),
    %% build state
    State = #state{
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

handle_call({join_on_node, GroupName, Pid, Meta}, _From, State) ->
    %% check if pid is alive
    case is_process_alive(Pid) of
        true ->
            join_on_node(GroupName, Pid, Meta),
            %% multicast
            multicast_join(GroupName, Pid, Meta, State),
            %% return
            {reply, ok, State};
        _ ->
            {reply, {error, not_alive}, State}
    end;

handle_call({leave_on_node, GroupName, Pid}, _From, State) ->
    case leave_on_node(GroupName, Pid) of
        ok ->
            %% multicast
            multicast_leave(GroupName, Pid, State),
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

handle_cast({sync_join, GroupName, Pid, Meta}, State) ->
    %% add to table
    add_to_local_table(GroupName, Pid, Meta, undefined),
    %% return
    {noreply, State};

handle_cast({sync_leave, GroupName, Pid}, State) ->
    %% remove entry
    remove_from_local_table(GroupName, Pid),
    %% return
    {noreply, State};

handle_cast(force_cluster_sync, State) ->
    error_logger:info_msg("Syn(~p): Initiating full cluster groups FORCED sync for nodes: ~p~n", [node(), nodes()]),
    do_sync_from_full_cluster(),
    {noreply, State};

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
    case find_groups_tuples_by_pid(Pid) of
        [] ->
            %% handle
            handle_process_down(undefined, Pid, undefined, Reason, State);

        GroupTuples ->
            lists:foreach(fun({GroupName, _Pid, Meta}) ->
                %% remove from table
                remove_from_local_table(GroupName, Pid),
                %% handle
                handle_process_down(GroupName, Pid, Meta, Reason, State),
                %% multicast
                multicast_leave(GroupName, Pid, State)
            end, GroupTuples)
    end,
    %% return
    {noreply, State};

handle_info({nodeup, RemoteNode}, State) ->
    error_logger:info_msg("Syn(~p): Node ~p has joined the cluster~n", [node(), RemoteNode]),
    groups_automerge(RemoteNode),
    %% resume
    {noreply, State};

handle_info({nodedown, RemoteNode}, State) ->
    error_logger:warning_msg("Syn(~p): Node ~p has left the cluster, removing group entries on local~n", [node(), RemoteNode]),
    raw_purge_group_entries_for_node(RemoteNode),
    {noreply, State};

handle_info(sync_from_full_cluster, State) ->
    error_logger:info_msg("Syn(~p): Initiating full cluster groups sync for nodes: ~p~n", [node(), nodes()]),
    do_sync_from_full_cluster(),
    {noreply, State};

handle_info(sync_anti_entropy, State) ->
    %% sync
    RemoteNodes = nodes(),
    case length(RemoteNodes) > 0 of
        true ->
            RandomRemoteNode = lists:nth(rand:uniform(length(RemoteNodes)), RemoteNodes),
            error_logger:info_msg("Syn(~p): Initiating anti-entropy sync for node ~p~n", [node(), RandomRemoteNode]),
            groups_automerge(RandomRemoteNode);

        _ ->
            ok
    end,
    %% set timer
    set_timer_for_anti_entropy(State),
    %% return
    {noreply, State};

handle_info(Info, State) ->
    error_logger:warning_msg("Syn(~p): Received an unknown info message: ~p~n", [node(), Info]),
    {noreply, State}.

%% ----------------------------------------------------------------------------------------------------------
%% Terminate
%% ----------------------------------------------------------------------------------------------------------
-spec terminate(Reason :: any(), #state{}) -> terminated.
terminate(Reason, #state{
    multicast_pid = MulticastPid
}) ->
    error_logger:info_msg("Syn(~p): Terminating with reason: ~p~n", [node(), Reason]),
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
-spec multicast_join(GroupName :: any(), Pid :: pid(), Meta :: any(), #state{}) -> any().
multicast_join(GroupName, Pid, Meta, #state{
    multicast_pid = MulticastPid
}) ->
    MulticastPid ! {multicast_join, GroupName, Pid, Meta}.

-spec multicast_leave(GroupName :: any(), Pid :: pid(), #state{}) -> any().
multicast_leave(GroupName, Pid, #state{
    multicast_pid = MulticastPid
}) ->
    MulticastPid ! {multicast_leave, GroupName, Pid}.

-spec join_on_node(GroupName :: any(), Pid :: pid(), Meta :: any()) -> ok.
join_on_node(GroupName, Pid, Meta) ->
    MonitorRef = case find_monitor_for_pid(Pid) of
        undefined ->
            %% process is not monitored yet, add
            erlang:monitor(process, Pid);

        MRef ->
            MRef
    end,
    %% add to table
    add_to_local_table(GroupName, Pid, Meta, MonitorRef).

-spec leave_on_node(GroupName :: any(), Pid :: pid()) -> ok | {error, Reason :: any()}.
leave_on_node(GroupName, Pid) ->
    case find_groups_entry_by_name_and_pid(GroupName, Pid) of
        undefined ->
            {error, not_in_group};

        {GroupName, Pid, _Meta, MonitorRef, _Node} when MonitorRef =/= undefined ->
            %% is this the last group process is in?
            case find_groups_tuples_by_pid(Pid) of
                [_GroupTuple] ->
                    %% only one left (the one we're about to delete), demonitor
                    erlang:demonitor(MonitorRef, [flush]);

                _ ->
                    ok
            end,
            %% remove from table
            remove_from_local_table(GroupName, Pid);

        {GroupName, Pid, _Meta, _MonitorRef, Node} = GroupsEntry when Node =:= node() ->
            error_logger:error_msg(
                "Syn(~p): INTERNAL ERROR | Group entry ~p has no monitor but it's running on node~n",
                [node(), GroupsEntry]
            ),
            %% remove from table
            remove_from_local_table(GroupName, Pid);

        _ ->
            %% race condition: leave request but entry in table is not a local pid (has no monitor)
            %% ignore it, sync messages will take care of it
            ok
    end.

-spec add_to_local_table(GroupName :: any(), Pid :: pid(), Meta :: any(), MonitorRef :: undefined | reference()) -> ok.
add_to_local_table(GroupName, Pid, Meta, MonitorRef) ->
    ets:insert(syn_groups_by_name, {{GroupName, Pid}, Meta, MonitorRef, node(Pid)}),
    ets:insert(syn_groups_by_pid, {{Pid, GroupName}, Meta, MonitorRef, node(Pid)}),
    ok.

-spec remove_from_local_table(GroupName :: any(), Pid :: pid()) -> ok | {error, Reason :: any()}.
remove_from_local_table(GroupName, Pid) ->
    case ets:lookup(syn_groups_by_name, {GroupName, Pid}) of
        [] ->
            {error, not_in_group};

        _ ->
            ets:match_delete(syn_groups_by_name, {{GroupName, Pid}, '_', '_', '_'}),
            ets:match_delete(syn_groups_by_pid, {{Pid, GroupName}, '_', '_', '_'}),
            ok
    end.

-spec find_groups_tuples_by_pid(Pid :: pid()) -> GroupTuples :: list(syn_groups_tuple()).
find_groups_tuples_by_pid(Pid) when is_pid(Pid) ->
    ets:select(syn_groups_by_pid, [{
        {{Pid, '$2'}, '$3', '_', '_'},
        [],
        [{{'$2', Pid, '$3'}}]
    }]).

-spec find_groups_entry_by_name_and_pid(GroupName :: any(), Pid :: pid()) -> Entry :: syn_groups_entry() | undefined.
find_groups_entry_by_name_and_pid(GroupName, Pid) ->
    case ets:select(syn_groups_by_name, [{
        {{GroupName, Pid}, '$3', '$4', '$5'},
        [],
        [{{{const, GroupName}, Pid, '$3', '$4', '$5'}}]
    }]) of
        [RegistryTuple] -> RegistryTuple;
        _ -> undefined
    end.

-spec find_monitor_for_pid(Pid :: pid()) -> reference() | undefined.
find_monitor_for_pid(Pid) when is_pid(Pid) ->
    case ets:select(syn_groups_by_pid, [{
        {{Pid, '_'}, '_', '$4', '_'},
        [],
        ['$4']
    }], 1) of
        {[MonitorRef], _} -> MonitorRef;
        _ -> undefined
    end.

-spec get_groups_tuples_for_node(Node :: node()) -> [syn_groups_tuple()].
get_groups_tuples_for_node(Node) ->
    ets:select(syn_groups_by_name, [{
        {{'$1', '$2'}, '$3', '_', Node},
        [],
        [{{'$1', '$2', '$3'}}]
    }]).

-spec handle_process_down(GroupName :: any(), Pid :: pid(), Meta :: any(), Reason :: any(), #state{}) -> ok.
handle_process_down(GroupName, Pid, Meta, Reason, #state{
    custom_event_handler = CustomEventHandler
}) ->
    case GroupName of
        undefined ->
            error_logger:warning_msg(
                "Syn(~p): Received a DOWN message from an unjoined group process ~p with reason: ~p~n",
                [node(), Pid, Reason]
            );
        _ ->
            syn_event_handler:do_on_group_process_exit(GroupName, Pid, Meta, Reason, CustomEventHandler)
    end.

-spec groups_automerge(RemoteNode :: node()) -> ok.
groups_automerge(RemoteNode) ->
    global:trans({{?MODULE, auto_merge_groups}, self()},
        fun() ->
            error_logger:info_msg("Syn(~p): GROUPS AUTOMERGE ----> Initiating for remote node ~p~n", [node(), RemoteNode]),
            %% get group tuples from remote node
            case rpc:call(RemoteNode, ?MODULE, sync_get_local_groups_tuples, [node()]) of
                {badrpc, _} ->
                    error_logger:info_msg("Syn(~p): GROUPS AUTOMERGE <---- Syn not ready on remote node ~p, postponing~n", [node(), RemoteNode]);

                GroupTuples ->
                    error_logger:info_msg(
                        "Syn(~p): Received ~p group tuple(s) from remote node ~p~n",
                        [node(), length(GroupTuples), RemoteNode]
                    ),
                    %% ensure that groups doesn't have any joining node's entries
                    raw_purge_group_entries_for_node(RemoteNode),
                    %% add
                    lists:foreach(fun({GroupName, RemotePid, RemoteMeta}) ->
                        case rpc:call(node(RemotePid), erlang, is_process_alive, [RemotePid]) of
                            true ->
                                add_to_local_table(GroupName, RemotePid, RemoteMeta, undefined);
                            _ ->
                                ok = rpc:call(RemoteNode, syn_groups, remove_from_local_table, [GroupName, RemotePid])
                        end
                    end, GroupTuples),
                    %% exit
                    error_logger:info_msg("Syn(~p): GROUPS AUTOMERGE <---- Done for remote node ~p~n", [node(), RemoteNode])
            end
        end
    ).

-spec do_sync_from_full_cluster() -> ok.
do_sync_from_full_cluster() ->
    lists:foreach(fun(RemoteNode) ->
        groups_automerge(RemoteNode)
    end, nodes()).

-spec raw_purge_group_entries_for_node(Node :: atom()) -> ok.
raw_purge_group_entries_for_node(Node) ->
    %% NB: no demonitoring is done, this is why it's raw
    ets:match_delete(syn_groups_by_name, {{'_', '_'}, '_', '_', Node}),
    ets:match_delete(syn_groups_by_pid, {{'_', '_'}, '_', '_', Node}),
    ok.

-spec multi_call_and_receive(
    CollectorPid :: pid(),
    Pid :: pid(),
    Message :: any(),
    Timeout :: non_neg_integer()
) -> any().

multi_call_and_receive(CollectorPid, Pid, Message, Timeout) ->
    MonitorRef = monitor(process, Pid),
    Pid ! {syn_multi_call, self(), Message},

    receive
        {syn_multi_call_reply, Pid, Reply} ->
            CollectorPid ! {reply, Pid, Reply};
        {'DOWN', MonitorRef, _, _, _} ->
            CollectorPid ! {bad_pid, Pid}
    after Timeout ->
        CollectorPid ! {bad_pid, Pid}
    end.

-spec collect_replies(MemberPids :: [pid()]) -> {[{pid(), Reply :: any()}], [BadPid :: pid()]}.
collect_replies(MemberPids) ->
    collect_replies(MemberPids, [], []).

-spec collect_replies(MemberPids :: [pid()], [{pid(), Reply :: any()}], [pid()]) ->
    {[{pid(), Reply :: any()}], [BadPid :: pid()]}.
collect_replies([], Replies, BadPids) -> {Replies, BadPids};
collect_replies(MemberPids, Replies, BadPids) ->
    receive
        {reply, Pid, Reply} ->
            MemberPids1 = lists:delete(Pid, MemberPids),
            collect_replies(MemberPids1, [{Pid, Reply} | Replies], BadPids);
        {bad_pid, Pid} ->
            MemberPids1 = lists:delete(Pid, MemberPids),
            collect_replies(MemberPids1, Replies, [Pid | BadPids])
    end.

-spec rebuild_monitors() -> ok.
rebuild_monitors() ->
    GroupTuples = get_groups_tuples_for_node(node()),
    %% ensure that groups doesn't have any joining node's entries
    raw_purge_group_entries_for_node(node()),
    %% add
    lists:foreach(fun({GroupName, Pid, Meta}) ->
        case erlang:is_process_alive(Pid) of
            true ->
                join_on_node(GroupName, Pid, Meta);
            _ ->
                remove_from_local_table(GroupName, Pid)
        end
    end, GroupTuples).

-spec set_timer_for_anti_entropy(#state{}) -> ok.
set_timer_for_anti_entropy(#state{anti_entropy_interval_ms = undefined}) -> ok;
set_timer_for_anti_entropy(#state{
    anti_entropy_interval_ms = AntiEntropyIntervalMs,
    anti_entropy_interval_max_deviation_ms = AntiEntropyIntervalMaxDeviationMs
}) ->
    IntervalMs = round(AntiEntropyIntervalMs + rand:uniform() * AntiEntropyIntervalMaxDeviationMs),
    {ok, _} = timer:send_after(IntervalMs, self(), sync_anti_entropy),
    ok.

-spec multicast_loop() -> terminated.
multicast_loop() ->
    receive
        {multicast_join, GroupName, Pid, Meta} ->
            lists:foreach(fun(RemoteNode) ->
                sync_join(RemoteNode, GroupName, Pid, Meta)
            end, nodes()),
            multicast_loop();

        {multicast_leave, GroupName, Pid} ->
            lists:foreach(fun(RemoteNode) ->
                sync_leave(RemoteNode, GroupName, Pid)
            end, nodes()),
            multicast_loop();

        terminate ->
            terminated
    end.
