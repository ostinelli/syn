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
-export([join/2]).
-export([leave/2]).
-export([member/2]).
-export([get_members/1]).
-export([publish/2]).
-export([multi_call/2, multi_call/3]).
-export([multi_call_reply/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% internal
-export([multi_call_and_receive/4]).

%% records
-record(state, {}).

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

-spec join(Name :: any(), Pid :: pid()) -> ok | {error, pid_already_in_group}.
join(Name, Pid) when is_pid(Pid) ->
    Node = node(Pid),
    gen_server:call({?MODULE, Node}, {join, Name, Pid}).

-spec leave(Name :: any(), Pid :: pid()) -> ok | {error, undefined | pid_not_in_group}.
leave(Name, Pid) when is_pid(Pid) ->
    Node = node(Pid),
    gen_server:call({?MODULE, Node}, {leave, Name, Pid}).

-spec member(Pid :: pid(), Name :: any()) -> boolean().
member(Pid, Name) when is_pid(Pid) ->
    i_member(Pid, Name).

-spec get_members(Name :: any()) -> [pid()].
get_members(Name) ->
    i_get_members(Name).

-spec publish(Name :: any(), Message :: any()) -> {ok, RecipientCount :: non_neg_integer()}.
publish(Name, Message) ->
    MemberPids = i_get_members(Name),
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

    %% build state
    {ok, #state{}}.

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

handle_call({join, Name, Pid}, _From, State) ->
    case i_member(Pid, Name) of
        false ->
            %% add to table
            mnesia:dirty_write(#syn_groups_table{
                name = Name,
                pid = Pid,
                node = node()
            }),
            %% link
            erlang:link(Pid),
            %% return
            {reply, ok, State};
        _ ->
            {reply, pid_already_in_group, State}
    end;

handle_call({leave, Name, Pid}, _From, State) ->
    case find_by_pid_and_name(Pid, Name) of
        undefined ->
            {error, pid_not_in_group};
        Process ->
            %% remove from table
            remove_process(Process),
            %% unlink
            erlang:unlink(Pid),
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

handle_info({'EXIT', Pid, Reason}, State) ->
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
                %% get group
                Name = Process#syn_groups_table.name,
                %% log
                case Reason of
                    normal -> ok;
                    killed -> ok;
                    _ ->
                        error_logger:error_msg("Process of group ~p and pid ~p exited with reason: ~p", [Name, Pid, Reason])
                end,
                %% delete from table
                remove_process(Process)
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
find_by_pid_and_name(Pid, Name) when is_tuple(Name) ->
    i_find_by_pid_and_name(Pid, {'==', '$1', {Name}});
find_by_pid_and_name(Pid, Name) ->
    i_find_by_pid_and_name(Pid, {'=:=', '$1', Name}).

-spec i_find_by_pid_and_name(Pid :: pid(), NameGuard :: any()) -> boolean().
i_find_by_pid_and_name(Pid, NameGuard) ->
    %% build match specs
    MatchHead = #syn_groups_table{name = '$1', pid = '$2', _ = '_'},
    Guards = [NameGuard, {'=:=', '$2', Pid}],
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
