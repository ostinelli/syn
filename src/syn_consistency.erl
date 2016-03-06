%% ==========================================================================================================
%% Syn - A global Process Registry and Process Group manager.
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
-export([get_registry_processes_info_of_node/1]).
-export([write_registry_processes_info_to_node/2]).
-export([get_groups_processes_info_of_node/1]).
-export([write_groups_processes_info_to_node/2]).

%% records
-record(state, {
    registry_conflicting_process_callback_module = undefined :: atom(),
    registry_conflicting_process_callback_function = undefined :: atom()
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
    {ok, [RegistryConflictingProcessCallbackModule, RegistryConflictingProcessCallbackFunction]} = syn_utils:get_env_value(
        registry_conflicting_process_callback,
        [undefined, undefined]
    ),
    %% build state
    {ok, #state{
        registry_conflicting_process_callback_module = RegistryConflictingProcessCallbackModule,
        registry_conflicting_process_callback_function = RegistryConflictingProcessCallbackFunction
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
    delete_registry_pids_of_disconnected_node(RemoteNode),
    delete_groups_pids_of_disconnected_node(RemoteNode),
    {noreply, State};

handle_info({mnesia_system_event, _MnesiaEvent}, State) ->
    %% ignore mnesia event
    {noreply, State};

handle_info({purge_registry_double_processes, DoubleRegistryProcessesInfo}, #state{
    registry_conflicting_process_callback_module = RegistryConflictingProcessCallbackModule,
    registry_conflicting_process_callback_function = RegistryConflictingProcessCallbackFunction
} = State) ->
    error_logger:warning_msg("About to purge double processes after netsplit"),
    purge_registry_double_processes(RegistryConflictingProcessCallbackModule, RegistryConflictingProcessCallbackFunction, DoubleRegistryProcessesInfo),
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
-spec delete_registry_pids_of_disconnected_node(RemoteNode :: atom()) -> ok.
delete_registry_pids_of_disconnected_node(RemoteNode) ->
    %% build match specs
    MatchHead = #syn_registry_table{key = '$1', node = '$2', _ = '_'},
    Guard = {'=:=', '$2', RemoteNode},
    IdFormat = '$1',
    %% delete
    DelF = fun(Id) -> mnesia:dirty_delete({syn_registry_table, Id}) end,
    NodePids = mnesia:dirty_select(syn_registry_table, [{MatchHead, [Guard], [IdFormat]}]),
    lists:foreach(DelF, NodePids).

-spec delete_groups_pids_of_disconnected_node(RemoteNode :: atom()) -> ok.
delete_groups_pids_of_disconnected_node(RemoteNode) ->
    %% build match specs
    Pattern = #syn_groups_table{node = RemoteNode, _ = '_'},
    ObjectsToDelete = mnesia:dirty_match_object(syn_groups_table, Pattern),
    %% delete
    DelF = fun(Record) -> mnesia:dirty_delete_object(syn_groups_table, Record) end,
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
            catch case MergeF([syn_registry_table, syn_groups_table]) of
                {merged, _, _} = Res ->
                    stitch_registry_tab(RemoteNode),
                    stitch_group_tab(RemoteNode),
                    Res;
                Other ->
                    Other
            end
        end).

-spec stitch_registry_tab(RemoteNode :: atom()) -> ok.
stitch_registry_tab(RemoteNode) ->
    %% get remote processes info
    RemoteRegistryProcessesInfo = rpc:call(RemoteNode, ?MODULE, get_registry_processes_info_of_node, [RemoteNode]),
    %% get local processes info
    LocalRegistryProcessesInfo = get_registry_processes_info_of_node(node()),
    %% purge doubles (if any)
    {LocalRegistryProcessesInfo1, RemoteRegistryProcessesInfo1} = purge_registry_double_processes_from_local_mnesia(
        LocalRegistryProcessesInfo,
        RemoteRegistryProcessesInfo
    ),
    %% write
    write_remote_registry_processes_to_local(RemoteNode, RemoteRegistryProcessesInfo1),
    write_local_registry_processes_to_remote(RemoteNode, LocalRegistryProcessesInfo1).

-spec purge_registry_double_processes_from_local_mnesia(
    LocalRegistryProcessesInfo :: list(),
    RemoteRegistryProcessesInfo :: list()
) ->
    {LocalRegistryProcessesInfo :: list(), RemoteRegistryProcessesInfo :: list()}.
purge_registry_double_processes_from_local_mnesia(LocalRegistryProcessesInfo, RemoteRegistryProcessesInfo) ->
    %% create ETS table
    Tab = ets:new(syn_automerge_doubles_table, [set]),

    %% insert local processes info
    ets:insert(Tab, LocalRegistryProcessesInfo),

    %% find doubles
    F = fun({Key, _RemoteProcessPid, _RemoteProcessMeta}, Acc) ->
        case ets:lookup(Tab, Key) of
            [] -> Acc;
            [{Key, LocalProcessPid, LocalProcessMeta}] ->
                %% found a double process, remove it from local mnesia table
                mnesia:dirty_delete(syn_registry_table, Key),
                %% remove it from ETS
                ets:delete(Tab, Key),
                %% add it to acc
                [{Key, LocalProcessPid, LocalProcessMeta} | Acc]
        end
    end,
    DoubleRegistryProcessesInfo = lists:foldl(F, [], RemoteRegistryProcessesInfo),

    %% send to syn_consistency gen_server to handle double processes once merging is done
    ?MODULE ! {purge_registry_double_processes, DoubleRegistryProcessesInfo},

    %% compute local processes without doubles
    LocalRegistryProcessesInfo1 = ets:tab2list(Tab),
    %% delete ETS table
    ets:delete(Tab),
    %% return
    {LocalRegistryProcessesInfo1, RemoteRegistryProcessesInfo}.

-spec write_remote_registry_processes_to_local(RemoteNode :: atom(), RemoteRegistryProcessesInfo :: list()) -> ok.
write_remote_registry_processes_to_local(RemoteNode, RemoteRegistryProcessesInfo) ->
    write_registry_processes_info_to_node(RemoteNode, RemoteRegistryProcessesInfo).

-spec write_local_registry_processes_to_remote(RemoteNode :: atom(), LocalRegistryProcessesInfo :: list()) -> ok.
write_local_registry_processes_to_remote(RemoteNode, LocalRegistryProcessesInfo) ->
    ok = rpc:call(RemoteNode, ?MODULE, write_registry_processes_info_to_node, [node(), LocalRegistryProcessesInfo]).

-spec get_registry_processes_info_of_node(Node :: atom()) -> list().
get_registry_processes_info_of_node(Node) ->
    %% build match specs
    MatchHead = #syn_registry_table{key = '$1', pid = '$2', node = '$3', meta = '$4'},
    Guard = {'=:=', '$3', Node},
    ProcessInfoFormat = {{'$1', '$2', '$4'}},
    %% select
    mnesia:dirty_select(syn_registry_table, [{MatchHead, [Guard], [ProcessInfoFormat]}]).

-spec write_registry_processes_info_to_node(Node :: atom(), RegistryProcessesInfo :: list()) -> ok.
write_registry_processes_info_to_node(Node, RegistryProcessesInfo) ->
    FWrite = fun({Key, ProcessPid, ProcessMeta}) ->
        mnesia:dirty_write(#syn_registry_table{
            key = Key,
            pid = ProcessPid,
            node = Node,
            meta = ProcessMeta
        })
    end,
    lists:foreach(FWrite, RegistryProcessesInfo).

