%% ==========================================================================================================
%% Syn - A global Process Registry and Process Group manager.
%%
%% The MIT License (MIT)
%%
%% Copyright (c) 2015-2022 Roberto Ostinelli <roberto@ostinelli.net> and Neato Robotics, Inc.
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
%% @private
-module(syn_pg).
-behaviour(syn_gen_scope).

%% API
-export([start_link/1]).
-export([subcluster_nodes/1]).
-export([join/4]).
-export([leave/3]).
-export([members/2]).
-export([member/3]).
-export([member_count/2, member_count/3]).
-export([is_member/3]).
-export([update_member/4]).
-export([local_members/2]).
-export([is_local_member/3]).
-export([count/1, count/2]).
-export([group_names/1, group_names/2]).
-export([publish/3]).
-export([local_publish/3]).
-export([multi_call/4, multi_call_reply/2]).

%% syn_gen_scope callbacks
-export([
    init/1,
    handle_call/3,
    handle_info/2,
    save_remote_data/2,
    get_local_data/1,
    purge_local_data_for_node/2
]).

%% internal
-export([multi_call_and_receive/5]).

%% macros
-define(MODULE_LOG_NAME, pg).

%% tests
-ifdef(TEST).
-export([add_to_local_table/7]).
-endif.

%% includes
-include("syn.hrl").

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

-spec members(Scope :: atom(), GroupName :: term()) -> [{Pid :: pid(), Meta :: term()}].
members(Scope, GroupName) ->
    do_get_members(Scope, GroupName, undefined, undefined).

-spec member(Scope :: atom(), GroupName :: term(), pid()) -> {pid(), Meta :: term()} | undefined.
member(Scope, GroupName, Pid) ->
    case do_get_members(Scope, GroupName, Pid, undefined) of
        [] -> undefined;
        [Member] -> Member
    end.

-spec member_count(Scope :: atom(), GroupName :: term()) -> non_neg_integer().
member_count(Scope, GroupName) ->
    do_member_count(Scope, GroupName, '_').

-spec member_count(Scope :: atom(), GroupName :: term(), Node :: node()) -> non_neg_integer().
member_count(Scope, GroupName, Node) ->
    do_member_count(Scope, GroupName, Node).

do_member_count(Scope, GroupName, NodeParam) ->
    case syn_backbone:get_table_name(syn_pg_by_name, Scope) of
        undefined ->
            error({invalid_scope, Scope});

        TableByName ->
            ets:select_count(TableByName, [{
                {{GroupName, '$1'}, '_', '_', '_', NodeParam},
                [],
                [true]
            }])
    end.

-spec is_member(Scope :: atom(), GroupName :: term(), pid()) -> boolean().
is_member(Scope, GroupName, Pid) ->
    case syn_backbone:get_table_name(syn_pg_by_name, Scope) of
        undefined ->
            error({invalid_scope, Scope});

        TableByName ->
            case find_pg_entry_by_name_and_pid(GroupName, Pid, TableByName) of
                undefined -> false;
                _ -> true
            end
    end.

-spec local_members(Scope :: atom(), GroupName :: term()) -> [{pid(), Meta :: term()}].
local_members(Scope, GroupName) ->
    do_get_members(Scope, GroupName, undefined, node()).

-spec do_get_members(Scope :: atom(), GroupName :: term(), pid() | undefined, Node :: node() | undefined) ->
    [{pid(), Meta :: term()}].
do_get_members(Scope, GroupName, Pid, Node) ->
    PidParam = case Pid of
        undefined -> '$2';
        _ -> Pid
    end,
    NodeParam = case Node of
        undefined -> '_';
        _ -> Node
    end,
    case syn_backbone:get_table_name(syn_pg_by_name, Scope) of
        undefined ->
            error({invalid_scope, Scope});

        TableByName ->
            ets:select(TableByName, [{
                {{GroupName, PidParam}, '$3', '_', '_', NodeParam},
                [],
                [{{PidParam, '$3'}}]
            }])
    end.

