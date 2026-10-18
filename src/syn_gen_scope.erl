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
    call/3, call/4,
    call_ordered/4,
    reply_ordered/2
]).
-export([
    broadcast/2,
    broadcast/3,
    send_to_node/3,
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
-export_type([requester/0]).

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
-callback get_local_data(#state{}) -> {ok, Data :: term()} | undefined.
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
        ProcessName -> gen_server:call(ProcessName, {'3.0', subcluster_nodes})
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

%% a call for a process on another node, whose result the local scope process applies in order with everything else
%% that node sends it, see send_ordered_result/5: undefined if that node runs a version that doesn't know the call
-spec call_ordered(Handler :: module(), Node :: atom(), Scope :: atom(), Message :: tuple()) -> Response :: term().
call_ordered(Handler, Node, Scope, Message) ->
    case get_process_name_for_scope(Handler, Scope) of
        undefined ->
            error({invalid_scope, Scope});

        ProcessName ->
            case syn_backbone:is_legacy_node(Node) of
                true ->
                    undefined;

                false ->
                    %% a scope process can't wait for one, itself included: it gets the reply right away,
                    %% and the local scope process applies the result when it gets to it
                    ReplyWhen = case is_scope_process() of
                        true -> handled;
                        false -> applied
                    end,
                    Requester = {node(), whereis(ProcessName), ReplyWhen},
                    case call(Handler, Node, Scope, erlang:append_element(Message, Requester)) of
                        undefined ->
                            %% that node logs the unknown call, ask it only once
                            syn_backbone:save_legacy_node(Node),
                            undefined;

                        Response ->
                            Response
                    end
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
    SenderPid ! {broadcast, Message, ExcludedNodes, ProcessName, NodesMap}.

-spec send_to_node(RemoteNode :: node(), Message :: term(), #state{}) -> any().
send_to_node(RemoteNode, Message, #state{sender_pid = SenderPid, process_name = ProcessName}) ->
    SenderPid ! {send_single, RemoteNode, Message, ProcessName}.

%% an ordered call from a node this scope process doesn't know yet: that node gets the local data first, as for
%% a discover, so that it knows this node when the result reaches it
-spec discover_requester(Requester :: requester(), #state{}) -> {RequesterNode :: node(), #state{}}.
discover_requester({RequesterNode, RequesterScopePid, _}, #state{
    handler = Handler,
    nodes_map = NodesMap
} = State) ->
    case is_pid(RequesterScopePid) andalso not maps:is_key(RequesterNode, NodesMap) of
        true ->
            {ok, LocalData} = Handler:get_local_data(State),
            send_to_node(RequesterNode, {'3.0', ack_sync, self(), LocalData}, State),
            _MRef = monitor(process, RequesterScopePid),
            {RequesterNode, State#state{nodes_map = NodesMap#{RequesterNode => RequesterScopePid}}};

        false ->
            {RequesterNode, State}
    end.

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
handle_call({'3.0', subcluster_nodes}, _From, #state{
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
handle_info({'3.0', discover, RemoteScopePid}, #state{
    handler = Handler,
    handler_log_name = HandlerLogName,
    scope = Scope,
    nodes_map = NodesMap
} = State) ->
    RemoteScopeNode = node(RemoteScopePid),
    ?LOG_NOTICE(#{handler => HandlerLogName, scope => Scope,
                 event => discover_request, from => RemoteScopeNode}),
    %% send local data to remote (ordered to maintain FIFO with broadcasts)
    {ok, LocalData} = Handler:get_local_data(State),
    send_to_node(RemoteScopeNode, {'3.0', ack_sync, self(), LocalData}, State),
    %% is this a new node?
    case maps:is_key(RemoteScopeNode, NodesMap) of
        true ->
            %% already known, ignore
            {noreply, State};

        false ->
            %% monitor
            _MRef = monitor(process, RemoteScopePid),
            {noreply, State#state{nodes_map = NodesMap#{RemoteScopeNode => RemoteScopePid}}}
    end;

handle_info({'3.0', ack_sync, RemoteScopePid, Data}, #state{
    handler = Handler,
    handler_log_name = HandlerLogName,
    nodes_map = NodesMap,
    scope = Scope
} = State) ->
    RemoteScopeNode = node(RemoteScopePid),
    ?LOG_NOTICE(#{handler => HandlerLogName, scope => Scope,
                 event => ack_sync, from => RemoteScopeNode, entries => length(Data)}),
    %% is this a new node?
    case maps:is_key(RemoteScopeNode, NodesMap) of
        true ->
            %% already known, save remote data
            Handler:save_remote_data(RemoteScopeNode, Data, State),
            {noreply, State};

        false ->
            %% monitor
            _MRef = monitor(process, RemoteScopePid),
            State1 = State#state{nodes_map = NodesMap#{RemoteScopeNode => RemoteScopePid}},
            %% add to subcluster and send local data to remote before saving remote data,
            %% so that the snapshot keeps the entries a conflict resolution may remove
            %% and the broadcasts of the resolution reach the remote node after it (FIFO)
            {ok, LocalData} = Handler:get_local_data(State1),
            send_to_node(RemoteScopeNode, {'3.0', ack_sync, self(), LocalData}, State1),
            %% save remote data
            Handler:save_remote_data(RemoteScopeNode, Data, State1),
            %% return
            {noreply, State1}
    end;

handle_info({'DOWN', MRef, process, Pid, Reason}, #state{
    handler = Handler,
    handler_log_name = HandlerLogName,
    scope = Scope,
    nodes_map = NodesMap
} = State) when node(Pid) =/= node() ->
    %% scope process down
    RemoteNode = node(Pid),
    case maps:take(RemoteNode, NodesMap) of
        {Pid, NodesMap1} ->
            ?LOG_NOTICE(#{handler => HandlerLogName, scope => Scope,
                         event => scope_down, from => RemoteNode, reason => Reason}),
            Handler:purge_local_data_for_node(RemoteNode, State),
            {noreply, State#state{nodes_map = NodesMap1}};

        error ->
            %% relay to handler
            Handler:handle_info({'DOWN', MRef, process, Pid, Reason}, State)
    end;

handle_info({nodedown, _Node}, State) ->
    %% ignore & wait for monitor DOWN message
    {noreply, State};

handle_info({nodeup, RemoteNode}, #state{
    handler_log_name = HandlerLogName,
    scope = Scope
} = State) ->
    ?LOG_NOTICE(#{handler => HandlerLogName, scope => Scope,
                 event => nodeup, from => RemoteNode}),
    send_to_node(RemoteNode, {'3.0', discover, self()}, State),
    {noreply, State};

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
    scope = Scope,
    process_name = ProcessName
} = State) ->
    ?LOG_NOTICE(#{handler => HandlerLogName, scope => Scope,
                 event => discovering_cluster}),
    %% broadcasting is done in the scope process to avoid issues with ordering guarantees
    lists:foreach(fun(RemoteNode) ->
        {ProcessName, RemoteNode} ! {'3.0', discover, self()}
    end, nodes()),
    {noreply, State}.

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

-spec sender_loop() -> terminated.
sender_loop() ->
    receive
        {broadcast, Message, ExcludedNodes, ProcessName, NodesMap} ->
            lists:foreach(fun(RemoteNode) ->
                {ProcessName, RemoteNode} ! Message
            end, maps:keys(NodesMap) -- ExcludedNodes),
            sender_loop();

        {send_single, RemoteNode, Message, ProcessName} ->
            {ProcessName, RemoteNode} ! Message,
            sender_loop();

        terminate ->
            terminated
    end.