-spec purge_registry_double_processes(
    RegistryConflictingProcessCallbackModule :: atom(),
    RegistryConflictingProcessCallbackFunction :: atom(),
    DoubleRegistryProcessesInfo :: list()
) -> ok.
purge_registry_double_processes(undefined, _, DoubleRegistryProcessesInfo) ->
    F = fun({Key, LocalProcessPid, _LocalProcessMeta}) ->
        error_logger:warning_msg("Found a double process for ~s, killing it on local node ~p", [Key, node()]),
        exit(LocalProcessPid, kill)
    end,
    lists:foreach(F, DoubleRegistryProcessesInfo);
purge_registry_double_processes(RegistryConflictingProcessCallbackModule, RegistryConflictingProcessCallbackFunction, DoubleRegistryProcessesInfo) ->
    F = fun({Key, LocalProcessPid, LocalProcessMeta}) ->
        spawn(
            fun() ->
                error_logger:warning_msg("Found a double process for ~s, about to trigger callback on local node ~p", [Key, node()]),
                RegistryConflictingProcessCallbackModule:RegistryConflictingProcessCallbackFunction(Key, LocalProcessPid, LocalProcessMeta)
            end)
    end,
    lists:foreach(F, DoubleRegistryProcessesInfo).

-spec stitch_group_tab(RemoteNode :: atom()) -> ok.
stitch_group_tab(RemoteNode) ->
    %% get remote processes info
    RemoteGroupsRegistryProcessesInfo = rpc:call(RemoteNode, ?MODULE, get_groups_processes_info_of_node, [RemoteNode]),
    %% get local processes info
    LocalGroupsRegistryProcessesInfo = get_groups_processes_info_of_node(node()),
    %% write
    write_remote_groups_processes_info_to_local(RemoteNode, RemoteGroupsRegistryProcessesInfo),
    write_local_groups_processes_info_to_remote(RemoteNode, LocalGroupsRegistryProcessesInfo).

-spec get_groups_processes_info_of_node(Node :: atom()) -> list().
get_groups_processes_info_of_node(Node) ->
    %% build match specs
    MatchHead = #syn_groups_table{name = '$1', pid = '$2', node = '$3'},
    Guard = {'=:=', '$3', Node},
    GroupInfoFormat = {{'$1', '$2'}},
    %% select
    mnesia:dirty_select(syn_groups_table, [{MatchHead, [Guard], [GroupInfoFormat]}]).

-spec write_remote_groups_processes_info_to_local(RemoteNode :: atom(), RemoteGroupsRegistryProcessesInfo :: list()) -> ok.
write_remote_groups_processes_info_to_local(RemoteNode, RemoteGroupsRegistryProcessesInfo) ->
    write_groups_processes_info_to_node(RemoteNode, RemoteGroupsRegistryProcessesInfo).

-spec write_local_groups_processes_info_to_remote(RemoteNode :: atom(), LocalGroupsRegistryProcessesInfo :: list()) -> ok.
write_local_groups_processes_info_to_remote(RemoteNode, LocalGroupsRegistryProcessesInfo) ->
    ok = rpc:call(RemoteNode, ?MODULE, write_groups_processes_info_to_node, [node(), LocalGroupsRegistryProcessesInfo]).

-spec write_groups_processes_info_to_node(Node :: atom(), GroupsRegistryProcessesInfo :: list()) -> ok.
write_groups_processes_info_to_node(Node, GroupsRegistryProcessesInfo) ->
    FWrite = fun({Name, Pid}) ->
        mnesia:dirty_write(#syn_groups_table{
            name = Name,
            pid = Pid,
            node = Node
        })
    end,
    lists:foreach(FWrite, GroupsRegistryProcessesInfo).
