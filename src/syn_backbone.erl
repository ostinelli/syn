%% ==========================================================================================================
%% Syn - A global Process Registry and Process Group manager.
%%
%% The MIT License (MIT)
%%
%% Copyright (c) 2015 Roberto Ostinelli <roberto@ostinelli.net> and Neato Robotics, Inc.
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
-export([initdb/0]).

%% include
-include("syn.hrl").


%% ===================================================================
%% API
%% ===================================================================

-spec initdb() -> ok | {error, any()}.
initdb() ->
    %% ensure all nodes are added
    ClusterNodes = [node() | nodes()],
    mnesia:change_config(extra_db_nodes, ClusterNodes),
    %% create tables
    create_table(syn_registry_table, [
        {type, set},
        {ram_copies, ClusterNodes},
        {attributes, record_info(fields, syn_registry_table)},
        {index, [#syn_registry_table.pid]},
        {storage_properties, [{ets, [{read_concurrency, true}]}]}
    ]),
    create_table(syn_groups_table, [
        {type, bag},
        {ram_copies, ClusterNodes},
        {attributes, record_info(fields, syn_groups_table)},
        {index, [#syn_groups_table.pid]},
        {storage_properties, [{ets, [{read_concurrency, true}]}]}
    ]).

create_table(TableName, Options) ->
    CurrentNode = node(),
    %% ensure table exists
    case mnesia:create_table(TableName, Options) of
        {atomic, ok} ->
            error_logger:info_msg("~p was successfully created", [TableName]),
            ok;
        {aborted, {already_exists, TableName}} ->
            %% table already exists, try to add current node as copy
            add_table_copy_to_current_node(TableName);
        {aborted, {already_exists, TableName, CurrentNode}} ->
            %% table already exists, try to add current node as copy
            add_table_copy_to_current_node(TableName);
        Other ->
            error_logger:error_msg("Error while creating ~p: ~p", [TableName, Other]),
            {error, Other}
    end.

-spec add_table_copy_to_current_node(TableName :: atom()) -> ok | {error, any()}.
add_table_copy_to_current_node(TableName) ->
    CurrentNode = node(),
    %% wait for table
    mnesia:wait_for_tables([TableName], 10000),
    %% add copy
    case mnesia:add_table_copy(TableName, CurrentNode, ram_copies) of
        {atomic, ok} ->
            error_logger:info_msg("Copy of ~p was successfully added to current node", [TableName]),
            ok;
        {aborted, {already_exists, TableName}} ->
            error_logger:info_msg("Copy of ~p is already added to current node", [TableName]),
            ok;
        {aborted, {already_exists, TableName, CurrentNode}} ->
            error_logger:info_msg("Copy of ~p is already added to current node", [TableName]),
            ok;
        {aborted, Reason} ->
            error_logger:error_msg("Error while creating copy of ~p: ~p", [TableName, Reason]),
            {error, Reason}
    end.
