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

%% Cluster API
-export([announce/2]).
-export([sync/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

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
    ProcessName = get_process_name_for(Scope),
    Args = [Scope, ProcessName],
    gen_server:start_link({local, ProcessName}, ?MODULE, Args, []).

-spec get_subcluster_nodes(Scope :: atom()) -> [node()].
get_subcluster_nodes(Scope) ->
    ProcessName = get_process_name_for(Scope),
    gen_server:call(ProcessName, get_subcluster_nodes).

%% ===================================================================
%% Cluster API
%% ===================================================================
announce(RemoteNode, ProcessName) ->
    gen_server:cast({ProcessName, RemoteNode}, {announce, self()}).

sync(RemoteNode, ProcessName) ->
    gen_server:cast({ProcessName, RemoteNode}, {sync, self(), []}).

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
handle_cast({announce, RemoteScopePid}, #state{
    scope = Scope,
    process_name = ProcessName,
    nodes = Nodes
} = State) ->
    RemoteScopeNode = node(RemoteScopePid),
    error_logger:info_msg("SYN[~p] Received announce request from node ~p and scope ~p~n", [node(), RemoteScopeNode, Scope]),
    %% send data
    sync(RemoteScopeNode, ProcessName),
    %% is this a new node?
    case maps:is_key(RemoteScopeNode, Nodes) of
        true ->
            %% already known, ignore
            {noreply, State};

        false ->
            %% monitor & announce
            _MRef = monitor(process, RemoteScopePid),
            announce(RemoteScopeNode, ProcessName),
            {noreply, State#state{nodes = Nodes#{RemoteScopeNode => RemoteScopePid}}}
    end;

handle_cast({sync, RemoteScopePid, _Data}, #state{
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
    scope = Scope,
    process_name = ProcessName
} = State) ->
    error_logger:info_msg("SYN[~p] Announcing to all nodes in the cluster with scope: ~p~n", [node(), Scope]),
    lists:foreach(fun(RemoteNode) -> announce(RemoteNode, ProcessName) end, nodes()),
    {noreply, State};

handle_info({'DOWN', _MRef, process, Pid, _Reason}, #state{
    scope = Scope,
    nodes = Nodes
} = State) ->
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

handle_info({nodedown, _Node}, State) ->
    %% ignore & wait for monitor DOWN message
    {noreply, State};

handle_info({nodeup, RemoteNode}, #state{process_name = ProcessName} = State) ->
    error_logger:info_msg("SYN[~p] Node ~p has joined the cluster, sending announce message~n", [node(), RemoteNode]),
    announce(RemoteNode, ProcessName),
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
-spec get_process_name_for(Scope :: atom()) -> atom().
get_process_name_for(Scope) ->
    ModuleBin = atom_to_binary(?MODULE),
    ScopeBin = atom_to_binary(Scope),
    binary_to_atom(<<ModuleBin/binary, "_", ScopeBin/binary>>).
