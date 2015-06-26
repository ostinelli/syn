%% ==========================================================================================================
%% Syn - A global process registry.
%%
%% Copyright (C) 2015, Roberto Ostinelli <roberto@ostinelli.net>.
%% All rights reserved.
%%
%% The MIT License (MIT)
%%
%% Copyright (c) 2015 Roberto Ostinelli
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
-module(syn_netsplits).
-behaviour(gen_server).

%% API
-export([start_link/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% internal
-export([get_processes_info_of_node/1]).
-export([write_processes_info_to_node/2]).

%% records
-record(state, {
    conflicting_process_callback_module = undefined :: atom(),
    conflicting_process_callback_function = undefined :: atom()
}).

%% include
-include("syn.hrl").


%% ===================================================================
%% API
%% ===================================================================
-spec start_link() -> {ok, pid()} | {error, any()}.
start_link() ->
    Options = [],
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], Options).

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
    %% monitor mnesia events
    mnesia:subscribe(system),
    %% get options
    {ok, [ConflictingProcessCallbackModule, ConflictingProcessCallbackFunction]} = syn_utils:get_env_value(
        conflicting_process_callback,
        [undefined, undefined]
    ),
    %% build state
    {ok, #state{
        conflicting_process_callback_module = ConflictingProcessCallbackModule,
        conflicting_process_callback_function = ConflictingProcessCallbackFunction
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

handle_info({mnesia_system_event, {inconsistent_database, Context, Node}}, #state{
    conflicting_process_callback_module = ConflictingProcessCallbackModule,
    conflicting_process_callback_function = ConflictingProcessCallbackFunction
} = State) ->
    error_logger:warning_msg("MNESIA signalled an inconsistent database on node: ~p with context: ~p, initiating automerge~n", [Node, Context]),
    automerge(Node, ConflictingProcessCallbackModule, ConflictingProcessCallbackFunction),
    {noreply, State};

handle_info({mnesia_system_event, {mnesia_down, Node}}, State) when Node =/= node() ->
    error_logger:warning_msg("Received a MNESIA down event, removing all pids of node ~p~n", [Node]),
    delete_pids_of_disconnected_node(Node),
    {noreply, State};

handle_info({mnesia_system_event, _MnesiaEvent}, State) ->
    %% ignore mnesia event
    {noreply, State};

handle_info(Info, State) ->
    error_logger:warning_msg("Received an unknown info message: ~p~n", [Info]),
    {noreply, State}.