-spec is_local_member(Scope :: atom(), GroupName :: term(), pid()) -> boolean().
is_local_member(Scope, GroupName, Pid) ->
    case syn_backbone:get_table_name(syn_pg_by_name, Scope) of
        undefined ->
            error({invalid_scope, Scope});

        TableByName ->
            case find_pg_entry_by_name_and_pid(GroupName, Pid, TableByName) of
                {{_, _}, _, _, _, Node} when Node =:= node() -> true;
                _ -> false
            end
    end.

-spec join(Scope :: atom(), GroupName :: term(), Pid :: pid(), Meta :: term()) -> ok | {error, Reason :: term()}.
join(Scope, GroupName, Pid, Meta) ->
    case join_or_update(Scope, GroupName, Pid, Meta) of
        {ok, _} -> ok;
        {error, Reason} -> {error, Reason}
    end.

-spec update_member(Scope :: atom(), GroupName :: term(), Pid :: pid(), Fun :: function()) ->
    {ok, {Pid :: pid(), Meta :: term()}} | {error, Reason :: term()}.
update_member(Scope, GroupName, Pid, Fun) when is_function(Fun) ->
    join_or_update(Scope, GroupName, Pid, Fun).

-spec join_or_update(Scope :: atom(), GroupName :: term(), Pid :: pid(), MetaOrFun :: term() | function()) ->
    {ok, {Pid :: pid(), Meta :: term()}} | {error, Reason :: term()}.
join_or_update(Scope, GroupName, Pid, MetaOrFun) ->
    case syn_backbone:is_strict_mode() of
        true when Pid =/= self() ->
            {error, not_self};

        _ ->
            Node = node(Pid),
            case syn_gen_scope:call(?MODULE, Node, Scope, {'3.0', join_or_update_on_node, node(), GroupName, Pid, MetaOrFun}) of
                {ok, {CallbackMethod, PreviousMeta, Meta, Time, TableByName, TableByPid}} when Node =/= node() ->
                    %% update table on caller node immediately so that subsequent calls have an updated pg
                    add_to_local_table(GroupName, Pid, Meta, Time, undefined, TableByName, TableByPid),
                    %% callback
                    syn_event_handler:call_event_handler(CallbackMethod, [Scope, GroupName, Pid, Meta, normal]),
                    syn_event_handler:call_event_handler(CallbackMethod, [Scope, GroupName, Pid, PreviousMeta, Meta, normal]),
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
            end
    end.

-spec leave(Scope :: atom(), GroupName :: term(), pid()) -> ok | {error, Reason :: term()}.
leave(Scope, GroupName, Pid) ->
    case syn_backbone:get_table_name(syn_pg_by_name, Scope) of
        undefined ->
            error({invalid_scope, Scope});

        TableByName ->
            Node = node(Pid),
            case syn_gen_scope:call(?MODULE, Node, Scope, {'3.0', leave_on_node, node(), GroupName, Pid}) of
                {ok, {Meta, TableByPid}} when Node =/= node() ->
                    %% remove table on caller node immediately so that subsequent calls have an updated registry
                    remove_from_local_table(GroupName, Pid, TableByName, TableByPid),
                    %% callback
                    syn_event_handler:call_event_handler(on_process_left, [Scope, GroupName, Pid, Meta, normal]),
                    %% return
                    ok;

                {ok, _} ->
                    ok;

                {error, Reason} ->
                    {error, Reason}
            end
    end.

-spec count(Scope :: atom()) -> non_neg_integer().
count(Scope) ->
    Set = group_names_ordset(Scope, '_'),
    ordsets:size(Set).

-spec count(Scope :: atom(), Node :: node()) -> non_neg_integer().
count(Scope, Node) ->
    Set = group_names_ordset(Scope, Node),
    ordsets:size(Set).

-spec group_names(Scope :: atom()) -> [GroupName :: term()].
group_names(Scope) ->
    Set = group_names_ordset(Scope, '_'),
    ordsets:to_list(Set).

-spec group_names(Scope :: atom(), Node :: node()) -> [GroupName :: term()].
group_names(Scope, Node) ->
    Set = group_names_ordset(Scope, Node),
    ordsets:to_list(Set).

