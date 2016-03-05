%% ==========================================================================================================
%% Syn - A global process registry.
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
    %% get nodes
    CurrentNode = node(),
    ClusterNodes = [CurrentNode | nodes()],
    %% ensure all nodes are added
    mnesia:change_config(extra_db_nodes, ClusterNodes),
    %% ensure table exists
    case mnesia:create_table(syn_global_table, [
        {type, set},
        {ram_copies, ClusterNodes},
        {attributes, record_info(fields, syn_global_table)},
        {index, [#syn_global_table.pid]},
        {storage_properties, [{ets, [{read_concurrency, true}]}]}
    ]) of
        {atomic, ok} ->
            error_logger:info_msg("syn_global_table was successfully created"),
            ok;
        {aborted, {already_exists, syn_global_table}} ->
            %% table already exists, try to add current node as copy
            add_table_copy_to_current_node();
        {aborted, {already_exists, syn_global_table, CurrentNode}} ->
            %% table already exists, try to add current node as copy
            add_table_copy_to_current_node();
        Other ->
            error_logger:error_msg("Error while creating syn_global_table: ~p", [Other]),
            {error, Other}
    end.

-spec add_table_copy_to_current_node() -> ok | {error, any()}.
add_table_copy_to_current_node() ->
    %% wait for table
    mnesia:wait_for_tables([syn_global_table], 10000),
    %% add copy
    CurrentNode = node(),
    case mnesia:add_table_copy(syn_global_table, CurrentNode, ram_copies) of
        {atomic, ok} ->
            error_logger:info_msg("Copy of syn_global_table was successfully added to current node"),
            ok;
        {aborted, {already_exists, syn_global_table}} ->
            error_logger:info_msg("Copy of syn_global_table is already added to current node"),
            ok;
        {aborted, {already_exists, syn_global_table, CurrentNode}} ->
            error_logger:info_msg("Copy of syn_global_table is already added to current node"),
            ok;
        {aborted, Reason} ->
            error_logger:error_msg("Error while creating copy of syn_global_table: ~p", [Reason]),
            {error, Reason}
    end.