%% ----------------------------------------------------------------------------------------------------------
%% Terminate
%% ----------------------------------------------------------------------------------------------------------
-spec terminate(Reason :: any(), #state{}) -> terminated.
terminate(Reason, _State) ->
    error_logger:info_msg("Terminating syn netsplits with reason: ~p~n", [Reason]),
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
-spec delete_pids_of_disconnected_node(Node :: atom()) -> pid().
delete_pids_of_disconnected_node(Node) ->
    %% don't lock gen server
    spawn(fun() ->
        %% build match specs
        MatchHead = #syn_processes_table{key = '$1', node = '$2', _ = '_'},
        Guard = {'=:=', '$2', Node},
        IdFormat = '$1',
        %% delete
        DelF = fun(Id) -> mnesia:dirty_delete({syn_processes_table, Id}) end,
        NodePids = mnesia:dirty_select(syn_processes_table, [{MatchHead, [Guard], [IdFormat]}]),
        lists:foreach(DelF, NodePids)
    end).

-spec automerge(RemoteNode :: atom(), CallbackModule :: atom(), CallbackFunction :: atom()) -> ok.
automerge(RemoteNode, CallbackModule, CallbackFunction) ->
    global:trans({{?MODULE, automerge}, self()},
        fun() ->
            error_logger:warning_msg("AUTOMERGE starting for remote node ~s (global lock is set)~n", [RemoteNode]),
            check_stitch(RemoteNode, CallbackModule, CallbackFunction),
            error_logger:warning_msg("AUTOMERGE done (global lock will be unset)~n")
        end).

-spec check_stitch(RemoteNode :: atom(), CallbackModule :: atom(), CallbackFunction :: atom()) -> ok.
check_stitch(RemoteNode, CallbackModule, CallbackFunction) ->
    case catch lists:member(RemoteNode, mnesia:system_info(running_db_nodes)) of
        true ->
            ok;
        false ->
            stitch(RemoteNode, CallbackModule, CallbackFunction),
            ok;
        Error ->
            error_logger:error_msg("Could not check if node is stiched: ~p~n", [Error])
    end.

-spec stitch(RemoteNode :: atom(), CallbackModule :: atom(), CallbackFunction :: atom()) ->
    {'ok', any()} | {'error', any()}.
stitch(RemoteNode, CallbackModule, CallbackFunction) ->
    mnesia_controller:connect_nodes(
        [RemoteNode],
        fun(MergeF) ->
            catch case MergeF([syn_processes_table]) of
                {merged, _, _} = Res ->
                    stitch_tab(RemoteNode, CallbackModule, CallbackFunction),
                    Res;
                Other ->
                    Other
            end
        end).

-spec stitch_tab(RemoteNode :: atom(), CallbackModule :: atom(), CallbackFunction :: atom()) -> ok.
stitch_tab(RemoteNode, CallbackModule, CallbackFunction) ->
    %% get remote processes info
    RemoteProcessesInfo = rpc:call(RemoteNode, ?MODULE, get_processes_info_of_node, [RemoteNode]),
    %% get local processes info
    LocalProcessesInfo = get_processes_info_of_node(node()),
    %% purge doubles (if any)
    {LocalProcessesInfo1, RemoteProcessesInfo1} = purge_double_processes_from_local_node(
        LocalProcessesInfo,
        RemoteProcessesInfo,
        CallbackModule,
        CallbackFunction
    ),
    %% write
    write_remote_processes_to_local(RemoteNode, RemoteProcessesInfo1),
    write_local_processes_to_remote(RemoteNode, LocalProcessesInfo1).

-spec purge_double_processes_from_local_node(
    LocalProcessesInfo :: list(),
    RemoteProcessesInfo :: list(),
    ConflictingMode :: kill | send_message,
    Message :: any()
) ->
    {LocalProcessesInfo :: list(), RemoteProcessesInfo :: list()}.
purge_double_processes_from_local_node(LocalProcessesInfo, RemoteProcessesInfo, CallbackModule, CallbackFunction) ->
    %% create ETS table
    Tab = ets:new(syn_automerge_doubles_table, [set]),

    %% insert local processes info
    ets:insert(Tab, LocalProcessesInfo),

    %% find doubles
    F = fun({Key, _RemoteProcessPid}) ->
        case ets:lookup(Tab, Key) of
            [] -> ok;
            [{Key, LocalProcessPid}] ->
                error_logger:warning_msg("Found a double process for ~s, killing it on local node~n", [Key]),
                %% remove it from local mnesia table
                mnesia:dirty_delete(syn_processes_table, Key),
                %% remove it from ETS
                ets:delete(Tab, Key),
                %% kill or send message
                case CallbackModule of
                    undefined -> exit(LocalProcessPid, kill);
                    _ -> spawn(fun() -> CallbackModule:CallbackFunction(Key, LocalProcessPid) end)
                end
        end
    end,
    lists:foreach(F, RemoteProcessesInfo),

    %% compute local processes without doubles
    LocalProcessesInfo1 = ets:tab2list(Tab),
    %% delete ETS table
    ets:delete(Tab),
    %% return
    {LocalProcessesInfo1, RemoteProcessesInfo}.

-spec write_remote_processes_to_local(RemoteNode :: atom(), RemoteProcessesInfo :: list()) -> ok.
write_remote_processes_to_local(RemoteNode, RemoteProcessesInfo) ->
    write_processes_info_to_node(RemoteNode, RemoteProcessesInfo).

-spec write_local_processes_to_remote(RemoteNode :: atom(), LocalProcessesInfo :: list()) -> ok.
write_local_processes_to_remote(RemoteNode, LocalProcessesInfo) ->
    ok = rpc:call(RemoteNode, ?MODULE, write_processes_info_to_node, [node(), LocalProcessesInfo]).

-spec get_processes_info_of_node(Node :: atom()) -> list().
get_processes_info_of_node(Node) ->
    %% build match specs
    MatchHead = #syn_processes_table{key = '$1', pid = '$2', node = '$3'},
    Guard = {'=:=', '$3', Node},
    ProcessInfoFormat = {{'$1', '$2'}},
    %% select
    mnesia:dirty_select(syn_processes_table, [{MatchHead, [Guard], [ProcessInfoFormat]}]).

-spec write_processes_info_to_node(Node :: atom(), ProcessesInfo :: list()) -> ok.
write_processes_info_to_node(Node, ProcessesInfo) ->
    FWrite = fun({Key, ProcessPid}) ->
        mnesia:dirty_write(#syn_processes_table{
            key = Key,
            pid = ProcessPid,
            node = Node
        })
    end,
    lists:foreach(FWrite, ProcessesInfo).
