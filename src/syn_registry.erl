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

%% types
%% this node's registration of a name, with the monitor on its process
-type own_claim() :: {Pid :: pid(), Meta :: term(), Time :: integer(), MRef :: reference()}.
%% another node's registration of a name, as that node holds it
-type claim() :: {Pid :: pid(), Meta :: term(), Time :: integer()}.
%% a registration of another node that this node doesn't show
-type aside_entry() :: {Name :: term(), Node :: node(), Pid :: pid(), Meta :: term(), Time :: integer()}.

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
            Response = case Node =/= node() of
                true ->
                    %% the scope process of this node applies the result, in order with everything else the process'
                    %% node sends it, and replies once it has: a lookup on this node right after the call sees it
                    syn_gen_scope:call_ordered(?MODULE, Node, Scope,
                        {'3.5', register_or_update_on_node_ordered, Name, Pid, MetaOrFun});

                false ->
                    syn_gen_scope:call(?MODULE, Scope, {'3.5', register_or_update_on_node, Name, Pid, MetaOrFun})
            end,
            case Response of
                {ok, {Pid, Meta}} -> {ok, {Pid, Meta}};
                {error, Reason} -> {error, Reason};
                {raise, Class, Reason, Stacktrace} -> erlang:raise(Class, Reason, Stacktrace)
            end
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

                {Name, Pid, _, _, _, _} ->
                    Node = node(Pid),
                    case Node =/= node() of
                        true -> syn_gen_scope:call_ordered(?MODULE, Node, Scope, {'3.5', unregister_on_node_ordered, Name, Pid});
                        false -> syn_gen_scope:call(?MODULE, Scope, {'3.5', unregister_on_node, Name, Pid})
                    end
            end
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
    %% init, with a table for the registrations of other nodes that this node doesn't show (see store/4)
    HandlerState = #{aside => ets:new(syn_registry_aside, [bag])},
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
handle_call({'3.5', register_or_update_on_node, Name, Pid, MetaOrFun}, _From, State) ->
    case register_or_update_on_node(node(), Name, Pid, MetaOrFun, State) of
        {ok, Meta, _Time} ->
            %% an update can make this node lose a conflict it was keeping
            resolve(Name, all, State),
            {reply, {ok, {Pid, Meta}}, State};

        {noop, Meta, _Time} ->
            {reply, {ok, {Pid, Meta}}, State};

        Error ->
            {reply, Error, State}
    end;

handle_call({'3.5', register_or_update_on_node_ordered, Name, Pid, MetaOrFun, Requester}, From, State) ->
    {RequesterNode, State1} = syn_gen_scope:discover_requester(Requester, State),
    case register_or_update_on_node(RequesterNode, Name, Pid, MetaOrFun, State1) of
        {ok, Meta, Time} ->
            Message = {'3.5', sync_register_reply, self(), Name, Pid, Meta, Time},
            Result = syn_gen_scope:send_ordered_result(Requester, Message, {ok, {Pid, Meta}}, From, State1),
            %% an update can make this node lose a conflict it was keeping: the withdrawal goes after the result,
            %% so that the caller's node doesn't put the registration back after removing it
            resolve(Name, all, State1),
            Result;

        {noop, Meta, Time} ->
            %% sent anyway, the requester may be missing the entry
            Message = {'3.5', sync_register_reply, self(), Name, Pid, Meta, Time},
            syn_gen_scope:send_ordered_result(Requester, Message, {ok, {Pid, Meta}}, From, State1);

        Error ->
            {reply, Error, State1}
    end;

handle_call({'3.5', unregister_on_node, Name, Pid}, _From, State) ->
    case unregister_on_node(node(), Name, Pid, State) of
        {ok, _Meta} -> {reply, ok, State};
        {error, Reason} -> {reply, {error, Reason}, State}
    end;

handle_call({'3.5', unregister_on_node_ordered, Name, Pid, Requester}, From, State) ->
    {RequesterNode, State1} = syn_gen_scope:discover_requester(Requester, State),
    case unregister_on_node(RequesterNode, Name, Pid, State1) of
        {ok, Meta} ->
            Message = {'3.5', sync_unregister_reply, self(), Name, Pid, Meta},
            syn_gen_scope:send_ordered_result(Requester, Message, ok, From, State1);

        {error, Reason} ->
            {reply, {error, Reason}, State1}
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
handle_info({'3.5', sync_register, ScopePid, Name, Pid, Meta, Time, Reason}, State) ->
    case is_from_owner(ScopePid, Pid, State) of
        true -> put_claim(Name, Pid, Meta, Time, Reason, State);
        false -> ok
    end,
    {noreply, State};

