%% ==========================================================================================================
%% Syn - A global Process Registry and Process Group manager.
%%
%% The MIT License (MIT)
%%
%% Copyright (c) 2016 Roberto Ostinelli <roberto@ostinelli.net> and Neato Robotics, Inc.
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
-module(syn_groups).
-behaviour(gen_server).

%% API
-export([start_link/0]).
-export([join/2, join/3]).
-export([leave/2]).
-export([member/2]).
-export([get_members/1, get_members/2]).
-export([get_local_members/1, get_local_members/2]).
-export([publish/2]).
-export([publish_to_local/2]).
-export([multi_call/2, multi_call/3]).
-export([multi_call_reply/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% internal
-export([multi_call_and_receive/4]).

%% records
-record(state, {
    process_groups_process_exit_callback_module = undefined :: atom(),
    process_groups_process_exit_callback_function = undefined :: atom()
}).

%% macros
-define(DEFAULT_MULTI_CALL_TIMEOUT_MS, 5000).

%% include
-include("syn.hrl").


%% ===================================================================
%% API
%% ===================================================================
-spec start_link() -> {ok, pid()} | {error, any()}.
start_link() ->
    Options = [],
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], Options).

-spec join(Name :: any(), Pid :: pid()) -> ok.
join(Name, Pid) ->
    join(Name, Pid, undefined).

-spec join(Name :: any(), Pid :: pid(), Meta :: any()) -> ok.
join(Name, Pid, Meta) when is_pid(Pid) ->
    Node = node(Pid),
    gen_server:call({?MODULE, Node}, {join, Name, Pid, Meta}).

-spec leave(Name :: any(), Pid :: pid()) -> ok | {error, pid_not_in_group}.
leave(Name, Pid) when is_pid(Pid) ->
    Node = node(Pid),
    gen_server:call({?MODULE, Node}, {leave, Name, Pid}).

-spec member(Pid :: pid(), Name :: any()) -> boolean().
member(Pid, Name) when is_pid(Pid) ->
    i_member(Pid, Name).

-spec get_members(Name :: any()) -> [pid()].
get_members(Name) ->
    i_get_members(Name).

-spec get_members(Name :: any(), with_meta) -> [{pid(), Meta :: any()}].
get_members(Name, with_meta) ->
    i_get_members(Name, with_meta).

-spec get_local_members(Name :: any()) -> [pid()].
get_local_members(Name) ->
    i_get_local_members(Name).

-spec get_local_members(Name :: any(), with_meta) -> [{pid(), Meta :: any()}].
get_local_members(Name, with_meta) ->
    i_get_local_members(Name, with_meta).

-spec publish(Name :: any(), Message :: any()) -> {ok, RecipientCount :: non_neg_integer()}.
publish(Name, Message) ->
    MemberPids = i_get_members(Name),
    FSend = fun(Pid) ->
        Pid ! Message
    end,
    lists:foreach(FSend, MemberPids),
    {ok, length(MemberPids)}.

-spec publish_to_local(Name :: any(), Message :: any()) -> {ok, RecipientCount :: non_neg_integer()}.
publish_to_local(Name, Message) ->
    MemberPids = i_get_local_members(Name),
    FSend = fun(Pid) ->
        Pid ! Message
    end,
    lists:foreach(FSend, MemberPids),
    {ok, length(MemberPids)}.

-spec multi_call(Name :: any(), Message :: any()) -> {[{pid(), Reply :: any()}], [BadPid :: pid()]}.
multi_call(Name, Message) ->
    multi_call(Name, Message, ?DEFAULT_MULTI_CALL_TIMEOUT_MS).

-spec multi_call(Name :: any(), Message :: any(), Timeout :: non_neg_integer()) ->
    {[{pid(), Reply :: any()}], [BadPid :: pid()]}.
multi_call(Name, Message, Timeout) ->
    Self = self(),
    MemberPids = i_get_members(Name),
    FSend = fun(Pid) ->
        spawn_link(?MODULE, multi_call_and_receive, [Self, Pid, Message, Timeout])
    end,
    lists:foreach(FSend, MemberPids),
    collect_replies(MemberPids).

