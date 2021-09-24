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
-module(syn_test_event_handler_resolution).
-behaviour(syn_event_handler).

-export([resolve_registry_conflict/4]).

-spec resolve_registry_conflict(
    Scope :: atom(),
    Name :: any(),
    {LocalPid :: pid(), LocalMeta :: any()},
    {RemotePid :: pid(), RemoteMeta :: any()}
) -> PidToKeep :: pid().
resolve_registry_conflict(default, _Name, {Pid1, keepthis, _Time1}, {_Pid2, _Meta2, _Time2}) ->
    Pid1;
resolve_registry_conflict(custom_scope_bc, _Name, {Pid1, keepthis, _Time1}, {_Pid2, _Meta2, _Time2}) ->
    Pid1;
resolve_registry_conflict(default, _Name, {_Pid1, _Meta1, _Time1}, {Pid2, keepthis, _Time2}) ->
    Pid2;
resolve_registry_conflict(custom_scope_bc, _Name, {_Pid1, _Meta1, _Time1}, {Pid2, keepthis, _Time2}) ->
    Pid2.