-spec group_names_ordset(Scope :: atom(), Node :: node()) -> ordsets:ordset(GroupName :: term()).
group_names_ordset(Scope, NodeParam) ->
    case syn_backbone:get_table_name(syn_pg_by_name, Scope) of
        undefined ->
            error({invalid_scope, Scope});

        TableByName ->
            DuplicatedGroups = ets:select(TableByName, [{
                {{'$1', '_'}, '_', '_', '_', NodeParam},
                [],
                ['$1']
            }]),
            ordsets:from_list(DuplicatedGroups)
    end.

-spec publish(Scope :: atom(), GroupName :: term(), Message :: term()) -> {ok, RecipientCount :: non_neg_integer()}.
publish(Scope, GroupName, Message) ->
    Members = members(Scope, GroupName),
    do_publish(Members, Message).

-spec local_publish(Scope :: atom(), GroupName :: term(), Message :: term()) -> {ok, RecipientCount :: non_neg_integer()}.
local_publish(Scope, GroupName, Message) ->
    Members = local_members(Scope, GroupName),
    do_publish(Members, Message).

-spec do_publish(Members :: [{Pid :: pid(), Meta :: term()}], Message :: term()) ->
    {ok, RecipientCount :: non_neg_integer()}.
do_publish(Members, Message) ->
    lists:foreach(fun({Pid, _Meta}) ->
        Pid ! Message
    end, Members),
    {ok, length(Members)}.

-spec multi_call(Scope :: atom(), GroupName :: term(), Message :: term(), Timeout :: non_neg_integer()) ->
    {
        Replies :: [{{pid(), Meta :: term()}, Reply :: term()}],
        BadReplies :: [{pid(), Meta :: term()}]
    }.
multi_call(Scope, GroupName, Message, Timeout) ->
    Self = self(),
    Members = members(Scope, GroupName),
    lists:foreach(fun({Pid, Meta}) ->
        spawn_link(?MODULE, multi_call_and_receive, [Self, Pid, Meta, Message, Timeout])
    end, Members),
    collect_replies(orddict:from_list(Members)).

-spec multi_call_reply({CallerPid :: term(), reference()}, Reply :: term()) -> any().
multi_call_reply({CallerPid, Ref}, Reply) ->
    CallerPid ! {syn_multi_call_reply, Ref, Reply}.

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
    purge_pg_for_remote_nodes(Scope, TableByName, TableByPid),
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
handle_call({'3.0', join_or_update_on_node, RequesterNode, GroupName, Pid, MetaOrFun}, _From, #state{
    table_by_name = TableByName,
    table_by_pid = TableByPid
} = State) ->
    case is_process_alive(Pid) of
        true ->
            case find_pg_entry_by_name_and_pid(GroupName, Pid, TableByName) of
                undefined when is_function(MetaOrFun) ->
                    {reply, {error, undefined}, State};

                undefined ->
                    %% add
                    MRef = case find_monitor_for_pid(Pid, TableByPid) of
                        undefined -> erlang:monitor(process, Pid);  %% process is not monitored yet, create
                        MRef0 -> MRef0
                    end,
                    do_join_on_node(GroupName, Pid, undefined, MetaOrFun, MRef, normal, RequesterNode, on_process_joined, State);

                {{_, _}, TableMeta, _, MRef, _} when is_function(MetaOrFun) ->
                    %% update with fun
                    try MetaOrFun(TableMeta) of
                        Meta when Meta =:= TableMeta ->
                            {reply, {noop, TableMeta}, State};

                        Meta ->
                            do_join_on_node(GroupName, Pid, TableMeta, Meta, MRef, normal, RequesterNode, on_group_process_updated, State)

                    catch Class:Reason:Stacktrace ->
                        error_logger:error_msg(
                            "SYN[~s] Error ~p:~p in pg update function: ~p",
                            [node(), Class, Reason, Stacktrace]
                        ),
                        {reply, {raise, Class, Reason, Stacktrace}, State}
                    end;

                {{_, _}, MetaOrFun, _, _, _} ->
                    %% re-joined with same meta
                    {reply, {noop, MetaOrFun}, State};

                {{_, _}, TableMeta, _, MRef, _} ->
                    %% re-joined with different meta
                    do_join_on_node(GroupName, Pid, TableMeta, MetaOrFun, MRef, normal, RequesterNode, on_group_process_updated, State)
            end;

        false ->
            {reply, {error, not_alive}, State}
    end;