handle_info({'3.5', sync_register_reply, ScopePid, Name, Pid, Meta, Time, From}, #state{
    table_by_name = TableByName
} = State) ->
    Reply = case is_from_owner(ScopePid, Pid, State) of
        true ->
            put_claim(Name, Pid, Meta, Time, normal, State),
            case find_registry_entry_by_name(Name, TableByName) of
                {Name, Pid, _, _, _, _} ->
                    {ok, {Pid, Meta}};

                _ ->
                    %% this node shows another registration of the name
                    {error, race_condition}
            end;

        false ->
            %% a scope process this node doesn't know (anymore): the entry comes with its full data, unless this node
            %% doesn't sync with that one, as with a hidden node
            {ok, {Pid, Meta}}
    end,
    syn_gen_scope:reply_ordered(From, Reply),
    {noreply, State};

handle_info({'3.5', sync_unregister, ScopePid, Name, Pid, _Meta, Reason}, State) ->
    case is_from_owner(ScopePid, Pid, State) of
        true -> drop_claim(Name, Pid, Reason, State);
        false -> ok
    end,
    {noreply, State};

handle_info({'3.5', sync_unregister_reply, ScopePid, Name, Pid, _Meta, From}, State) ->
    case is_from_owner(ScopePid, Pid, State) of
        true -> drop_claim(Name, Pid, normal, State);
        false -> ok
    end,
    syn_gen_scope:reply_ordered(From, ok),
    {noreply, State};

