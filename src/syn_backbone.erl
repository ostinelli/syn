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
-module(syn_backbone).
-behaviour(gen_server).

%% API
-export([start_link/0]).
-export([get_event_handler_module/0]).
-export([get_anti_entropy_settings/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% macros
-define(DEFAULT_EVENT_HANDLER_MODULE, syn_event_handler).
-define(DEFAULT_ANTI_ENTROPY_MAX_DEVIATION_MS, 60000).

%% records
-record(state, {}).

%% includes
-include("syn.hrl").

%% ===================================================================
%% API
%% ===================================================================
-spec start_link() -> {ok, pid()} | {error, any()}.
start_link() ->
    Options = [],
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], Options).

-spec get_event_handler_module() -> module().
get_event_handler_module() ->
    %% get handler
    CustomEventHandler = application:get_env(syn, event_handler, ?DEFAULT_EVENT_HANDLER_MODULE),
    %% ensure that is it loaded (not using code:ensure_loaded/1 to support embedded mode)
    catch CustomEventHandler:module_info(exports),
    %% return
    CustomEventHandler.

-spec get_anti_entropy_settings(Module :: registry | groups) ->
    {IntervalMs :: non_neg_integer() | undefined, IntervalMaxDeviationMs :: non_neg_integer() | undefined}.
get_anti_entropy_settings(Module) ->
    case application:get_env(syn, anti_entropy, undefined) of
        undefined ->
            {undefined, undefined};

        AntiEntropySettings ->
            case proplists:get_value(Module, AntiEntropySettings) of
                undefined ->
                    {undefined, undefined};

                ModSettings ->
                    case proplists:get_value(interval, ModSettings) of
                        undefined ->
                            {undefined, undefined};

                        I ->
                            IntervalMs = I * 1000,
                            IntervalMaxDeviationMs = proplists:get_value(
                                interval_max_deviation,
                                ModSettings,
                                ?DEFAULT_ANTI_ENTROPY_MAX_DEVIATION_MS
                            ) * 1000,
                            %% return
                            {IntervalMs, IntervalMaxDeviationMs}
                    end
            end
    end.

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
    %% create ETS tables
    %% entries have structure {{Name, Pid}, Meta, Clock, MonitorRef, Node}
    ets:new(syn_registry_by_name, [ordered_set, public, named_table, {read_concurrency, true}, {write_concurrency, true}]),
    %% entries have format {{Pid, Name}, Meta, Clock, MonitorRef, Node}
    ets:new(syn_registry_by_pid, [ordered_set, public, named_table, {read_concurrency, true}, {write_concurrency, true}]),
    %% entries have format {{GroupName, Pid}, Meta, MonitorRef, Node}
    ets:new(syn_groups_by_name, [ordered_set, public, named_table, {read_concurrency, true}, {write_concurrency, true}]),
    %% entries have format {{Pid, GroupName}, Meta, MonitorRef, Node}
    ets:new(syn_groups_by_pid, [ordered_set, public, named_table, {read_concurrency, true}, {write_concurrency, true}]),
    %% init
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

handle_call(Request, From, State) ->
    error_logger:warning_msg("Syn(~p): Received from ~p an unknown call message: ~p~n", [node(), Request, From]),
    {reply, undefined, State}.

%% ----------------------------------------------------------------------------------------------------------
%% Cast messages
%% ----------------------------------------------------------------------------------------------------------
-spec handle_cast(Msg :: any(), #state{}) ->
    {noreply, #state{}} |
    {noreply, #state{}, Timeout :: non_neg_integer()} |
    {stop, Reason :: any(), #state{}}.

handle_cast(Msg, State) ->
    error_logger:warning_msg("Syn(~p): Received an unknown cast message: ~p~n", [node(), Msg]),
    {noreply, State}.

%% ----------------------------------------------------------------------------------------------------------
%% All non Call / Cast messages
%% ----------------------------------------------------------------------------------------------------------
-spec handle_info(Info :: any(), #state{}) ->
    {noreply, #state{}} |
    {noreply, #state{}, Timeout :: non_neg_integer()} |
    {stop, Reason :: any(), #state{}}.

handle_info(Info, State) ->
    error_logger:warning_msg("Syn(~p): Received an unknown info message: ~p~n", [node(), Info]),
    {noreply, State}.

%% ----------------------------------------------------------------------------------------------------------
%% Terminate
%% ----------------------------------------------------------------------------------------------------------
-spec terminate(Reason :: any(), #state{}) -> terminated.
terminate(Reason, _State) ->
    error_logger:info_msg("Syn(~p): Terminating with reason: ~p~n", [node(), Reason]),
    %% delete ETS tables
    ets:delete(syn_registry_by_name),
    ets:delete(syn_registry_by_pid),
    ets:delete(syn_groups_by_name),
    ets:delete(syn_groups_by_pid),
    %% return
    terminated.

%% ----------------------------------------------------------------------------------------------------------
%% Convert process state when code is changed.
%% ----------------------------------------------------------------------------------------------------------
-spec code_change(OldVsn :: any(), #state{}, Extra :: any()) -> {ok, #state{}}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
