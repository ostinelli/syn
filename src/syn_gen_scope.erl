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
%% IMPLIED, INCLUDING BUT NOT LIMITED TO THxE WARRANTIES OF MERCHANTABILITY,
%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
%% THE SOFTWARE.
%% ==========================================================================================================
-module(syn_gen_scope).
-behaviour(gen_server).

%% API
-export([
    start_link/2,
    subcluster_nodes/2,
    call/3, call/4
]).
-export([
    broadcast/2, broadcast/3,
    broadcast_all_cluster/2,
    send_to_node/3
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
-export([multicast_loop/0]).

%% includes
-include("syn.hrl").

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
-callback save_remote_data(RemoteData :: term(), #state{}) -> any().
-callback get_local_data(#state{}) -> {ok, Data :: term()} | undefined.
-callback purge_local_data_for_node(Node :: node(), #state{}) -> any().

%% ===================================================================
%% API
%% ===================================================================
-spec start_link(Handler :: module(), Scope :: atom()) ->
    {ok, Pid :: pid()} | {error, {already_started, Pid :: pid()}} | {error, Reason :: term()}.
start_link(Handler, Scope) when is_atom(Scope) ->
    %% build name
    HandlerBin = atom_to_binary(Handler),
    ScopeBin = atom_to_binary(Scope),
    ProcessName = binary_to_atom(<<HandlerBin/binary, "_", ScopeBin/binary>>),
    %% save to lookup table
    syn_backbone:save_process_name({Handler, Scope}, ProcessName),
    %% create process
    gen_server:start_link({local, ProcessName}, ?MODULE, [Handler, Scope, ProcessName], []).

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
            catch exit:{noproc, {gen_server, call, _}} -> error({invalid_remote_scope, Scope})
            end
    end.

%% ===================================================================
%% In-Process API
%% ===================================================================
-spec broadcast(Message :: term(), #state{}) -> any().
broadcast(Message, State) ->
    broadcast(Message, [], State).

-spec broadcast(Message :: term(), ExcludedNodes :: [node()], #state{}) -> any().
broadcast(Message, ExcludedNodes, #state{multicast_pid = MulticastPid} = State) ->
    MulticastPid ! {broadcast, Message, ExcludedNodes, State}.

-spec broadcast_all_cluster(Message :: term(), #state{}) -> any().
broadcast_all_cluster(Message, #state{multicast_pid = MulticastPid} = State) ->
    MulticastPid ! {broadcast_all_cluster, Message, State}.

-spec send_to_node(RemoteNode :: node(), Message :: term(), #state{}) -> any().
send_to_node(RemoteNode, Message, #state{process_name = ProcessName}) ->
    {ProcessName, RemoteNode} ! Message.

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
init([Handler, Scope, ProcessName]) ->
    %% monitor nodes
    ok = net_kernel:monitor_nodes(true),
    %% start multicast process
    MulticastPid = spawn_link(?MODULE, multicast_loop, []),
    %% table names
    HandlerBin = atom_to_binary(Handler),
    TableByName = syn_backbone:get_table_name(binary_to_atom(<<HandlerBin/binary, "_by_name">>), Scope),
    TableByPid = syn_backbone:get_table_name(binary_to_atom(<<HandlerBin/binary, "_by_pid">>), Scope),
    %% build state
    State = #state{
        handler = Handler,
        scope = Scope,
        process_name = ProcessName,
        multicast_pid = MulticastPid,
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
handle_cast(Msg, #state{handler = Handler} = State) ->
    Handler:handle_cast(Msg, State).

%% ----------------------------------------------------------------------------------------------------------
%% Info messages
%% ----------------------------------------------------------------------------------------------------------
-spec handle_info(Info :: timeout | term(), #state{}) ->
    {noreply, #state{}} |
    {noreply, #state{}, timeout() | hibernate | {continue, term()}} |
    {stop, Reason :: term(), #state{}}.
handle_info({'3.0', discover, RemoteScopePid}, #state{
    handler = Handler,
    scope = Scope,
    nodes_map = NodesMap
} = State) ->
    RemoteScopeNode = node(RemoteScopePid),
    error_logger:info_msg("SYN[~s<~s>] Received DISCOVER request from node '~s'",
        [Handler, Scope, RemoteScopeNode]
    ),
    %% send local data to remote
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
    nodes_map = NodesMap,
    scope = Scope
} = State) ->
    RemoteScopeNode = node(RemoteScopePid),
    error_logger:info_msg("SYN[~s<~s>] Received ACK SYNC (~w entries) from node '~s'",
        [Handler, Scope, length(Data), RemoteScopeNode]
    ),
    %% save remote data
    Handler:save_remote_data(Data, State),
    %% is this a new node?
    case maps:is_key(RemoteScopeNode, NodesMap) of
        true ->
            %% already known
            {noreply, State};

        false ->
            %% monitor
            _MRef = monitor(process, RemoteScopePid),
            %% send local to remote
            {ok, LocalData} = Handler:get_local_data(State),
            send_to_node(RemoteScopeNode, {'3.0', ack_sync, self(), LocalData}, State),
            %% return
            {noreply, State#state{nodes_map = NodesMap#{RemoteScopeNode => RemoteScopePid}}}
    end;

handle_info({'DOWN', MRef, process, Pid, Reason}, #state{
    handler = Handler,
    scope = Scope,
    nodes_map = NodesMap
} = State) when node(Pid) =/= node() ->
    %% scope process down
    RemoteNode = node(Pid),
    case maps:take(RemoteNode, NodesMap) of
        {Pid, NodesMap1} ->
            error_logger:info_msg("SYN[~s<~s>] Scope Process is DOWN on node '~s': ~p",
                [Handler, Scope, RemoteNode, Reason]
            ),
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
    handler = Handler,
    scope = Scope
} = State) ->
    error_logger:info_msg("SYN[~s<~s>] Node '~s' has joined the cluster, sending discover message",
        [Handler, Scope, RemoteNode]
    ),
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
    handler = Handler,
    scope = Scope
} = State) ->
    error_logger:info_msg("SYN[~s<~s>] Discovering the cluster", [Handler, Scope]),
    broadcast_all_cluster({'3.0', discover, self()}, State),
    {noreply, State}.

%% ----------------------------------------------------------------------------------------------------------
%% Terminate
%% ----------------------------------------------------------------------------------------------------------
-spec terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()), #state{}) -> any().
terminate(Reason, #state{handler = Handler, scope = Scope}) ->
    error_logger:info_msg("SYN[~s<~s>] ~s terminating with reason: ~p", [Handler, Scope, Handler, Reason]).

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

-spec multicast_loop() -> terminated.
multicast_loop() ->
    receive
        {broadcast, Message, ExcludedNodes, #state{process_name = ProcessName, nodes_map = NodesMap}} ->
            lists:foreach(fun(RemoteNode) ->
                {ProcessName, RemoteNode} ! Message
            end, maps:keys(NodesMap) -- ExcludedNodes),
            multicast_loop();

        {broadcast_all_cluster, Message, #state{process_name = ProcessName}} ->
            lists:foreach(fun(RemoteNode) ->
                {ProcessName, RemoteNode} ! Message
            end, nodes()),
            multicast_loop();

        terminate ->
            terminated
    end.
