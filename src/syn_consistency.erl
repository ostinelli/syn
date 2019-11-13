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
-module(syn_consistency).
-behaviour(gen_server).

%% API
-export([start_link/0]).
-export([resume_local_syn_registry/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% records
-record(state, {}).

%% includes
-include("syn_records.hrl").

%% ===================================================================
%% API
%% ===================================================================
-spec start_link() -> {ok, pid()} | {error, any()}.
start_link() ->
    Options = [],
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], Options).

-spec resume_local_syn_registry() -> ok.
resume_local_syn_registry() ->
    %% resume processes able to modify mnesia tables
    sys:resume(syn_registry).

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
    %% wait for table
    case mnesia:wait_for_tables([syn_registry_table], 10000) of
        ok ->
            {ok, #state{}};
        Reason ->
            {stop, {error_waiting_for_process_registry_table, Reason}}
    end.

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

handle_call(Request, From, State) ->
    error_logger:warning_msg("Received from ~p an unknown call message: ~p~n", [Request, From]),
    {reply, undefined, State}.

%% ----------------------------------------------------------------------------------------------------------
%% Cast messages
%% ----------------------------------------------------------------------------------------------------------
-spec handle_cast(Msg :: any(), #state{}) ->
    {noreply, #state{}} |
    {noreply, #state{}, Timeout :: non_neg_integer()} |
    {stop, Reason :: any(), #state{}}.

handle_cast(Msg, State) ->
    error_logger:warning_msg("Received an unknown cast message: ~p~n", [Msg]),
    {noreply, State}.

%% ----------------------------------------------------------------------------------------------------------
%% All non Call / Cast messages
%% ----------------------------------------------------------------------------------------------------------
-spec handle_info(Info :: any(), #state{}) ->
    {noreply, #state{}} |
    {noreply, #state{}, Timeout :: non_neg_integer()} |
    {stop, Reason :: any(), #state{}}.

handle_info({nodeup, RemoteNode}, State) ->
    error_logger:info_msg("Node ~p has joined the cluster of local node ~p~n", [RemoteNode, node()]),
    global:trans({{?MODULE, auto_merge_node_up}, self()},
        fun() ->
            error_logger:info_msg("Merge: ----> Initiating on ~p for remote node ~p~n", [node(), RemoteNode]),
            %% request remote node process info & suspend remote registry
            RegistryTuples = rpc:call(RemoteNode, syn_registry, get_local_registry_tuples_and_suspend, [node()]),
            sync_registry_tuples(RemoteNode, RegistryTuples),
            error_logger:error_msg("Merge: <---- Done on ~p for remote node ~p~n", [node(), RemoteNode])
        end
    ),
    %% resume remote processes able to modify tables
    ok = rpc:call(RemoteNode, sys, resume, [syn_registry]),
    %% resume
    {noreply, State};

handle_info({nodedown, RemoteNode}, State) ->
    error_logger:warning_msg("Node ~p has left the cluster of local node ~p~n", [RemoteNode, node()]),
    {noreply, State};


handle_info(Info, State) ->
    error_logger:warning_msg("Received an unknown info message: ~p~n", [Info]),
    {noreply, State}.

sync_registry_tuples(RemoteNode, RegistryTuples) ->
    %% ensure that registry doesn't have any joining node's entries
    purge_registry_entries_for_node(RemoteNode),
    %% loop
    F = fun({Name, RemotePid, _RemoteNode, RemoteMeta}) ->
        %% check if same name is registered
        case syn_registry:find_process_entry_by_name(Name) of
            undefined ->
                %% no conflict
                ok;
            Entry ->
                error_logger:warning_msg(
                    "Conflicting name process found for: ~p, processes are ~p, ~p, killing local~n",
                    [Name, Entry#syn_registry_table.pid, RemotePid]
                ),
                %% kill the local one
                exit(Entry#syn_registry_table.pid, kill)
        end,
        %% enqueue registration (to be done on syn_registry for monitor)
        syn_registry:sync_register(Name, RemotePid, RemoteMeta)
    end,
    %% add to table
    lists:foreach(F, RegistryTuples).

%% ----------------------------------------------------------------------------------------------------------
%% Terminate
%% ----------------------------------------------------------------------------------------------------------
-spec terminate(Reason :: any(), #state{}) -> terminated.
terminate(Reason, _State) ->
    error_logger:info_msg("Terminating with reason: ~p~n", [Reason]),
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
-spec purge_registry_entries_for_node(Node :: atom()) -> ok.
purge_registry_entries_for_node(Node) ->
    %% build match specs
    MatchHead = #syn_registry_table{name = '$1', node = '$2', _ = '_'},
    Guard = {'=:=', '$2', Node},
    IdFormat = '$1',
    %% delete
    NodePids = mnesia:dirty_select(syn_registry_table, [{MatchHead, [Guard], [IdFormat]}]),
    DelF = fun(Id) -> mnesia:dirty_delete({syn_registry_table, Id}) end,
    lists:foreach(DelF, NodePids).
