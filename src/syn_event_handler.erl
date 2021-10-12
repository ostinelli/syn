%% ==========================================================================================================
%% Syn - A global Process Registry and Process Group manager.
%%
%% The MIT License (MIT)
%%
%% Copyright (c) 2019-2021 Roberto Ostinelli <roberto@ostinelli.net> and Neato Robotics, Inc.
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

%% ===================================================================
%% @doc `syn_event_handler' defines Syn's callbacks.
%%
%% You can specify the callback module with {@link syn:set_event_handler/1}.
%% In your module you need to specify the behavior `syn_event_handler' and implement the callbacks.
%% All callbacks are optional, so you just need to define the ones you need.
%%
%% While all callbacks do not have a direct effect on Syn (their return value is ignored), a special case is the callback
%% `resolve_registry_conflict/3'. If specified, this is the method that will be used to resolve registry conflicts when detected.
%%
%% In case of net splits or race conditions, a specific name might get registered simultaneously on two different nodes.
%% When this happens, the cluster experiences a registry naming conflict.
%%
%% Syn will resolve this Process Registry conflict by choosing a single process. By default, Syn keeps track of the time
%% when a registration takes place with {@link erlang:system_time/0},
%% compares values between conflicting processes and:
%% <ul>
%% <li>Keeps the one with the higher value (the process that was registered more recently).</li>
%% <li>Kills the other process by sending a kill signal with `exit(Pid, {syn_resolve_kill, Name, Meta})'.</li>
%% </ul>
%% This is a very simple mechanism that can be imprecise, as system clocks are not perfectly aligned in a cluster.
%% If something more elaborate is desired you MAY specify a custom handler that implements the `resolve_registry_conflict/3' callback.
%% To this effect, you may also store additional data to resolve conflicts in the `Meta' value, since it will be passed
%% into the callback for both of the conflicting processes.
%%
%% If implemented, this method MUST return the `pid()' of the process that you wish to keep. The other process will be killed.
%%
%% Important Note: the conflict resolution method will be called on the two nodes where the conflicting processes are running on.
%% Therefore, this method MUST be defined in the same way across all nodes of the cluster and have the same effect
%% regardless of the node it is run on, or you will experience unexpected results.
%%
%% <h2>Examples</h2>
%% The following callback module implements the `on_process_unregistered/4' and the `on_process_left/4' callbacks.
%% <h3>Elixir</h3>
%% ```
%% defmodule MyCustomEventHandler do
%%   ‎@behaviour :syn_event_handler
%%
%%   ‎@impl true
%%   ‎@spec on_process_unregistered(
%%     scope :: atom(),
%%     name :: any(),
%%     pid :: pid(),
%%     meta :: any()
%%   ) :: any()
%%   def on_process_unregistered(scope, name, pid, meta) do
%%   end
%%
%%   ‎@impl true
%%   ‎@spec on_process_left(
%%     scope :: atom(),
%%     group_name :: any(),
%%     pid :: pid(),
%%     meta :: any()
%%   ) :: any()
%%   def on_process_left(scope, group_name, pid, meta) do
%%   end
%% end
%% '''
%% <h3>Erlang</h3>
%% ```
%% -module(my_custom_event_handler).
%% -behaviour(syn_event_handler).
%% -export([on_process_unregistered/4]).
%% -export([on_group_process_exit/4]).
%%
%% -spec on_process_unregistered(
%%     Scope :: atom(),
%%     Name :: any(),
%%     Pid :: pid(),
%%     Meta :: any()
%% ) -> any().
%% on_process_unregistered(Scope, Name, Pid, Meta) ->
%%     ok.
%%
%% -spec on_process_left(
%%     Scope :: atom(),
%%     GroupName :: any(),
%%     Pid :: pid(),
%%     Meta :: any()
%% ) -> any().
%% on_process_left(Scope, GroupName, Pid, Meta) ->
%%     ok.
%% '''
%%
%% @end
%% ===================================================================

-module(syn_event_handler).

%% API
-export([ensure_event_handler_loaded/0]).
-export([call_event_handler/2]).
-export([do_resolve_registry_conflict/4]).

-callback on_process_registered(
    Scope :: any(),
    Name :: any(),
    Pid :: pid(),
    Meta :: any()
) -> any().

-callback on_registry_process_updated(
    Scope :: any(),
    Name :: any(),
    Pid :: pid(),
    Meta :: any()
) -> any().

-callback on_process_unregistered(
    Scope :: any(),
    Name :: any(),
    Pid :: pid(),
    Meta :: any()
) -> any().

-callback on_process_joined(
    Scope :: any(),
    GroupName :: any(),
    Pid :: pid(),
    Meta :: any()
) -> any().

-callback on_group_process_updated(
    Scope :: any(),
    GroupName :: any(),
    Pid :: pid(),
    Meta :: any()
) -> any().

-callback on_process_left(
    Scope :: any(),
    GroupName :: any(),
    Pid :: pid(),
    Meta :: any()
) -> any().

-callback resolve_registry_conflict(
    Name :: any(),
    {Pid1 :: pid(), Meta1 :: any(), Time1 :: non_neg_integer()},
    {Pid2 :: pid(), Meta2 :: any(), Time2 :: non_neg_integer()}
) -> PidToKeep :: pid().

-optional_callbacks([on_process_registered/4, on_registry_process_updated/4, on_process_unregistered/4]).
-optional_callbacks([on_process_joined/4, on_group_process_updated/4, on_process_left/4]).
-optional_callbacks([resolve_registry_conflict/3]).

%% ===================================================================
%% API
%% ===================================================================
-spec ensure_event_handler_loaded() -> module().
ensure_event_handler_loaded() ->
    %% get handler
    CustomEventHandler = get_custom_event_handler(),
    %% ensure that is it loaded (not using code:ensure_loaded/1 to support embedded mode)
    catch CustomEventHandler:module_info(exports).

-spec call_event_handler(
    CallbackMethod :: atom(),
    Args :: [any()]
) -> any().
call_event_handler(CallbackMethod, Args) ->
    CustomEventHandler = get_custom_event_handler(),
    case erlang:function_exported(CustomEventHandler, CallbackMethod, 4) of
        true ->
            try apply(CustomEventHandler, CallbackMethod, Args)
            catch Class:Reason:Stacktrace ->
                error_logger:error_msg(
                    "SYN[~s] Error ~p:~p in custom handler ~p: ~p",
                    [?MODULE, Class, Reason, CallbackMethod, Stacktrace]
                )
            end;

        _ ->
            ok
    end.

-spec do_resolve_registry_conflict(
    Scope :: atom(),
    Name :: any(),
    {Pid1 :: pid(), Meta1 :: any(), Time1 :: non_neg_integer()},
    {Pid2 :: pid(), Meta2 :: any(), Time2 :: non_neg_integer()}
) -> PidToKeep :: pid() | undefined.
do_resolve_registry_conflict(Scope, Name, {Pid1, Meta1, Time1}, {Pid2, Meta2, Time2}) ->
    CustomEventHandler = get_custom_event_handler(),
    case erlang:function_exported(CustomEventHandler, resolve_registry_conflict, 4) of
        true ->
            try CustomEventHandler:resolve_registry_conflict(Scope, Name, {Pid1, Meta1, Time1}, {Pid2, Meta2, Time2}) of
                PidToKeep when is_pid(PidToKeep) -> PidToKeep;
                _ -> undefined

            catch Class:Reason ->
                error_logger:error_msg(
                    "SYN[~s] Error ~p in custom handler resolve_registry_conflict: ~p",
                    [?MODULE, Class, Reason]
                ),
                undefined
            end;

        _ ->
            %% by default, keep pid registered more recently
            %% this is a simple mechanism that can be imprecise, as system clocks are not perfectly aligned in a cluster
            %% if something more elaborate is desired (such as vector clocks) use Meta to store data and a custom event handler
            PidToKeep = case Time1 > Time2 of
                true -> Pid1;
                _ -> Pid2
            end,
            PidToKeep
    end.

%% ===================================================================
%% Internal
%% ===================================================================
-spec get_custom_event_handler() -> undefined | {ok, CustomEventHandler :: atom()}.
get_custom_event_handler() ->
    application:get_env(syn, event_handler, undefined).
