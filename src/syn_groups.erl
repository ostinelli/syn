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
-export([member/2]).
-export([get_local_members/1, get_local_members/2]).
-export([local_member/2]).
-export([publish/2]).
-export([publish_to_local/2]).
-export([multi_call/2, multi_call/3, multi_call_reply/2]).

%% sync API
-export([sync_get_local_group_tuples/1]).
-export([add_to_local_table/4]).
-export([remove_from_local_table/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% internal
-export([multi_call_and_receive/4]).

%% records
-record(state, {
    custom_event_handler = undefined :: module()
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
    case find_process_entry_by_name_and_pid(GroupName, Pid) of
        undefined ->
            {error, not_in_group};
        _ ->
            Node = node(Pid),
            gen_server:call({?MODULE, Node}, {leave_on_node, GroupName, Pid})
    end.

-spec get_members(Name :: any()) -> [pid()].
get_members(GroupName) ->
    Entries = mnesia:dirty_read(syn_groups_table, GroupName),
    Pids = [Entry#syn_groups_table.pid || Entry <- Entries],
    lists:sort(Pids).

-spec get_members(GroupName :: any(), with_meta) -> [{pid(), Meta :: any()}].
get_members(GroupName, with_meta) ->
    Entries = mnesia:dirty_read(syn_groups_table, GroupName),
    Pids = [{Entry#syn_groups_table.pid, Entry#syn_groups_table.meta} || Entry <- Entries],
    lists:sort(Pids).

-spec member(Pid :: pid(), GroupName :: any()) -> boolean().
member(Pid, GroupName) ->
    case find_process_entry_by_name_and_pid(GroupName, Pid) of
        undefined -> false;
        _ -> true
    end.

-spec get_local_members(Name :: any()) -> [pid()].
get_local_members(GroupName) ->
    %% build name guard
    NameGuard = case is_tuple(GroupName) of
        true -> {'==', '$1', {GroupName}};
        _ -> {'=:=', '$1', GroupName}
    end,
    %% build match specs
    MatchHead = #syn_groups_table{name = '$1', node = '$2', pid = '$3', _ = '_'},
    Guards = [NameGuard, {'=:=', '$2', node()}],
    Result = '$3',
    %% select
    Pids = mnesia:dirty_select(syn_groups_table, [{MatchHead, Guards, [Result]}]),
    lists:sort(Pids).

-spec get_local_members(GroupName :: any(), with_meta) -> [{pid(), Meta :: any()}].
get_local_members(GroupName, with_meta) ->
    %% build name guard
    NameGuard = case is_tuple(GroupName) of
        true -> {'==', '$1', {GroupName}};
        _ -> {'=:=', '$1', GroupName}
    end,
    %% build match specs
    MatchHead = #syn_groups_table{name = '$1', node = '$2', pid = '$3', meta = '$4', _ = '_'},
    Guards = [NameGuard, {'=:=', '$2', node()}],
    Result = {{'$3', '$4'}},
    %% select
    PidsWithMeta = mnesia:dirty_select(syn_groups_table, [{MatchHead, Guards, [Result]}]),
    lists:keysort(1, PidsWithMeta).

-spec local_member(Pid :: pid(), GroupName :: any()) -> boolean().
local_member(Pid, GroupName) ->
    case find_process_entry_by_name_and_pid(GroupName, Pid) of
        undefined -> false;
        Entry when Entry#syn_groups_table.node =:= node() -> true;
        _ -> false
    end.

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

-spec sync_get_local_group_tuples(FromNode :: node()) -> list(syn_group_tuple()).
sync_get_local_group_tuples(FromNode) ->
    error_logger:info_msg("Syn(~p): Received request of local group tuples from remote node: ~p", [node(), FromNode]),
    get_group_tuples_for_node(node()).

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
    %% rebuild
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

handle_call({join_on_node, GroupName, Pid, Meta}, _From, State) ->
    %% check if pid is alive
    case is_process_alive(Pid) of
        true ->
            join_on_node(GroupName, Pid, Meta),
            %% multicast
            multicast_join(GroupName, Pid, Meta),
            %% return
            {reply, ok, State};
        _ ->
            {reply, {error, not_alive}, State}
    end;

handle_call({leave_on_node, GroupName, Pid}, _From, State) ->
    case leave_on_node(GroupName, Pid) of
        ok ->
            %% multicast
            multicast_leave(GroupName, Pid),
            %% return
            {reply, ok, State};
        {error, Reason} ->
            %% return
            {reply, {error, Reason}, State}
    end;

handle_call(Request, From, State) ->
    error_logger:warning_msg("Syn(~p): Received from ~p an unknown call message: ~p", [node(), Request, From]),
    {reply, undefined, State}.

%% ----------------------------------------------------------------------------------------------------------
%% Cast messages
%% ----------------------------------------------------------------------------------------------------------
-spec handle_cast(Msg :: any(), #state{}) ->
    {noreply, #state{}} |
    {noreply, #state{}, Timeout :: non_neg_integer()} |
    {stop, Reason :: any(), #state{}}.

handle_cast(Msg, State) ->
    error_logger:warning_msg("Syn(~p): Received an unknown cast message: ~p", [node(), Msg]),
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
                GroupName = Entry#syn_groups_table.name,
                Meta = Entry#syn_groups_table.meta,
                %% handle
                handle_process_down(GroupName, Pid, Meta, Reason, State),
                %% remove from table
                remove_from_local_table(Entry),
                %% multicast
                multicast_leave(GroupName, Pid)
            end, Entries)
    end,
    %% return
    {noreply, State};

handle_info({nodeup, RemoteNode}, State) ->
    error_logger:info_msg("Syn(~p): Node ~p has joined the cluster", [node(), RemoteNode]),
    global:trans({{?MODULE, auto_merge_groups}, self()},
        fun() ->
            error_logger:warning_msg("Syn(~p): GROUPS AUTOMERGE ----> Initiating for remote node ~p", [node(), RemoteNode]),
            %% get group tuples from remote node
            GroupTuples = rpc:call(RemoteNode, ?MODULE, sync_get_local_group_tuples, [node()]),
            error_logger:warning_msg(
                "Syn(~p): Received ~p group entrie(s) from remote node ~p",
                [node(), length(GroupTuples), RemoteNode]
            ),
            write_group_tuples_for_node(GroupTuples, RemoteNode),
            %% exit
            error_logger:warning_msg("Syn(~p): GROUPS AUTOMERGE <---- Done for remote node ~p", [node(), RemoteNode])
        end
    ),
    %% resume
    {noreply, State};

handle_info({nodedown, RemoteNode}, State) ->
    error_logger:warning_msg("Syn(~p): Node ~p has left the cluster, removing group entries on local", [node(), RemoteNode]),
    raw_purge_group_entries_for_node(RemoteNode),
    {noreply, State};

handle_info(Info, State) ->
    error_logger:warning_msg("Syn(~p): Received an unknown info message: ~p", [node(), Info]),
    {noreply, State}.

%% ----------------------------------------------------------------------------------------------------------
%% Terminate
%% ----------------------------------------------------------------------------------------------------------
-spec terminate(Reason :: any(), #state{}) -> terminated.
terminate(Reason, _State) ->
    error_logger:info_msg("Syn(~p): Terminating with reason: ~p", [node(), Reason]),
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
-spec multicast_join(GroupName :: any(), Pid :: pid(), Meta :: any()) -> pid().
multicast_join(GroupName, Pid, Meta) ->
    spawn_link(fun() ->
        rpc:eval_everywhere(nodes(), ?MODULE, add_to_local_table, [GroupName, Pid, Meta, undefined])
    end).

-spec multicast_leave(GroupName :: any(), Pid :: pid()) -> pid().
multicast_leave(GroupName, Pid) ->
    spawn_link(fun() ->
        rpc:eval_everywhere(nodes(), ?MODULE, remove_from_local_table, [GroupName, Pid])
    end).

-spec join_on_node(GroupName :: any(), Pid :: pid(), Meta :: any()) -> ok.
join_on_node(GroupName, Pid, Meta) ->
    MonitorRef = case find_processes_entry_by_pid(Pid) of
        [] ->
            %% process is not monitored yet, add
            erlang:monitor(process, Pid);
        [Entry | _] ->
            Entry#syn_groups_table.monitor_ref
    end,
    %% add to table
    add_to_local_table(GroupName, Pid, Meta, MonitorRef).

-spec leave_on_node(GroupName :: any(), Pid :: pid()) -> ok | {error, Reason :: any()}.
leave_on_node(GroupName, Pid) ->
    case find_process_entry_by_name_and_pid(GroupName, Pid) of
        undefined ->
            {error, not_in_group};

        Entry when Entry#syn_groups_table.monitor_ref =/= undefined ->
            %% is this the last group process is in?
            case find_processes_entry_by_pid(Pid) of
                [Entry] ->
                    %% demonitor
                    erlang:demonitor(Entry#syn_groups_table.monitor_ref);
                _ ->
                    ok
            end,
            %% remove from table
            remove_from_local_table(Entry)
    end.

-spec add_to_local_table(GroupName :: any(), Pid :: pid(), Meta :: any(), MonitorRef :: undefined | reference()) -> ok.
add_to_local_table(GroupName, Pid, Meta, MonitorRef) ->
    %% clean if any
    remove_from_local_table(GroupName, Pid),
    %% write
    mnesia:dirty_write(#syn_groups_table{
        name = GroupName,
        pid = Pid,
        node = node(Pid),
        meta = Meta,
        monitor_ref = MonitorRef
    }).

-spec remove_from_local_table(GroupName :: any(), Pid :: pid()) -> ok | {error, Reason :: any()}.
remove_from_local_table(GroupName, Pid) ->
    case find_process_entry_by_name_and_pid(GroupName, Pid) of
        undefined ->
            {error, not_in_group};
        Entry ->
            %% remove from table
            remove_from_local_table(Entry)
    end.

-spec remove_from_local_table(Entry :: #syn_groups_table{}) -> ok.
remove_from_local_table(Entry) ->
    mnesia:dirty_delete_object(syn_groups_table, Entry).

-spec find_processes_entry_by_pid(Pid :: pid()) -> Entries :: list(#syn_groups_table{}).
find_processes_entry_by_pid(Pid) when is_pid(Pid) ->
    mnesia:dirty_index_read(syn_groups_table, Pid, #syn_groups_table.pid).

-spec find_process_entry_by_name_and_pid(GroupName :: any(), Pid :: pid()) -> Entry :: #syn_groups_table{} | undefined.
find_process_entry_by_name_and_pid(GroupName, Pid) ->
    %% build match specs
    MatchHead = #syn_groups_table{name = GroupName, pid = Pid, _ = '_'},
    Guards = [],
    Result = '$_',
    %% select
    case mnesia:dirty_select(syn_groups_table, [{MatchHead, Guards, [Result]}]) of
        [Entry] -> Entry;
        [] -> undefined
    end.

-spec get_group_tuples_for_node(Node :: node()) -> [syn_group_tuple()].
get_group_tuples_for_node(Node) ->
    %% build match specs
    MatchHead = #syn_groups_table{name = '$1', pid = '$2', node = '$3', meta = '$4', _ = '_'},
    Guard = {'=:=', '$3', Node},
    GroupTupleFormat = {{'$1', '$2', '$4'}},
    %% select
    mnesia:dirty_select(syn_groups_table, [{MatchHead, [Guard], [GroupTupleFormat]}]).

-spec handle_process_down(GroupName :: any(), Pid :: pid(), Meta :: any(), Reason :: any(), #state{}) -> ok.
handle_process_down(GroupName, Pid, Meta, Reason, #state{
    custom_event_handler = CustomEventHandler
}) ->
    case GroupName of
        undefined ->
            error_logger:warning_msg(
                "Syn(~p): Received a DOWN message from an unjoined group process ~p with reason: ~p",
                [node(), Pid, Reason]
            );
        _ ->
            syn_event_handler:do_on_group_process_exit(GroupName, Pid, Meta, Reason, CustomEventHandler)
    end.

-spec write_group_tuples_for_node(GroupTuples :: [syn_registry_tuple()], RemoteNode :: node()) -> ok.
write_group_tuples_for_node(GroupTuples, RemoteNode) ->
    %% ensure that groups doesn't have any joining node's entries
    raw_purge_group_entries_for_node(RemoteNode),
    %% add
    lists:foreach(fun({GroupName, RemotePid, RemoteMeta}) ->
        case rpc:call(node(RemotePid), erlang, is_process_alive, [RemotePid]) of
            true ->
                add_to_local_table(GroupName, RemotePid, RemoteMeta, undefined);
            _ ->
                ok = rpc:call(RemoteNode, syn_registry, remove_from_local_table, [GroupName, RemotePid])
        end
    end, GroupTuples).

-spec raw_purge_group_entries_for_node(Node :: atom()) -> ok.
raw_purge_group_entries_for_node(Node) ->
    %% NB: no demonitoring is done, this is why it's raw
    %% build match specs
    Pattern = #syn_groups_table{node = Node, _ = '_'},
    ObjectsToDelete = mnesia:dirty_match_object(syn_groups_table, Pattern),
    %% delete
    DelF = fun(Record) -> mnesia:dirty_delete_object(syn_groups_table, Record) end,
    lists:foreach(DelF, ObjectsToDelete).

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
    GroupTuples = get_group_tuples_for_node(node()),
    %% ensure that groups doesn't have any joining node's entries
    raw_purge_group_entries_for_node(node()),
    %% add
    lists:foreach(fun({GroupName, Pid, Meta}) ->
        case erlang:is_process_alive(Pid) of
            true ->
                join_on_node(GroupName, Pid, Meta);
            _ ->
                multicast_leave(GroupName, Pid)
        end
    end, GroupTuples).