-spec multi_call_reply(CallerPid :: pid(), Reply :: any()) -> {syn_multi_call_reply, pid(), Reply :: any()}.
multi_call_reply(CallerPid, Reply) ->
    CallerPid ! {syn_multi_call_reply, self(), Reply}.

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
    %% trap linked processes signal
    process_flag(trap_exit, true),
    
    %% get options
    {ok, [ProcessExitCallbackModule, ProcessExitCallbackFunction]} = syn_utils:get_env_value(
        process_groups_process_exit_callback,
        [undefined, undefined]
    ),
    
    %% build state
    {ok, #state{
        process_groups_process_exit_callback_module = ProcessExitCallbackModule,
        process_groups_process_exit_callback_function = ProcessExitCallbackFunction
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

handle_call({join, Name, Pid, Meta}, _From, State) ->
    %% check if pid is already in group
    case find_by_pid_and_name(Pid, Name) of
        undefined ->
            ok;
        Process ->
            %% remove old reference
            mnesia:dirty_delete_object(Process)
    end,
    %% add to group
    mnesia:dirty_write(#syn_groups_table{
        name = Name,
        pid = Pid,
        node = node(),
        meta = Meta
    }),
    %% link
    erlang:link(Pid),
    %% return
    {reply, ok, State};

handle_call({leave, Name, Pid}, _From, State) ->
    case find_by_pid_and_name(Pid, Name) of
        undefined ->
            {reply, {error, pid_not_in_group}, State};
        Process ->
            %% remove from table
            remove_process(Process),
            %% unlink only when process is no more in groups
            case find_groups_by_pid(Pid) of
                [] -> erlang:unlink(Pid);
                _ -> nop
            end,
            %% reply
            {reply, ok, State}
    end;

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

handle_info({'EXIT', Pid, Reason}, #state{
    process_groups_process_exit_callback_module = ProcessExitCallbackModule,
    process_groups_process_exit_callback_function = ProcessExitCallbackFunction
} = State) ->
    %% check if pid is in table
    case find_groups_by_pid(Pid) of
        [] ->
            %% log
            case Reason of
                normal -> ok;
                killed -> ok;
                _ ->
                    error_logger:error_msg("Received an exit message from an unlinked process ~p with reason: ~p", [Pid, Reason])
            end;
        
        Processes ->
            F = fun(Process) ->
                %% get group & meta
                Name = Process#syn_groups_table.name,
                Meta = Process#syn_groups_table.meta,
                %% log
                case Reason of
                    normal -> ok;
                    killed -> ok;
                    _ ->
                        error_logger:error_msg("Process of group ~p and pid ~p exited with reason: ~p", [Name, Pid, Reason])
                end,
                %% delete from table
                remove_process(Process),
                
                %% callback in separate process
                case ProcessExitCallbackModule of
                    undefined ->
                        ok;
                    _ ->
                        spawn(fun() ->
                            ProcessExitCallbackModule:ProcessExitCallbackFunction(Name, Pid, Meta, Reason)
                        end)
                end
            end,
            lists:foreach(F, Processes)
    end,
    %% return
    {noreply, State};

handle_info(Info, State) ->
    error_logger:warning_msg("Received an unknown info message: ~p", [Info]),
    {noreply, State}.

