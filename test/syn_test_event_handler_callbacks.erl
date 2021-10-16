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
-module(syn_test_event_handler_callbacks).
-behaviour(syn_event_handler).

-export([on_process_registered/5]).
-export([on_process_unregistered/5]).
-export([on_registry_process_updated/5]).
-export([on_process_joined/5]).
-export([on_process_left/5]).
-export([on_group_process_updated/5]).

on_process_registered(Scope, Name, Pid, {recipient, RecipientPid, AdditionalMeta}, Reason) ->
    RecipientPid ! {on_process_registered, node(), Scope, Name, Pid, AdditionalMeta, Reason}.

on_process_unregistered(Scope, Name, Pid, {recipient, RecipientPid, AdditionalMeta}, Reason) ->
    RecipientPid ! {on_process_unregistered, node(), Scope, Name, Pid, AdditionalMeta, Reason}.

on_registry_process_updated(Scope, Name, Pid, {recipient, RecipientPid, AdditionalMeta}, Reason) ->
    RecipientPid ! {on_registry_process_updated, node(), Scope, Name, Pid, AdditionalMeta, Reason}.

on_process_joined(Scope, GroupName, Pid, {recipient, RecipientPid, AdditionalMeta}, Reason) ->
    RecipientPid ! {on_process_joined, node(), Scope, GroupName, Pid, AdditionalMeta, Reason}.

on_process_left(Scope, GroupName, Pid, {recipient, RecipientPid, AdditionalMeta}, Reason) ->
    RecipientPid ! {on_process_left, node(), Scope, GroupName, Pid, AdditionalMeta, Reason}.

on_group_process_updated(Scope, GroupName, Pid, {recipient, RecipientPid, AdditionalMeta}, Reason) ->
    RecipientPid ! {on_group_process_updated, node(), Scope, GroupName, Pid, AdditionalMeta, Reason}.