handle_info({'DOWN', _MRef, process, Pid, Reason}, #state{
    scope = Scope,
    table_by_pid = TableByPid
} = State) ->
    case find_registry_entries_by_pid(Pid, TableByPid) of
        [] ->
            ?LOG_WARNING(#{handler => ?MODULE_LOG_NAME, scope => Scope,
                           event => unknown_down, pid => Pid, reason => Reason});

        Entries ->
            lists:foreach(fun({_, Name, Meta, _, _, _}) ->
                withdraw(Name, Pid, Meta, Reason, [], State)
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
    %% a node always shows its own registrations
    {ok, get_registry_tuples_for_node(node(), TableByName)}.

%% the full data of a node replaces what this node had from it
-spec save_remote_data(RemoteNode :: node(), RemoteData :: term(), #state{}) -> any().
save_remote_data(RemoteNode, RegistryTuplesOfRemoteNode, #state{scope = Scope} = State) ->
    Reason = {syn_remote_scope_node_up, Scope, RemoteNode},
    SnapshotNames = maps:from_list([{Name, true} || {Name, _, _, _} <- RegistryTuplesOfRemoteNode]),
    %% what the node doesn't hold anymore
    lists:foreach(fun({Name, Pid}) ->
        case maps:is_key(Name, SnapshotNames) of
            true -> ok;
            false -> drop_claim(Name, Pid, Reason, State)
        end
    end, claimed_by_node(RemoteNode, State)),
    %% what it holds now
    lists:foreach(fun({Name, Pid, Meta, Time}) ->
        put_claim(Name, Pid, Meta, Time, Reason, State)
    end, RegistryTuplesOfRemoteNode).

-spec purge_local_data_for_node(Node :: node(), #state{}) -> any().
purge_local_data_for_node(Node, #state{scope = Scope} = State) ->
    Reason = {syn_remote_scope_node_down, Scope, Node},
    lists:foreach(fun({Name, Pid}) ->
        drop_claim(Name, Pid, Reason, State)
    end, claimed_by_node(Node, State)).

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
    {ok, Meta :: term(), Time :: integer()} |
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
                    do_register_on_node(Name, Pid, MetaOrFun, MRef, RequesterNode, State);

                {Name, Pid, TableMeta, TableTime, MRef, _} when is_function(MetaOrFun) ->
                    %% update with fun
                    try MetaOrFun(Pid, TableMeta) of
                        Meta when Meta =:= TableMeta ->
                            {noop, TableMeta, TableTime};

                        Meta ->
                            do_register_on_node(Name, Pid, Meta, MRef, RequesterNode, State)

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

                {Name, Pid, _, _, MRef, _} ->
                    %% same pid, different meta
                    do_register_on_node(Name, Pid, MetaOrFun, MRef, RequesterNode, State);

                _ ->
                    {error, taken}
            end;

        false ->
            {error, not_alive}
    end.

-spec unregister_on_node(RequesterNode :: node(), Name :: term(), Pid :: pid(), #state{}) ->
    {ok, Meta :: term()} | {error, Reason :: term()}.
unregister_on_node(RequesterNode, Name, Pid, #state{
    table_by_name = TableByName,
    table_by_pid = TableByPid
} = State) ->
    case find_registry_entry_by_name(Name, TableByName) of
        undefined ->
            {error, undefined};

        {Name, Pid, Meta, _, _, _} ->
            %% demonitor if the process is not registered under other names
            maybe_demonitor(Pid, TableByPid),
            withdraw(Name, Pid, Meta, normal, [RequesterNode], State),
            {ok, Meta};

        _ ->
            %% process is registered locally with another pid: race condition, wait for sync to happen & return error
            {error, race_condition}
    end.

-spec do_register_on_node(
    Name :: term(),
    Pid :: pid(),
    Meta :: term(),
    MRef :: reference(),
    RequesterNode :: node(),
    #state{}
) -> {ok, Meta :: term(), Time :: integer()}.
do_register_on_node(Name, Pid, Meta, MRef, RequesterNode, State) ->
    Time = erlang:system_time(),
    case read(Name, State) of
        {Before, []} ->
            %% no other node holds the name: what this node shows is its own registration
            show(Name, Before, {Pid, Meta, Time, MRef}, normal, State);

        Stored ->
            {_, Others} = claims(Stored),
            store(Name, {{Pid, Meta, Time, MRef}, Others}, normal, Stored, State)
    end,
    syn_gen_scope:broadcast({'3.5', sync_register, self(), Name, Pid, Meta, Time, normal}, [RequesterNode], State),
    {ok, Meta, Time}.

%% this node drops its own registration of Pid under Name and tells the other nodes, but ExcludedNodes
-spec withdraw(Name :: term(), Pid :: pid(), Meta :: term(), Reason :: term(), ExcludedNodes :: [node()], #state{}) ->
    any().
withdraw(Name, Pid, Meta, Reason, ExcludedNodes, State) ->
    case read(Name, State) of
        {Before, []} ->
            %% no other node holds the name: nothing to show instead
            show(Name, Before, undefined, Reason, State);

        Stored ->
            {_, Others} = claims(Stored),
            store(Name, {undefined, Others}, Reason, Stored, State)
    end,
    syn_gen_scope:broadcast({'3.5', sync_unregister, self(), Name, Pid, Meta, Reason}, ExcludedNodes, State).

%% Pid's node holds Pid under Name, with Meta and Time
-spec put_claim(Name :: term(), Pid :: pid(), Meta :: term(), Time :: integer(), Reason :: term(), #state{}) -> any().
put_claim(Name, Pid, Meta, Time, Reason, State) ->
    Node = node(Pid),
    case read(Name, State) of
        {{_, Pid, Meta, Time, _, _}, _} ->
            %% nothing changed
            ok;

        {Before, []} when Before =:= undefined; element(6, Before) =:= Node ->
            %% no other node holds the name: what this node shows is this registration
            show(Name, Before, {Pid, Meta, Time, undefined}, Reason, State);

        Stored ->
            {Own, Others} = claims(Stored),
            Claim = {Pid, Meta, Time},
            case maps:find(Node, Others) of
                {ok, Claim} ->
                    %% nothing changed
                    ok;

                _ ->
                    store(Name, {Own, Others#{Node => Claim}}, Reason, Stored, State),
                    case Own of
                        undefined -> ok;
                        _ -> resolve(Name, [Node], State)
                    end
            end
    end.

%% Pid's node doesn't hold Pid under Name anymore
-spec drop_claim(Name :: term(), Pid :: pid(), Reason :: term(), #state{}) -> any().
drop_claim(Name, Pid, Reason, State) ->
    case read(Name, State) of
        {{_, Pid, _, _, _, _} = Before, []} ->
            %% no other node holds the name: nothing to show instead
            show(Name, Before, undefined, Reason, State);

        Stored ->
            {Own, Others} = claims(Stored),
            Node = node(Pid),
            case maps:find(Node, Others) of
                {ok, {Pid, _, _}} -> store(Name, {Own, maps:remove(Node, Others)}, Reason, Stored, State);
                _ -> ok
            end
    end.

%% what this node stores for Name: the entry it shows, and the registrations of other nodes it keeps aside
-spec read(Name :: term(), #state{}) -> {Shown :: syn_registry_entry() | undefined, Aside :: [aside_entry()]}.
read(Name, #state{table_by_name = TableByName} = State) ->
    {find_registry_entry_by_name(Name, TableByName), ets:lookup(aside_table(State), Name)}.

%% the registrations of Name that this node has: its own, if it holds one, and those of other nodes, by node
-spec claims({Shown :: syn_registry_entry() | undefined, Aside :: [aside_entry()]}) ->
    {Own :: own_claim() | undefined, Others :: #{node() => claim()}}.
claims({Shown, Aside}) ->
    Others = maps:from_list([{Node, {Pid, Meta, Time}} || {_, Node, Pid, Meta, Time} <- Aside]),
    LocalNode = node(),
    case Shown of
        undefined -> {undefined, Others};
        {_, Pid, Meta, Time, MRef, LocalNode} -> {{Pid, Meta, Time, MRef}, Others};
        {_, Pid, Meta, Time, _, Node} -> {undefined, Others#{Node => {Pid, Meta, Time}}}
    end.

%% the names a node holds, as this node has them
-spec claimed_by_node(Node :: node(), #state{}) -> [{Name :: term(), Pid :: pid()}].
claimed_by_node(Node, #state{table_by_name = TableByName} = State) ->
    Shown = ets:select(TableByName, [{{'$1', '$2', '_', '_', '_', Node}, [], [{{'$1', '$2'}}]}]),
    Aside = ets:select(aside_table(State), [{{'$1', Node, '$2', '_', '_'}, [], [{{'$1', '$2'}}]}]),
    Shown ++ Aside.

%% stores the registrations of Name that this node has, where it had Stored: the one it shows goes in the tables, the
%% others aside. A node shows its own registration if it holds one, and otherwise the most recent one, the node name
%% breaking ties, so that every node shows the same one. The callbacks report the change in what this node shows.
-spec store(
    Name :: term(),
    {Own :: own_claim() | undefined, Others :: #{node() => claim()}},
    Reason :: term(),
    Stored :: {Shown :: syn_registry_entry() | undefined, Aside :: [aside_entry()]},
    #state{}
) -> any().
store(Name, {Own, Others}, Reason, {Before, BeforeAside}, State) ->
    Shown = case Own of
        undefined -> newest(Others);
        _ -> Own
    end,
    %% aside: only what changed, most names have no registration aside
    ShownNode = case Shown of
        undefined -> undefined;
        {ShownPid, _, _, _} -> node(ShownPid)
    end,
    Aside = [{Name, Node, Pid, Meta, Time} || {Node, {Pid, Meta, Time}} <- maps:to_list(Others), Node =/= ShownNode],
    case Aside =:= BeforeAside of
        true ->
            ok;

        false ->
            AsideTable = aside_table(State),
            AsideSet = maps:from_keys(Aside, true),
            BeforeAsideSet = maps:from_keys(BeforeAside, true),
            [true = ets:delete_object(AsideTable, Entry) || Entry <- BeforeAside, not maps:is_key(Entry, AsideSet)],
            [true = ets:insert(AsideTable, Entry) || Entry <- Aside, not maps:is_key(Entry, BeforeAsideSet)]
    end,
    show(Name, Before, Shown, Reason, State).

%% puts Shown in the tables in place of Before, the entry this node showed for Name, and calls the callbacks for the change
-spec show(
    Name :: term(),
    Before :: syn_registry_entry() | undefined,
    Shown :: {Pid :: pid(), Meta :: term(), Time :: integer(), MRef :: reference() | undefined} | undefined,
    Reason :: term(),
    #state{}
) -> any().
show(Name, Before, Shown, Reason, #state{
    scope = Scope,
    table_by_name = TableByName,
    table_by_pid = TableByPid
}) ->
    case {Before, Shown} of
        {undefined, undefined} ->
            ok;

        {undefined, {Pid, Meta, Time, MRef}} ->
            add_to_local_table(Name, Pid, Meta, Time, MRef, TableByName, TableByPid),
            syn_event_handler:call_event_handler(on_process_registered, [Scope, Name, Pid, Meta, Reason]);

        {{_, TablePid, TableMeta, _, _, _}, undefined} ->
            remove_from_local_table(Name, TablePid, TableByName, TableByPid),
            syn_event_handler:call_event_handler(on_process_unregistered, [Scope, Name, TablePid, TableMeta, Reason]);

        {{_, Pid, Meta, Time, MRef, _}, {Pid, Meta, Time, MRef}} ->
            ok;

        {{_, Pid, TableMeta, _, _, _}, {Pid, Meta, Time, MRef}} ->
            add_to_local_table(Name, Pid, Meta, Time, MRef, TableByName, TableByPid),
            case TableMeta =/= Meta of
                true ->
                    syn_event_handler:call_event_handler(on_registry_process_updated, [Scope, Name, Pid, Meta, Reason]),
                    syn_event_handler:call_event_handler(on_registry_process_updated, [Scope, Name, Pid, TableMeta, Meta, Reason]);

                false ->
                    ok
            end;

        {{_, TablePid, TableMeta, _, _, _}, {Pid, Meta, Time, MRef}} ->
            remove_from_local_table(Name, TablePid, TableByName, TableByPid),
            add_to_local_table(Name, Pid, Meta, Time, MRef, TableByName, TableByPid),
            syn_event_handler:call_event_handler(on_process_unregistered, [Scope, Name, TablePid, TableMeta, Reason]),
            syn_event_handler:call_event_handler(on_process_registered, [Scope, Name, Pid, Meta, Reason])
    end.

%% the most recent of the other nodes' registrations, the node name breaking ties, or undefined
-spec newest(Others :: #{node() => claim()}) ->
    {Pid :: pid(), Meta :: term(), Time :: integer(), MRef :: undefined} | undefined.
newest(Others) ->
    Newest = maps:fold(fun
        (Node, {_, _, Time} = Claim, {NewestTime, NewestNode, _}) when {Time, Node} > {NewestTime, NewestNode} ->
            {Time, Node, Claim};
        (_, _, {_, _, _} = Acc) ->
            Acc;
        (Node, {_, _, Time} = Claim, undefined) ->
            {Time, Node, Claim}
    end, undefined, Others),
    case Newest of
        undefined -> undefined;
        {_, _, {Pid, Meta, Time}} -> {Pid, Meta, Time, undefined}
    end.

%% this node holds Name and has other nodes' registrations of it: the resolver decides between this node's process and
%% the registrations of Nodes (all of them when this node's own registration changed, otherwise the ones that changed).
%% This node keeps its own only if it wins every time, and otherwise drops it and tells everyone; the node that keeps
%% its own does nothing, since the others drop theirs
-spec resolve(Name :: term(), Nodes :: [node()] | all, #state{}) -> any().
resolve(Name, Nodes, #state{scope = Scope, table_by_pid = TableByPid} = State) ->
    case claims(read(Name, State)) of
        {{TablePid, TableMeta, TableTime, _}, Others} when map_size(Others) > 0 ->
            Contenders = case Nodes of
                all -> maps:values(Others);
                _ -> [Claim || {Node, Claim} <- maps:to_list(Others), lists:member(Node, Nodes)]
            end,
            Outcomes = lists:map(fun({Pid, Meta, _Time} = Claim) ->
                %% both nodes pass the two registrations in the same order, the one of the node whose name sorts
                %% first being the first, so that a resolver that only looks at its arguments decides the same on both
                {First, Second} = case node(Pid) < node(TablePid) of
                    true -> {Claim, {TablePid, TableMeta, TableTime}};
                    false -> {{TablePid, TableMeta, TableTime}, Claim}
                end,
                {PidToKeep, KillOtherPid} = syn_event_handler:do_resolve_registry_conflict(Scope, Name, First, Second),
                Keep = case PidToKeep of
                    TablePid -> local;
                    Pid -> remote;
                    Invalid -> {none, Invalid}
                end,
                ?LOG_NOTICE(#{handler => ?MODULE_LOG_NAME, scope => Scope,
                            event => registry_conflict, name => Name,
                            remote => {Pid, Meta}, local => {TablePid, TableMeta}, keep => Keep}),
                {Keep, KillOtherPid}
            end, Contenders),
            case [KillOtherPid || {Keep, KillOtherPid} <- Outcomes, Keep =/= local] of
                [] ->
                    ok;

                Kills ->
                    maybe_demonitor(TablePid, TableByPid),
                    case lists:member(true, Kills) of
                        true -> exit(TablePid, {syn_resolve_kill, Name, TableMeta});
                        false -> ok
                    end,
                    withdraw(Name, TablePid, TableMeta, syn_conflict_resolution, [], State)
            end;

        _ ->
            ok
    end.

%% a message about Pid comes from the scope process this node knows for Pid's node
-spec is_from_owner(ScopePid :: pid(), Pid :: pid(), #state{}) -> boolean().
is_from_owner(ScopePid, Pid, State) ->
    node(ScopePid) =:= node(Pid) andalso syn_gen_scope:is_current_scope(ScopePid, State).

-spec aside_table(#state{}) -> ets:table().
aside_table(#state{handler_state = #{aside := Aside}}) -> Aside.

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
    MRef :: undefined | reference(),
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
