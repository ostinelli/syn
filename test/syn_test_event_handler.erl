%% ==========================================================================================================
%% Syn - A global Process Registry and Process Group manager.
%%
%% The MIT License (MIT)
%%
%% Copyright (c) 2019 Roberto Ostinelli <roberto@ostinelli.net> and Neato Robotics, Inc.
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
-module(syn_test_event_handler).
-behaviour(syn_event_handler).

%% API
-export([on_process_exit/4]).
-export([on_group_process_exit/4]).
-export([resolve_registry_conflict/3]).

%% ===================================================================
%% Syn Callbacks
%% ===================================================================
-spec on_process_exit(
    Name :: any(),
    Pid :: pid(),
    Meta :: any(),
    Reason :: any()
) -> any().
on_process_exit(_Name, _Pid, {PidId, TestPid}, _Reason) when is_pid(TestPid) ->
    TestPid ! {received_event_on, PidId};
on_process_exit(_Name, _Pid, _Meta, _Reason) ->
    ok.

-spec on_group_process_exit(
    GroupName :: any(),
    Pid :: pid(),
    Meta :: any(),
    Reason :: any()
) -> any().
on_group_process_exit(_GroupName, _Pid, {PidId, TestPid}, _Reason) when is_pid(TestPid) ->
    TestPid ! {received_event_on, PidId};
on_group_process_exit(_GroupName, _Pid, _Meta, _Reason) ->
    ok.

-spec resolve_registry_conflict(
    Name :: any(),
    {Pid1 :: pid(), Meta1 :: any()},
    {Pid2 :: pid(), Meta2 :: any()}
) -> PidToKeep :: pid().
resolve_registry_conflict(_Name, {LocalPid, keep_this_one}, {_RemotePid, _RemoteMeta}) ->
    LocalPid;
resolve_registry_conflict(_Name, {_LocalPid, _LocalMeta}, {RemotePid, keep_this_one}) ->
    RemotePid;
resolve_registry_conflict(_Name, {LocalPid, _LocalMeta}, {_RemotePid, _RemoteMeta}) ->
    LocalPid.
