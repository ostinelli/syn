%% ==========================================================================================================
%% Syn - A global process registry.
%%
%% The MIT License (MIT)
%%
%% Copyright (c) 2015 Roberto Ostinelli <roberto@ostinelli.net> and Neato Robotics, Inc.
%%
%% Portions of code from Ulf Wiger's unsplit server module:
%% <https://github.com/uwiger/unsplit/blob/master/src/unsplit_server.erl>
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

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% internal
-export([get_processes_info_of_node/1]).
-export([write_processes_info_to_node/2]).
-export([get_pgs_info_of_node/1]).
-export([write_pgs_info_to_node/2]).

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
    error_logger:warning_msg("Received from ~p an unknown call message: ~p", [Request, From]),
    {reply, undefined, State}.

%% ----------------------------------------------------------------------------------------------------------
%% Cast messages
%% ----------------------------------------------------------------------------------------------------------
-spec handle_cast(Msg :: any(), #state{}) ->
    {noreply, #state{}} |
    {noreply, #state{}, Timeout :: non_neg_integer()} |
    {stop, Reason :: any(), #state{}}.

handle_cast(Msg, State) ->
    error_logger:warning_msg("Received an unknown cast message: ~p", [Msg]),
    {noreply, State}.

%% ----------------------------------------------------------------------------------------------------------
%% All non Call / Cast messages
%% ----------------------------------------------------------------------------------------------------------
-spec handle_info(Info :: any(), #state{}) ->
    {noreply, #state{}} |
    {noreply, #state{}, Timeout :: non_neg_integer()} |
    {stop, Reason :: any(), #state{}}.

handle_info({mnesia_system_event, {inconsistent_database, Context, RemoteNode}}, State) ->
    error_logger:error_msg("MNESIA signalled an inconsistent database on node ~p for remote node ~p with context: ~p, initiating automerge", [node(), RemoteNode, Context]),
    automerge(RemoteNode),
    {noreply, State};

handle_info({mnesia_system_event, {mnesia_down, RemoteNode}}, State) when RemoteNode =/= node() ->
    error_logger:error_msg("Received a MNESIA down event, removing on node ~p all pids of node ~p", [node(), RemoteNode]),
    delete_global_pids_of_disconnected_node(RemoteNode),
    delete_pg_pids_of_disconnected_node(RemoteNode),
    {noreply, State};

handle_info({mnesia_system_event, _MnesiaEvent}, State) ->
    %% ignore mnesia event
    {noreply, State};

handle_info({purge_double_processes, DoubleProcessesInfo}, #state{
    conflicting_process_callback_module = ConflictingProcessCallbackModule,
    conflicting_process_callback_function = ConflictingProcessCallbackFunction
} = State) ->
    error_logger:warning_msg("About to purge double processes after netsplit"),
    purge_double_processes(ConflictingProcessCallbackModule, ConflictingProcessCallbackFunction, DoubleProcessesInfo),
    {noreply, State};

handle_info(Info, State) ->
    error_logger:warning_msg("Received an unknown info message: ~p", [Info]),
    {noreply, State}.

%% ----------------------------------------------------------------------------------------------------------
%% Terminate
%% ----------------------------------------------------------------------------------------------------------
-spec terminate(Reason :: any(), #state{}) -> terminated.
terminate(Reason, _State) ->
    error_logger:info_msg("Terminating syn consistency with reason: ~p", [Reason]),
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
-spec delete_global_pids_of_disconnected_node(RemoteNode :: atom()) -> ok.
delete_global_pids_of_disconnected_node(RemoteNode) ->
    %% build match specs
    MatchHead = #syn_global_table{key = '$1', node = '$2', _ = '_'},
    Guard = {'=:=', '$2', RemoteNode},
    IdFormat = '$1',
    %% delete
    DelF = fun(Id) -> mnesia:dirty_delete({syn_global_table, Id}) end,
    NodePids = mnesia:dirty_select(syn_global_table, [{MatchHead, [Guard], [IdFormat]}]),
    lists:foreach(DelF, NodePids).

-spec delete_pg_pids_of_disconnected_node(RemoteNode :: atom()) -> ok.
delete_pg_pids_of_disconnected_node(RemoteNode) ->
    %% build match specs
    Pattern = #syn_pg_table{node = RemoteNode, _ = '_'},
    ObjectsToDelete = mnesia:dirty_match_object(syn_pg_table, Pattern),
    %% delete
    DelF = fun(Record) -> mnesia:dirty_delete_object(syn_pg_table, Record) end,
    lists:foreach(DelF, ObjectsToDelete).

-spec automerge(RemoteNode :: atom()) -> ok.
automerge(RemoteNode) ->
    global:trans({{?MODULE, automerge}, self()},
        fun() ->
            error_logger:warning_msg("AUTOMERGE starting on node ~p for remote node ~p (global lock is set)", [node(), RemoteNode]),
            check_stitch(RemoteNode),
            error_logger:warning_msg("AUTOMERGE done (global lock about to be unset)")
        end).

-spec check_stitch(RemoteNode :: atom()) -> ok.
check_stitch(RemoteNode) ->
    case catch lists:member(RemoteNode, mnesia:system_info(running_db_nodes)) of
        true ->
            error_logger:warning_msg("Remote node ~p is already stitched.", [RemoteNode]),
            ok;
        false ->
            catch stitch(RemoteNode),
            ok;
        Error ->
            error_logger:error_msg("Could not check if node is stiched: ~p", [Error]),
            ok
    end.

-spec stitch(RemoteNode :: atom()) -> {ok, any()} | {error, any()}.
stitch(RemoteNode) ->
    mnesia_controller:connect_nodes(
        [RemoteNode],
        fun(MergeF) ->
            catch case MergeF([syn_global_table, syn_pg_table]) of
                {merged, _, _} = Res ->
                    stitch_global_tab(RemoteNode),
                    stitch_pg_tab(RemoteNode),
                    Res;
                Other ->
                    Other
            end
        end).

-spec stitch_global_tab(RemoteNode :: atom()) -> ok.
stitch_global_tab(RemoteNode) ->
    %% get remote processes info
    RemoteProcessesInfo = rpc:call(RemoteNode, ?MODULE, get_processes_info_of_node, [RemoteNode]),
    %% get local processes info
    LocalProcessesInfo = get_processes_info_of_node(node()),
    %% purge doubles (if any)
    {LocalProcessesInfo1, RemoteProcessesInfo1} = purge_double_processes_from_local_mnesia(
        LocalProcessesInfo,
        RemoteProcessesInfo
    ),
    %% write
    write_remote_processes_to_local(RemoteNode, RemoteProcessesInfo1),
    write_local_processes_to_remote(RemoteNode, LocalProcessesInfo1).

-spec purge_double_processes_from_local_mnesia(
    LocalProcessesInfo :: list(),
    RemoteProcessesInfo :: list()
) ->
    {LocalProcessesInfo :: list(), RemoteProcessesInfo :: list()}.
purge_double_processes_from_local_mnesia(LocalProcessesInfo, RemoteProcessesInfo) ->
    %% create ETS table
    Tab = ets:new(syn_automerge_doubles_table, [set]),

    %% insert local processes info
    ets:insert(Tab, LocalProcessesInfo),

    %% find doubles
    F = fun({Key, _RemoteProcessPid, _RemoteProcessMeta}, Acc) ->
        case ets:lookup(Tab, Key) of
            [] -> Acc;
            [{Key, LocalProcessPid, LocalProcessMeta}] ->
                %% found a double process, remove it from local mnesia table
                mnesia:dirty_delete(syn_global_table, Key),
                %% remove it from ETS
                ets:delete(Tab, Key),
                %% add it to acc
                [{Key, LocalProcessPid, LocalProcessMeta} | Acc]
        end
    end,
    DoubleProcessesInfo = lists:foldl(F, [], RemoteProcessesInfo),

    %% send to syn_consistency gen_server to handle double processes once merging is done
    ?MODULE ! {purge_double_processes, DoubleProcessesInfo},

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
    MatchHead = #syn_global_table{key = '$1', pid = '$2', node = '$3', meta = '$4'},
    Guard = {'=:=', '$3', Node},
    ProcessInfoFormat = {{'$1', '$2', '$4'}},
    %% select
    mnesia:dirty_select(syn_global_table, [{MatchHead, [Guard], [ProcessInfoFormat]}]).

-spec write_processes_info_to_node(Node :: atom(), ProcessesInfo :: list()) -> ok.
write_processes_info_to_node(Node, ProcessesInfo) ->
    FWrite = fun({Key, ProcessPid, ProcessMeta}) ->
        mnesia:dirty_write(#syn_global_table{
            key = Key,
            pid = ProcessPid,
            node = Node,
            meta = ProcessMeta
        })
    end,
    lists:foreach(FWrite, ProcessesInfo).

-spec purge_double_processes(
    ConflictingProcessCallbackModule :: atom(),
    ConflictingProcessCallbackFunction :: atom(),
    DoubleProcessesInfo :: list()
) -> ok.
purge_double_processes(undefined, _, DoubleProcessesInfo) ->
    F = fun({Key, LocalProcessPid, _LocalProcessMeta}) ->
        error_logger:warning_msg("Found a double process for ~s, killing it on local node ~p", [Key, node()]),
        exit(LocalProcessPid, kill)
    end,
    lists:foreach(F, DoubleProcessesInfo);
purge_double_processes(ConflictingProcessCallbackModule, ConflictingProcessCallbackFunction, DoubleProcessesInfo) ->
    F = fun({Key, LocalProcessPid, LocalProcessMeta}) ->
        spawn(
            fun() ->
                error_logger:warning_msg("Found a double process for ~s, about to trigger callback on local node ~p", [Key, node()]),
                ConflictingProcessCallbackModule:ConflictingProcessCallbackFunction(Key, LocalProcessPid, LocalProcessMeta)
            end)
    end,
    lists:foreach(F, DoubleProcessesInfo).

-spec stitch_pg_tab(RemoteNode :: atom()) -> ok.
stitch_pg_tab(RemoteNode) ->
    %% get remote processes info
    RemotePgsInfo = rpc:call(RemoteNode, ?MODULE, get_pgs_info_of_node, [RemoteNode]),
    %% get local processes info
    LocalPgsInfo = get_pgs_info_of_node(node()),
    %% write
    write_remote_pgs_to_local(RemoteNode, RemotePgsInfo),
    write_local_pgs_to_remote(RemoteNode, LocalPgsInfo).

-spec get_pgs_info_of_node(Node :: atom()) -> list().
get_pgs_info_of_node(Node) ->
    %% build match specs
    MatchHead = #syn_pg_table{name = '$1', pid = '$2', node = '$3'},
    Guard = {'=:=', '$3', Node},
    PgInfoFormat = {{'$1', '$2'}},
    %% select
    mnesia:dirty_select(syn_pg_table, [{MatchHead, [Guard], [PgInfoFormat]}]).

-spec write_remote_pgs_to_local(RemoteNode :: atom(), RemotePgsInfo :: list()) -> ok.
write_remote_pgs_to_local(RemoteNode, RemotePgsInfo) ->
    write_pgs_info_to_node(RemoteNode, RemotePgsInfo).

-spec write_local_pgs_to_remote(RemoteNode :: atom(), LocalPgsInfo :: list()) -> ok.
write_local_pgs_to_remote(RemoteNode, LocalPgsInfo) ->
    ok = rpc:call(RemoteNode, ?MODULE, write_pgs_info_to_node, [node(), LocalPgsInfo]).

-spec write_pgs_info_to_node(Node :: atom(), PgsInfo :: list()) -> ok.
write_pgs_info_to_node(Node, PgsInfo) ->
    FWrite = fun({Name, Pid}) ->
        mnesia:dirty_write(#syn_pg_table{
            name = Name,
            pid = Pid,
            node = Node
        })
    end,
    lists:foreach(FWrite, PgsInfo).
