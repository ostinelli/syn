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
-module(syn_event_handler).

-export([do_resolve_registry_conflict/5]).

-callback resolve_registry_conflict(
    Name :: any(),
    {Pid1 :: pid(), Meta1 :: any()},
    {Pid2 :: pid(), Meta2 :: any()}
) -> PidToKeep :: pid() | undefined.

-optional_callbacks([resolve_registry_conflict/3]).

-spec do_resolve_registry_conflict(
    Scope :: atom(),
    Name :: any(),
    {Pid1 :: pid(), Meta1 :: any(), Time1 :: non_neg_integer()},
    {Pid2 :: pid(), Meta2 :: any(), Time2 :: non_neg_integer()},
    CustomEventHandler :: module() | undefined
) -> PidToKeep :: pid() | undefined.
do_resolve_registry_conflict(Scope, Name, {Pid1, Meta1, Time1}, {Pid2, Meta2, Time2}, CustomEventHandler) ->
    case erlang:function_exported(CustomEventHandler, resolve_registry_conflict, 4) of
        true ->
            try CustomEventHandler:resolve_registry_conflict(Scope, Name, {Pid1, Meta1}, {Pid2, Meta2}) of
                PidToKeep when is_pid(PidToKeep) -> PidToKeep;
                _ -> undefined

            catch Exception:Reason ->
                error_logger:error_msg(
                    "Syn(~p): Error ~p in custom handler resolve_registry_conflict: ~p~n",
                    [node(), Exception, Reason]
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
