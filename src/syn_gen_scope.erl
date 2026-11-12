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
-module(syn_gen_scope).
-behaviour(gen_server).

%% API
-export([
    start_link/3,
    subcluster_nodes/2,
    call/3,
    call_ordered/4,
    reply_ordered/2
]).
-export([
    broadcast/2,
    broadcast/3,
    is_current_scope/2,
    discover_requester/2,
    send_ordered_result/5
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    handle_continue/2,
    terminate/2,
    code_change/3
]).

%% internal
-export([sender_loop/0]).

%% includes
-include("syn.hrl").

-include_lib("kernel/include/logger.hrl").

%% types
-type requester() :: {node(), ScopePid :: pid() | undefined, ReplyWhen :: applied | handled}.

%% callbacks
-callback init(#state{}) ->
    {ok, HandlerState :: term()}.
-callback handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    #state{}) ->
    {reply, Reply :: term(), #state{}} |
    {reply, Reply :: term(), #state{}, timeout() | hibernate | {continue, term()}} |
    {noreply, #state{}} |
    {noreply, #state{}, timeout() | hibernate | {continue, term()}} |
    {stop, Reason :: term(), Reply :: term(), #state{}} |
    {stop, Reason :: term(), #state{}}.
-callback handle_info(Info :: timeout | term(), #state{}) ->
    {noreply, #state{}} |
    {noreply, #state{}, timeout() | hibernate | {continue, term()}} |
    {stop, Reason :: term(), #state{}}.
-callback save_remote_data(RemoteNode :: node(), RemoteData :: term(), #state{}) -> any().
-callback get_local_data(#state{}) -> {ok, Data :: term()}.
-callback purge_local_data_for_node(Node :: node(), #state{}) -> any().

%% ===================================================================
%% API
%% ===================================================================
-spec start_link(Handler :: module(), HandlerLogName :: atom(), Scope :: atom()) ->
    {ok, pid()} | {error, {already_started, pid()}} | {error, Reason :: term()}.
start_link(Handler, HandlerLogName, Scope) when is_atom(Scope) ->
    %% build name
    HandlerBin = list_to_binary(atom_to_list(Handler)),
    ScopeBin = list_to_binary(atom_to_list(Scope)),
    ProcessName = list_to_atom(binary_to_list(<<HandlerBin/binary, "_", ScopeBin/binary>>)),
    %% save to lookup table
    syn_backbone:save_process_name({Handler, Scope}, ProcessName),
    %% create process
    gen_server:start_link({local, ProcessName}, ?MODULE, [Handler, HandlerLogName, Scope, ProcessName], []).

-spec subcluster_nodes(Handler :: module(), Scope :: atom()) -> [node()].
subcluster_nodes(Handler, Scope) ->
    case get_process_name_for_scope(Handler, Scope) of
        undefined -> error({invalid_scope, Scope});
        ProcessName -> gen_server:call(ProcessName, {'3.5', subcluster_nodes})
    end.

-spec call(Handler :: module(), Scope :: atom(), Message :: term()) -> Response :: term().
call(Handler, Scope, Message) ->
    call(Handler, node(), Scope, Message).

-spec call(Handler :: module(), Node :: atom(), Scope :: atom(), Message :: term()) -> Response :: term().
call(Handler, Node, Scope, Message) ->
    case get_process_name_for_scope(Handler, Scope) of
        undefined -> error({invalid_scope, Scope});
        ProcessName ->
            try gen_server:call({ProcessName, Node}, Message)
            catch exit:{noproc, {gen_server, call, _}} when node() =/= Node ->
                error({invalid_remote_scope, Scope, Node})
            end
    end.

%% a call for a process on another node: that node sends the result to the local scope process, after everything
%% it sent it before, and the local scope process applies it and then replies (see send_ordered_result/5)
-spec call_ordered(Handler :: module(), Node :: atom(), Scope :: atom(), Message :: tuple()) -> Response :: term().
call_ordered(Handler, Node, Scope, Message) ->
    case get_process_name_for_scope(Handler, Scope) of
        undefined ->
            error({invalid_scope, Scope});

        ProcessName ->
            %% a scope process can't wait for one, itself included: it gets the reply right away,
            %% and the local scope process applies the result when it gets to it
            ReplyWhen = case is_scope_process() of
                true -> handled;
                false -> applied
            end,
            Requester = {node(), whereis(ProcessName), ReplyWhen},
            case call(Handler, Node, Scope, erlang:append_element(Message, Requester)) of
                undefined ->
                    %% that node runs a version of Syn that this one doesn't sync with
                    error({invalid_remote_scope, Scope, Node});

                Response ->
                    Response
            end
    end.

%% replies to the caller of an ordered call, unless it got its reply already
-spec reply_ordered(From :: {pid(), Tag :: term()} | undefined, Reply :: term()) -> ok.
reply_ordered(undefined, _Reply) -> ok;
reply_ordered(From, Reply) -> gen_server:reply(From, Reply).

%% ===================================================================
%% In-Process API
%% ===================================================================
-spec broadcast(Message :: term(), #state{}) -> any().
broadcast(Message, State) ->
    broadcast(Message, [], State).

-spec broadcast(Message :: term(), ExcludedNodes :: [node()], #state{}) -> any().
broadcast(Message, ExcludedNodes, #state{sender_pid = SenderPid, process_name = ProcessName, nodes_map = NodesMap}) ->
    SenderPid ! {broadcast, Message, ExcludedNodes, ProcessName, maps:keys(NodesMap)}.

-spec send_to_node(RemoteNode :: node(), Message :: term(), #state{}) -> any().
send_to_node(RemoteNode, Message, #state{sender_pid = SenderPid, process_name = ProcessName}) ->
    SenderPid ! {send_single, RemoteNode, Message, ProcessName}.

%% ScopePid is the scope process this one knows for its node: only what that process sends gets applied
-spec is_current_scope(ScopePid :: pid(), #state{}) -> boolean().
is_current_scope(ScopePid, #state{nodes_map = NodesMap}) ->
    case maps:find(node(ScopePid), NodesMap) of
        {ok, {ScopePid, _MRef}} -> true;
        _ -> false
    end.

%% an ordered call from a scope process this one doesn't know: that node gets the local data first, so that it knows
%% this node when the result reaches it, and is asked for its own
-spec discover_requester(Requester :: requester(), #state{}) -> {RequesterNode :: node(), #state{}}.
discover_requester({RequesterNode, RequesterScopePid, _}, State) when is_pid(RequesterScopePid) ->
    case is_current_scope(RequesterScopePid, State) orelse not is_connected(RequesterNode) of
        true ->
            %% known, or gone since the call: the result can't reach it anyway, and it syncs again once it's back
            {RequesterNode, State};

        false ->
            case adopt(RequesterScopePid, State) of
                {ok, State1} ->
                    send_local_data(RequesterNode, State1),
                    {RequesterNode, ask(RequesterNode, State1)};

                disconnected ->
                    {RequesterNode, State}
            end
    end;
discover_requester({RequesterNode, undefined, _}, State) ->
    {RequesterNode, State}.

%% the result of an ordered call goes to the scope process of the requester after everything sent to it before,
%% with From appended: that process applies it and then replies, unless the call came from a scope process,
%% which gets Reply now
-spec send_ordered_result(
    Requester :: requester(),
    Message :: tuple(),
    Reply :: term(),
    From :: {pid(), Tag :: term()},
    #state{}
) -> {noreply, #state{}} | {reply, Reply :: term(), #state{}}.
send_ordered_result({RequesterNode, _, applied}, Message, _Reply, From, State) ->
    send_to_node(RequesterNode, erlang:append_element(Message, From), State),
    {noreply, State};
send_ordered_result({RequesterNode, _, handled}, Message, Reply, _From, State) ->
    send_to_node(RequesterNode, erlang:append_element(Message, undefined), State),
    {reply, Reply, State}.

%% ===================================================================
%% Callbacks
%% ===================================================================

%% ----------------------------------------------------------------------------------------------------------
%% Init
%% ----------------------------------------------------------------------------------------------------------
-spec init([term()]) ->
    {ok, #state{}} |
    {ok, #state{}, timeout() | hibernate | {continue, term()}} |
    {stop, Reason :: term()} | ignore.
init([Handler, HandlerLogName, Scope, ProcessName]) ->
    %% monitor nodes
    ok = net_kernel:monitor_nodes(true),
    %% start sender process
    SenderPid = spawn_link(?MODULE, sender_loop, []),
    %% table names
    HandlerBin = list_to_binary(atom_to_list(Handler)),
    TableByName = syn_backbone:get_table_name(list_to_atom(binary_to_list(<<HandlerBin/binary, "_by_name">>)), Scope),
    TableByPid = syn_backbone:get_table_name(list_to_atom(binary_to_list(<<HandlerBin/binary, "_by_pid">>)), Scope),
    %% build state
    State = #state{
        handler = Handler,
        handler_log_name = HandlerLogName,
        scope = Scope,
        process_name = ProcessName,
        sender_pid = SenderPid,
        table_by_name = TableByName,
        table_by_pid = TableByPid
    },
    %% call init
    {ok, HandlerState} = Handler:init(State),
    State1 = State#state{handler_state = HandlerState},
    {ok, State1, {continue, after_init}}.

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
handle_call({'3.5', subcluster_nodes}, _From, #state{
    nodes_map = NodesMap
} = State) ->
    Nodes = maps:keys(NodesMap),
    {reply, Nodes, State};

handle_call(Request, From, #state{handler = Handler} = State) ->
    Handler:handle_call(Request, From, State).

%% ----------------------------------------------------------------------------------------------------------
%% Cast messages
%% ----------------------------------------------------------------------------------------------------------
-spec handle_cast(Request :: term(), #state{}) ->
    {noreply, #state{}} |
    {noreply, #state{}, timeout() | hibernate | {continue, term()}} |
    {stop, Reason :: term(), #state{}}.
handle_cast(Msg, #state{handler_log_name = HandlerLogName, scope = Scope} = State) ->
    ?LOG_WARNING(#{handler => HandlerLogName, scope => Scope, event => unknown_cast, msg => Msg}),
    {noreply, State}.

%% ----------------------------------------------------------------------------------------------------------
%% Info messages
%% ----------------------------------------------------------------------------------------------------------
-spec handle_info(Info :: timeout | term(), #state{}) ->
    {noreply, #state{}} |
    {noreply, #state{}, timeout() | hibernate | {continue, term()}} |
    {stop, Reason :: term(), #state{}}.
handle_info({'3.5', discover, RemoteScopePid}, #state{
    handler_log_name = HandlerLogName,
    scope = Scope
} = State) ->
    RemoteScopeNode = node(RemoteScopePid),
    ?LOG_NOTICE(#{handler => HandlerLogName, scope => Scope,
                 event => discover_request, from => RemoteScopeNode}),
    case {is_connected(RemoteScopeNode), is_current_scope(RemoteScopePid, State)} of
        {false, _} ->
            %% sent before the connection dropped: that node asks again once it's back
            {noreply, State};

        {true, true} ->
            send_local_data(RemoteScopeNode, State),
            {noreply, State};

        {true, false} ->
            %% a scope process this one doesn't know: it gets the local data, and is asked for its own
            case adopt(RemoteScopePid, State) of
                {ok, State1} ->
                    send_local_data(RemoteScopeNode, State1),
                    {noreply, ask(RemoteScopeNode, State1)};

                disconnected ->
                    {noreply, State}
            end
    end;

handle_info({'3.5', ack_sync, RemoteScopePid, Data}, #state{
    handler_log_name = HandlerLogName,
    scope = Scope
} = State) ->
    RemoteScopeNode = node(RemoteScopePid),
    ?LOG_NOTICE(#{handler => HandlerLogName, scope => Scope,
                 event => ack_sync, from => RemoteScopeNode, entries => length(Data)}),
    case {is_connected(RemoteScopeNode), is_current_scope(RemoteScopePid, State)} of
        {false, _} ->
            %% sent before the connection dropped: that node sends its data again once it's back
            {noreply, State};

        {true, true} ->
            save_remote_data(RemoteScopeNode, Data, State);

        {true, false} ->
            %% a scope process this one doesn't know: it gets the local data before a conflict resolution can change it
            case adopt(RemoteScopePid, State) of
                {ok, State1} ->
                    send_local_data(RemoteScopeNode, State1),
                    save_remote_data(RemoteScopeNode, Data, State1);

                disconnected ->
                    {noreply, State}
            end
    end;

handle_info({'DOWN', MRef, process, Pid, Reason}, #state{
    handler = Handler,
    handler_log_name = HandlerLogName,
    scope = Scope,
    nodes_map = NodesMap
} = State) when node(Pid) =/= node() ->
    RemoteNode = node(Pid),
    case maps:find(RemoteNode, NodesMap) of
        {ok, {Pid, MRef}} ->
            ?LOG_NOTICE(#{handler => HandlerLogName, scope => Scope,
                         event => scope_down, from => RemoteNode, reason => Reason}),
            State1 = State#state{nodes_map = maps:remove(RemoteNode, NodesMap)},
            Handler:purge_local_data_for_node(RemoteNode, State1),
            %% connected now, so the node didn't go: its scope process restarted, or this DOWN is from a connection
            %% that dropped and came back. Whatever scope process runs there now sends its data
            case is_connected(RemoteNode) of
                true -> {noreply, send_discover(RemoteNode, State1)};
                false -> {noreply, State1}
            end;

        _ ->
            %% a monitor that has been replaced since
            {noreply, State}
    end;

handle_info({nodedown, RemoteNode}, State) ->
    %% the node's data is purged on the monitor's DOWN; an answer to a request for it can't come anymore, and the
    %% nodeup that follows a reconnection asks again
    {noreply, forget_asked(RemoteNode, State)};

handle_info({nodeup, RemoteNode}, #state{
    handler_log_name = HandlerLogName,
    scope = Scope
} = State) ->
    ?LOG_NOTICE(#{handler => HandlerLogName, scope => Scope,
                 event => nodeup, from => RemoteNode}),
    {noreply, send_discover(RemoteNode, State)};

handle_info(Info, #state{handler = Handler} = State) ->
    Handler:handle_info(Info, State).

%% ----------------------------------------------------------------------------------------------------------
%% Continue messages
%% ----------------------------------------------------------------------------------------------------------
-spec handle_continue(Info :: term(), #state{}) ->
    {noreply, #state{}} |
    {noreply, #state{}, timeout() | hibernate | {continue, term()}} |
    {stop, Reason :: term(), #state{}}.
handle_continue(after_init, #state{
    handler_log_name = HandlerLogName,
    scope = Scope
} = State) ->
    ?LOG_NOTICE(#{handler => HandlerLogName, scope => Scope,
                 event => discovering_cluster}),
    {noreply, lists:foldl(fun send_discover/2, State, nodes())}.

%% ----------------------------------------------------------------------------------------------------------
%% Terminate
%% ----------------------------------------------------------------------------------------------------------
-spec terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()), #state{}) -> any().
terminate(Reason, #state{handler_log_name = HandlerLogName, scope = Scope, sender_pid = SenderPid}) ->
    ?LOG_NOTICE(#{handler => HandlerLogName, scope => Scope,
                 event => terminate, reason => Reason}),
    %% the sender sends what it has queued and stops before this process goes,
    %% so that the other nodes get all of it before its DOWN
    MRef = monitor(process, SenderPid),
    SenderPid ! terminate,
    receive
        {'DOWN', MRef, process, SenderPid, _} -> ok
    after 5000 ->
        ok
    end.

%% ----------------------------------------------------------------------------------------------------------
%% Convert process state when code is changed.
%% ----------------------------------------------------------------------------------------------------------
-spec code_change(OldVsn :: (term() | {down, term()}), #state{}, Extra :: term()) ->
    {ok, NewState :: term()} | {error, Reason :: term()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ===================================================================
%% Internal
%% ===================================================================
-spec get_process_name_for_scope(Handler :: module(), Scope :: atom()) -> ProcessName :: atom() | undefined.
get_process_name_for_scope(Handler, Scope) ->
    syn_backbone:get_process_name({Handler, Scope}).

%% the calling process is a scope process, i.e. code running in a callback
-spec is_scope_process() -> boolean().
is_scope_process() ->
    get('$initial_call') =:= {?MODULE, init, 1}.

%% visible nodes only: a hidden node isn't discovered, and syncing with it after one of its calls would make it share
%% data with the nodes it called and no others, so that the nodes disagree. Its calls still get their results
-spec is_connected(Node :: node()) -> boolean().
is_connected(Node) ->
    lists:member(Node, nodes()).

%% starts treating ScopePid as the scope process of its node, and monitors it: if another one was known for that node,
%% it restarted, so the data that came from it goes, and so does the DOWN still waiting from its monitor.
%% The monitor comes right after checking the connection, before any callback runs, since monitoring a process on a node
%% that just got disconnected makes Erlang connect it again
-spec adopt(ScopePid :: pid(), #state{}) -> {ok, #state{}} | disconnected.
adopt(ScopePid, #state{handler = Handler, nodes_map = NodesMap} = State) ->
    Node = node(ScopePid),
    case is_connected(Node) of
        true ->
            MRef = monitor(process, ScopePid),
            State1 = State#state{nodes_map = NodesMap#{Node => {ScopePid, MRef}}},
            case maps:find(Node, NodesMap) of
                {ok, {OtherScopePid, OldMRef}} when OtherScopePid =/= ScopePid ->
                    erlang:demonitor(OldMRef, [flush]),
                    Handler:purge_local_data_for_node(Node, State1);

                _ ->
                    ok
            end,
            {ok, State1};

        false ->
            disconnected
    end.

%% applies the full data of a node, which also answers a request for it
-spec save_remote_data(RemoteNode :: node(), Data :: term(), #state{}) -> {noreply, #state{}}.
save_remote_data(RemoteNode, Data, #state{handler = Handler, asked = Asked} = State) ->
    State1 = State#state{asked = lists:delete(RemoteNode, Asked)},
    Handler:save_remote_data(RemoteNode, Data, State1),
    {noreply, State1}.

-spec send_local_data(Node :: node(), #state{}) -> any().
send_local_data(Node, #state{handler = Handler} = State) ->
    {ok, LocalData} = Handler:get_local_data(State),
    send_to_node(Node, {'3.5', ack_sync, self(), LocalData}, State).

%% asks Node for its data
-spec send_discover(Node :: node(), #state{}) -> #state{}.
send_discover(Node, #state{asked = Asked} = State) ->
    send_to_node(Node, {'3.5', discover, self()}, State),
    State#state{asked = [Node | lists:delete(Node, Asked)]}.

%% stops waiting for the data of Node, whose connection dropped
-spec forget_asked(Node :: node(), #state{}) -> #state{}.
forget_asked(Node, #state{asked = Asked} = State) ->
    State#state{asked = lists:delete(Node, Asked)}.

%% asks Node for its data, unless already waiting for it
-spec ask(Node :: node(), #state{}) -> #state{}.
ask(Node, #state{asked = Asked} = State) ->
    case lists:member(Node, Asked) of
        true -> State;
        false -> send_discover(Node, State)
    end.

-spec sender_loop() -> terminated.
sender_loop() ->
    sender_loop(#{}).

%% messages to a node go out in the order they came, and only that order matters. A node whose connection is busy, for
%% example because it stopped reading from it, would make a plain send wait: its messages wait in its backlog instead,
%% so that the other nodes, and the results of calls made from them, don't wait for it
-spec sender_loop(Backlogs :: #{node() => queue:queue({atom(), term()})}) -> terminated.
sender_loop(Backlogs) ->
    Backlogs1 = send_backlogs(Backlogs),
    %% a busy connection gives no notice when it frees up: try again soon
    Timeout = case map_size(Backlogs1) of
        0 -> infinity;
        _ -> 1
    end,
    receive
        {broadcast, Message, ExcludedNodes, ProcessName, Nodes} ->
            sender_loop(lists:foldl(fun(RemoteNode, Acc) ->
                send_in_order(RemoteNode, ProcessName, Message, Acc)
            end, Backlogs1, Nodes -- ExcludedNodes));

        {send_single, RemoteNode, Message, ProcessName} ->
            sender_loop(send_in_order(RemoteNode, ProcessName, Message, Backlogs1));

        terminate ->
            %% what still waits for a busy connection goes with this process: that node gets the DOWN and syncs again
            _ = send_backlogs(Backlogs1),
            terminated
    after Timeout ->
        sender_loop(Backlogs1)
    end.

-spec send_in_order(RemoteNode :: node(), ProcessName :: atom(), Message :: term(),
    Backlogs :: #{node() => queue:queue({atom(), term()})}) -> #{node() => queue:queue({atom(), term()})}.
send_in_order(RemoteNode, ProcessName, Message, Backlogs) ->
    case maps:find(RemoteNode, Backlogs) of
        {ok, Queue} ->
            Backlogs#{RemoteNode := queue:in({ProcessName, Message}, Queue)};

        error ->
            case send_noconnect({ProcessName, RemoteNode}, Message) of
                nosuspend -> Backlogs#{RemoteNode => queue:from_list([{ProcessName, Message}])};
                _ -> Backlogs
            end
    end.

%% sends what each backlog can send without waiting
-spec send_backlogs(Backlogs :: #{node() => queue:queue({atom(), term()})}) ->
    #{node() => queue:queue({atom(), term()})}.
send_backlogs(Backlogs) ->
    maps:fold(fun(RemoteNode, Queue, Acc) ->
        case send_queue(RemoteNode, Queue) of
            empty -> maps:remove(RemoteNode, Acc);
            Queue1 -> Acc#{RemoteNode := Queue1}
        end
    end, Backlogs, Backlogs).

-spec send_queue(RemoteNode :: node(), queue:queue({atom(), term()})) -> empty | queue:queue({atom(), term()}).
send_queue(RemoteNode, Queue) ->
    case queue:out(Queue) of
        {empty, _} ->
            empty;

        {{value, {ProcessName, Message} = Item}, Rest} ->
            case send_noconnect({ProcessName, RemoteNode}, Message) of
                %% back in front of Rest, which keeps the work queue:out did, so a backlog that can't move costs
                %% the same to try again however long it is
                nosuspend -> queue:in_r(Item, Rest);
                _ -> send_queue(RemoteNode, Rest)
            end
    end.

%% syn never opens a connection: a message to a node that isn't connected is dropped, and that node gets the data again
%% when it connects. A connection too busy to take the message right away gives nosuspend, and the message isn't sent
-spec send_noconnect(Dest :: {atom(), node()}, Message :: term()) -> ok | noconnect | nosuspend.
send_noconnect(Dest, Message) ->
    erlang:send(Dest, Message, [noconnect, nosuspend]).