%% ----------------------------------------------------------------------------------------------------------
%% Terminate
%% ----------------------------------------------------------------------------------------------------------
-spec terminate(Reason :: any(), #state{}) -> terminated.
terminate(Reason, _State) ->
    error_logger:info_msg("Terminating syn_groups with reason: ~p", [Reason]),
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
-spec find_by_pid_and_name(Pid :: pid(), Name :: any()) -> Process :: #syn_groups_table{} | undefined.
find_by_pid_and_name(Pid, Name) ->
    %% build match specs
    MatchHead = #syn_groups_table{name = Name, pid = Pid, _ = '_'},
    Guards = [],
    Result = '$_',
    %% select
    case mnesia:dirty_select(syn_groups_table, [{MatchHead, Guards, [Result]}]) of
        [] -> undefined;
        [Process] -> Process
    end.

-spec i_member(Pid :: pid(), Name :: any()) -> boolean().
i_member(Pid, Name) ->
    case find_by_pid_and_name(Pid, Name) of
        undefined -> false;
        _ -> true
    end.

-spec i_get_members(Name :: any()) -> [pid()].
i_get_members(Name) ->
    Processes = mnesia:dirty_read(syn_groups_table, Name),
    Pids = lists:map(fun(Process) ->
        Process#syn_groups_table.pid
    end, Processes),
    lists:sort(Pids).

-spec i_get_members(Name :: any(), with_meta) -> [{pid(), Meta :: any()}].
i_get_members(Name, with_meta) ->
    Processes = mnesia:dirty_read(syn_groups_table, Name),
    PidsWithMeta = lists:map(fun(Process) ->
        {Process#syn_groups_table.pid, Process#syn_groups_table.meta}
    end, Processes),
    lists:keysort(1, PidsWithMeta).

-spec i_get_local_members(Name :: any()) -> [pid()].
i_get_local_members(Name) ->
    %% build name guard
    NameGuard = case is_tuple(Name) of
        true -> {'==', '$1', {Name}};
        _ -> {'=:=', '$1', Name}
    end,
    %% build match specs
    MatchHead = #syn_groups_table{name = '$1', node = '$2', pid = '$3', _ = '_'},
    Guards = [NameGuard, {'=:=', '$2', node()}],
    Result = '$3',
    %% select
    Pids = mnesia:dirty_select(syn_groups_table, [{MatchHead, Guards, [Result]}]),
    lists:sort(Pids).

-spec i_get_local_members(Name :: any(), with_meta) -> [{pid(), Meta :: any()}].
i_get_local_members(Name, with_meta) ->
    %% build name guard
    NameGuard = case is_tuple(Name) of
        true -> {'==', '$1', {Name}};
        _ -> {'=:=', '$1', Name}
    end,
    %% build match specs
    MatchHead = #syn_groups_table{name = '$1', node = '$2', pid = '$3', meta = '$4', _ = '_'},
    Guards = [NameGuard, {'=:=', '$2', node()}],
    Result = {{'$3', '$4'}},
    %% select
    PidsWithMeta = mnesia:dirty_select(syn_groups_table, [{MatchHead, Guards, [Result]}]),
    lists:keysort(1, PidsWithMeta).

-spec find_groups_by_pid(Pid :: pid()) -> [Process :: #syn_groups_table{}].
find_groups_by_pid(Pid) ->
    mnesia:dirty_index_read(syn_groups_table, Pid, #syn_groups_table.pid).

-spec remove_process(Process :: #syn_groups_table{}) -> ok.
remove_process(Process) ->
    mnesia:dirty_delete_object(syn_groups_table, Process).

-spec multi_call_and_receive(
    CollectorPid :: pid(),
    Pid :: pid(),
    Message :: any(),
    Timeout :: non_neg_integer()
) -> any().
multi_call_and_receive(CollectorPid, Pid, Message, Timeout) ->
    MonitorRef = monitor(process, Pid),
    Pid ! {syn_multi_call, self(), Message},
    
    receive
        {syn_multi_call_reply, Pid, Reply} ->
            CollectorPid ! {reply, Pid, Reply};
        {'DOWN', MonitorRef, _, _, _} ->
            CollectorPid ! {bad_pid, Pid}
    after Timeout ->
        CollectorPid ! {bad_pid, Pid}
    end.

-spec collect_replies(MemberPids :: [pid()]) -> {[{pid(), Reply :: any()}], [BadPid :: pid()]}.
collect_replies(MemberPids) ->
    collect_replies(MemberPids, [], []).

-spec collect_replies(MemberPids :: [pid()], [{pid(), Reply :: any()}], [pid()]) ->
    {[{pid(), Reply :: any()}], [BadPid :: pid()]}.
collect_replies([], Replies, BadPids) -> {Replies, BadPids};
collect_replies(MemberPids, Replies, BadPids) ->
    receive
        {reply, Pid, Reply} ->
            MemberPids1 = lists:delete(Pid, MemberPids),
            collect_replies(MemberPids1, [{Pid, Reply} | Replies], BadPids);
        {bad_pid, Pid} ->
            MemberPids1 = lists:delete(Pid, MemberPids),
            collect_replies(MemberPids1, Replies, [Pid | BadPids])
    end.
