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

%% API
-export([init/0]).
-export([deinit/0]).
-export([get_event_handler_module/0]).

%% macros
-define(DEFAULT_EVENT_HANDLER_MODULE, syn_event_handler).

%% includes
-include("syn.hrl").

%% ===================================================================
%% API
%% ===================================================================
-spec init() -> ok | {error, Reason :: any()}.
init() ->
    case create_registry_table() of
        {atomic, ok} ->
            case create_groups_table() of
                {atomic, ok} -> ok;
                {aborted, Reason} -> {error, {could_not_create_syn_groups_table, Reason}}
            end;
        {aborted, Reason} ->
            {error, {could_not_create_syn_registry_table, Reason}}
    end.

-spec deinit() -> ok.
deinit() ->
    mnesia:delete_table(syn_registry_table),
    mnesia:delete_table(syn_groups_table),
    ok.

-spec get_event_handler_module() -> module().
get_event_handler_module() ->
    %% get handler
    CustomEventHandler = application:get_env(syn, event_handler, ?DEFAULT_EVENT_HANDLER_MODULE),
    %% ensure that is it loaded (not using code:ensure_loaded/1 to support embedded mode)
    catch CustomEventHandler:module_info(exports),
    %% return
    CustomEventHandler.

%% ===================================================================
%% Internal
%% ===================================================================
-spec create_registry_table() -> {atomic, ok} | {aborted, Reason :: any()}.
create_registry_table() ->
    mnesia:create_table(syn_registry_table, [
        {type, set},
        {attributes, record_info(fields, syn_registry_table)},
        {index, [#syn_registry_table.pid]},
        {storage_properties, [{ets, [{read_concurrency, true}]}]}
    ]).

-spec create_groups_table() -> {atomic, ok} | {aborted, Reason :: any()}.
create_groups_table() ->
    mnesia:create_table(syn_groups_table, [
        {type, bag},
        {attributes, record_info(fields, syn_groups_table)},
        {index, [#syn_groups_table.pid, #syn_groups_table.node]},
        {storage_properties, [{ets, [{read_concurrency, true}]}]}
    ]).