handle_call({'3.0', leave_on_node, RequesterNode, GroupName, Pid}, _From, #state{
    scope = Scope,
    table_by_name = TableByName,
    table_by_pid = TableByPid
} = State) ->
    case find_pg_entry_by_name_and_pid(GroupName, Pid, TableByName) of
        undefined ->
            {reply, {error, not_in_group}, State};

        {{_, _}, Meta, _, _, _} ->
            %% is this the last group process is in?
            maybe_demonitor(Pid, TableByPid),
            %% remove from table
            remove_from_local_table(GroupName, Pid, TableByName, TableByPid),
            %% callback
            syn_event_handler:call_event_handler(on_process_left, [Scope, GroupName, Pid, Meta, normal]),
            %% broadcast
            syn_gen_scope:broadcast({'3.0', sync_leave, GroupName, Pid, Meta, normal}, [RequesterNode], State),
            %% return
            {reply, {ok, {Meta, TableByPid}}, State}
    end;

handle_call(Request, From, #state{scope = Scope} = State) ->
    error_logger:warning_msg("SYN[~s|~s<~s>] Received from ~p an unknown call message: ~p",
        [node(), ?MODULE_LOG_NAME, Scope, From, Request]
    ),
    {reply, undefined, State}.

%% ----------------------------------------------------------------------------------------------------------
%% Info messages
%% ----------------------------------------------------------------------------------------------------------
-spec handle_info(Info :: timeout | term(), #state{}) ->
    {noreply, #state{}} |
    {noreply, #state{}, timeout() | hibernate | {continue, term()}} |
    {stop, Reason :: term(), #state{}}.
handle_info({'3.0', sync_join, GroupName, Pid, Meta, Time, Reason}, #state{nodes_map = NodesMap} = State) ->
    case maps:is_key(node(Pid), NodesMap) of
        true ->
            handle_pg_sync(GroupName, Pid, Meta, Time, Reason, State);

        false ->
            %% ignore, race condition
            ok
    end,
    {noreply, State};

handle_info({'3.0', sync_leave, GroupName, Pid, Meta, Reason}, #state{
    scope = Scope,
    table_by_name = TableByName,
    table_by_pid = TableByPid
} = State) ->
    case find_pg_entry_by_name_and_pid(GroupName, Pid, TableByName) of
        undefined ->
            %% not in table, nothing to do
            ok;

        _ ->
            %% remove from table
            remove_from_local_table(GroupName, Pid, TableByName, TableByPid),
            %% callback
            syn_event_handler:call_event_handler(on_process_left, [Scope, GroupName, Pid, Meta, Reason])
    end,
    %% return
    {noreply, State};

handle_info({'DOWN', _MRef, process, Pid, Reason}, #state{
    scope = Scope,
    table_by_name = TableByName,
    table_by_pid = TableByPid
} = State) ->
    case find_pg_entries_by_pid(Pid, TableByPid) of
        [] ->
            error_logger:warning_msg(
                "SYN[~s|~s<~s>] Received a DOWN message from an unknown process ~p with reason: ~p",
                [node(), ?MODULE_LOG_NAME, Scope, Pid, Reason]
            );

        Entries ->
            lists:foreach(fun({{_Pid, GroupName}, Meta, _, _, _}) ->
                %% remove from table
                remove_from_local_table(GroupName, Pid, TableByName, TableByPid),
                %% callback
                syn_event_handler:call_event_handler(on_process_left, [Scope, GroupName, Pid, Meta, Reason]),
                %% broadcast
                syn_gen_scope:broadcast({'3.0', sync_leave, GroupName, Pid, Meta, Reason}, State)
            end, Entries)
    end,
    %% return
    {noreply, State};

handle_info(Info, #state{scope = Scope} = State) ->
    error_logger:warning_msg("SYN[~s|~s<~s>] Received an unknown info message: ~p", [node(), ?MODULE_LOG_NAME, Scope, Info]),
    {noreply, State}.

%% ----------------------------------------------------------------------------------------------------------
%% Data callbacks
%% ----------------------------------------------------------------------------------------------------------
-spec get_local_data(State :: term()) -> {ok, Data :: term()} | undefined.
get_local_data(#state{table_by_name = TableByName}) ->
    {ok, get_pg_tuples_for_node(node(), TableByName)}.

-spec save_remote_data(RemoteData :: term(), State :: term()) -> any().
save_remote_data(PgTuplesOfRemoteNode, #state{scope = Scope} = State) ->
    %% insert tuples
    lists:foreach(fun({GroupName, Pid, Meta, Time}) ->
        handle_pg_sync(GroupName, Pid, Meta, Time, {syn_remote_scope_node_up, Scope, node(Pid)}, State)
    end, PgTuplesOfRemoteNode).

-spec purge_local_data_for_node(Node :: node(), State :: term()) -> any().
purge_local_data_for_node(Node, #state{
    scope = Scope,
    table_by_name = TableByName,
    table_by_pid = TableByPid
}) ->
    purge_pg_for_remote_node(Scope, Node, TableByName, TableByPid).

%% ===================================================================
%% Internal
%% ===================================================================
-spec rebuild_monitors(Scope :: atom(), TableByName :: atom(), TableByPid :: atom()) -> ok.
rebuild_monitors(Scope, TableByName, TableByPid) ->
    PgTuples = get_pg_tuples_for_node(node(), TableByName),
    do_rebuild_monitors(PgTuples, #{}, Scope, TableByName, TableByPid).

-spec do_rebuild_monitors(
    [syn_pg_tuple()],
    #{pid() => reference()},
    Scope :: atom(),
    TableByName :: atom(),
    TableByPid :: atom()
) -> ok.
do_rebuild_monitors([], _, _, _, _) -> ok;
do_rebuild_monitors([{GroupName, Pid, Meta, Time} | T], NewMRefs, Scope, TableByName, TableByPid) ->
    remove_from_local_table(GroupName, Pid, TableByName, TableByPid),
    case is_process_alive(Pid) of
        true ->
            case maps:find(Pid, NewMRefs) of
                error ->
                    MRef = erlang:monitor(process, Pid),
                    add_to_local_table(GroupName, Pid, Meta, Time, MRef, TableByName, TableByPid),
                    do_rebuild_monitors(T, maps:put(Pid, MRef, NewMRefs), Scope, TableByName, TableByPid);

                {ok, MRef} ->
                    add_to_local_table(GroupName, Pid, Meta, Time, MRef, TableByName, TableByPid),
                    do_rebuild_monitors(T, NewMRefs, Scope, TableByName, TableByPid)
            end;

        _ ->
            %% process died meanwhile, callback
            %% the remote callbacks will have been called when the scope process crash triggered them
            syn_event_handler:call_event_handler(on_process_left, [Scope, GroupName, Pid, Meta, undefined]),
            %% loop
            do_rebuild_monitors(T, NewMRefs, Scope, TableByName, TableByPid)
    end.

-spec do_join_on_node(
    GroupName :: term(),
    Pid :: pid(),
    PreviousMeta :: term(),
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
            PreviousMeta :: term(),
            Meta :: term(),
            Time :: non_neg_integer(),
            TableByName :: atom(),
            TableByPid :: atom()
        }},
        #state{}
    }.
do_join_on_node(GroupName, Pid, PreviousMeta, Meta, MRef, Reason, RequesterNode, CallbackMethod, #state{
    scope = Scope,
    table_by_name = TableByName,
    table_by_pid = TableByPid
} = State) ->
    Time = erlang:system_time(),
    %% add to local table
    add_to_local_table(GroupName, Pid, Meta, Time, MRef, TableByName, TableByPid),
    %% callback
    syn_event_handler:call_event_handler(CallbackMethod, [Scope, GroupName, Pid, Meta, Reason]),
    syn_event_handler:call_event_handler(CallbackMethod, [Scope, GroupName, Pid, PreviousMeta, Meta, normal]),
    %% broadcast
    syn_gen_scope:broadcast({'3.0', sync_join, GroupName, Pid, Meta, Time, Reason}, [RequesterNode], State),
    %% return
    {reply, {ok, {CallbackMethod, PreviousMeta, Meta, Time, TableByName, TableByPid}}, State}.

-spec get_pg_tuples_for_node(Node :: node(), TableByName :: atom()) -> [syn_pg_tuple()].
get_pg_tuples_for_node(Node, TableByName) ->
    ets:select(TableByName, [{
        {{'$1', '$2'}, '$3', '$4', '_', Node},
        [],
        [{{'$1', '$2', '$3', '$4'}}]
    }]).

-spec find_monitor_for_pid(Pid :: pid(), TableByPid :: atom()) -> reference() | undefined.
find_monitor_for_pid(Pid, TableByPid) when is_pid(Pid) ->
    %% we use select instead of lookup to limit the results and thus cover the case
    %% when a process is in multiple groups
    case ets:select(TableByPid, [{
        {{Pid, '_'}, '_', '_', '$5', '_'},
        [],
        ['$5']
    }], 1) of
        {[MRef], _} -> MRef;
        '$end_of_table' -> undefined
    end.

-spec find_pg_entry_by_name_and_pid(GroupName :: term(), Pid :: pid(), TableByName :: atom()) ->
    Entry :: syn_pg_entry() | undefined.
find_pg_entry_by_name_and_pid(GroupName, Pid, TableByName) ->
    case ets:lookup(TableByName, {GroupName, Pid}) of
        [] -> undefined;
        [Entry] -> Entry
    end.

-spec find_pg_entries_by_pid(Pid :: pid(), TableByPid :: atom()) -> GroupEntries :: [syn_pg_entry()].
find_pg_entries_by_pid(Pid, TableByPid) when is_pid(Pid) ->
    ets:select(TableByPid, [{
        {{Pid, '_'}, '_', '_', '_', '_'},
        [],
        ['$_']
    }]).

-spec maybe_demonitor(Pid :: pid(), TableByPid :: atom()) -> ok.
maybe_demonitor(Pid, TableByPid) ->
    %% select 2: if only 1 is returned it means that no other aliases exist for the Pid
    %% we use select instead of lookup to limit the results and thus cover the case
    %% when a process is in multiple groups
    case ets:select(TableByPid, [{
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
    GroupName :: term(),
    Pid :: pid(),
    Meta :: term(),
    Time :: integer(),
    MRef :: undefined | reference(),
    TableByName :: atom(),
    TableByPid :: atom()
) -> true.
add_to_local_table(GroupName, Pid, Meta, Time, MRef, TableByName, TableByPid) ->
    %% insert
    ets:insert(TableByName, {{GroupName, Pid}, Meta, Time, MRef, node(Pid)}),
    ets:insert(TableByPid, {{Pid, GroupName}, Meta, Time, MRef, node(Pid)}).

-spec remove_from_local_table(
    Name :: term(),
    Pid :: pid(),
    TableByName :: atom(),
    TableByPid :: atom()
) -> true.
remove_from_local_table(GroupName, Pid, TableByName, TableByPid) ->
    true = ets:delete(TableByName, {GroupName, Pid}),
    true = ets:delete(TableByPid, {Pid, GroupName}).

-spec purge_pg_for_remote_nodes(Scope :: atom(), TableByName :: atom(), TableByPid :: atom()) -> any().
purge_pg_for_remote_nodes(Scope, TableByName, TableByPid) ->
    LocalNode = node(),
    DuplicatedRemoteNodes = ets:select(TableByName, [{
        {{'_', '_'}, '_', '_', '_', '$6'},
        [{'=/=', '$6', LocalNode}],
        ['$6']
    }]),
    RemoteNodes = ordsets:from_list(DuplicatedRemoteNodes),
    ordsets:fold(fun(RemoteNode, _) ->
        purge_pg_for_remote_node(Scope, RemoteNode, TableByName, TableByPid)
    end, undefined, RemoteNodes).

-spec purge_pg_for_remote_node(Scope :: atom(), Node :: atom(), TableByName :: atom(), TableByPid :: atom()) -> true.
purge_pg_for_remote_node(Scope, Node, TableByName, TableByPid) when Node =/= node() ->
    %% loop elements for callback in a separate process to free scope process
    PgTuples = get_pg_tuples_for_node(Node, TableByName),
    lists:foreach(fun({GroupName, Pid, Meta, _Time}) ->
        syn_event_handler:call_event_handler(on_process_left,
            [Scope, GroupName, Pid, Meta, {syn_remote_scope_node_down, Scope, Node}]
        )
    end, PgTuples),
    ets:match_delete(TableByName, {{'_', '_'}, '_', '_', '_', Node}),
    ets:match_delete(TableByPid, {{'_', '_'}, '_', '_', '_', Node}).

-spec handle_pg_sync(
    GroupName :: term(),
    Pid :: pid(),
    Meta :: term(),
    Time :: non_neg_integer(),
    Reason :: term(),
    #state{}
) -> any().
handle_pg_sync(GroupName, Pid, Meta, Time, Reason, #state{
    scope = Scope,
    table_by_name = TableByName,
    table_by_pid = TableByPid
}) ->
    case find_pg_entry_by_name_and_pid(GroupName, Pid, TableByName) of
        undefined ->
            %% new
            add_to_local_table(GroupName, Pid, Meta, Time, undefined, TableByName, TableByPid),
            %% callback
            syn_event_handler:call_event_handler(on_process_joined, [Scope, GroupName, Pid, Meta, Reason]);

        {{GroupName, Pid}, TableMeta, TableTime, _, _} when Time > TableTime ->
            %% maybe updated meta or time only
            add_to_local_table(GroupName, Pid, Meta, Time, undefined, TableByName, TableByPid),
            %% callback (call only if meta update)
            case TableMeta =/= Meta of
                true ->
                    syn_event_handler:call_event_handler(on_group_process_updated, [Scope, GroupName, Pid, Meta, Reason]),
                    syn_event_handler:call_event_handler(on_group_process_updated, [Scope, GroupName, Pid, TableMeta, Meta, Reason]);
                _ -> ok
            end;

        _ ->
            %% race condition: incoming data is older, ignore
            ok
    end.

-spec multi_call_and_receive(
    CollectorPid :: pid(),
    Pid :: pid(),
    Meta :: term(),
    Message :: term(),
    Timeout :: non_neg_integer()
) -> any().
multi_call_and_receive(CollectorPid, Pid, Meta, Message, Timeout) ->
    %% monitor
    MRef = monitor(process, Pid),
    %% send
    Ref = make_ref(),
    From = {self(), Ref},
    Pid ! {syn_multi_call, Message, From, Meta},
    %% wait for reply
    receive
        {syn_multi_call_reply, Ref, Reply} ->
            erlang:demonitor(MRef, [flush]),
            CollectorPid ! {syn_reply, Pid, Reply};

        {'DOWN', MRef, _, _, _} ->
            CollectorPid ! {syn_bad_reply, Pid}

    after Timeout ->
        erlang:demonitor(MRef, [flush]),
        CollectorPid ! {syn_bad_reply, Pid}
    end.

-spec collect_replies(MembersOD :: orddict:orddict({pid(), Meta :: term()})) ->
    {
        Replies :: [{{pid(), Meta :: term()}, Reply :: term()}],
        BadReplies :: [{pid(), Meta :: term()}]
    }.
collect_replies(MembersOD) ->
    collect_replies(MembersOD, [], []).

-spec collect_replies(
    MembersOD :: orddict:orddict({pid(), Meta :: term()}),
    Replies :: [{{pid(), Meta :: term()}, Reply :: term()}],
    BadReplies :: [{pid(), Meta :: term()}]
) ->
    {
        Replies :: [{{pid(), Meta :: term()}, Reply :: term()}],
        BadReplies :: [{pid(), Meta :: term()}]
    }.
collect_replies([], Replies, BadReplies) -> {Replies, BadReplies};
collect_replies(MembersOD, Replies, BadReplies) ->
    receive
        {syn_reply, Pid, Reply} ->
            {Meta, MembersOD1} = orddict:take(Pid, MembersOD),
            collect_replies(MembersOD1, [{{Pid, Meta}, Reply} | Replies], BadReplies);

        {syn_bad_reply, Pid} ->
            {Meta, MembersOD1} = orddict:take(Pid, MembersOD),
            collect_replies(MembersOD1, Replies, [{Pid, Meta} | BadReplies])
    end.
