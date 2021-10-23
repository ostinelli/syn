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
%% types
-type syn_cluster_api_version() :: {
    ApiCall :: atom(),
    Version :: atom()
}.
-type syn_registry_entry() :: {
    Name :: term(),
    Pid :: pid(),
    Meta :: term(),
    Time :: integer(),
    MRef :: undefined | reference(),
    Node :: node()
}.
-type syn_registry_entry_by_pid() :: {
    Pid :: pid(),
    Name :: term(),
    Meta :: term(),
    Time :: integer(),
    MRef :: undefined | reference(),
    Node :: node()
}.
-type syn_registry_tuple() :: {
    Name :: term(),
    Pid :: pid(),
    Meta :: term(),
    Time :: integer()
}.
-type syn_pg_entry() :: {
    {
        GroupName :: term(),
        Pid :: pid()
    },
    Meta :: term(),
    Time :: integer(),
    MRef :: undefined | reference(),
    Node :: node()
}.
-type syn_pg_tuple() :: {
    GroupName :: term(),
    Pid :: pid(),
    Meta :: term(),
    Time :: non_neg_integer()
}.

%% records
-record(state, {
    handler = undefined :: undefined | module(),
    handler_state :: term(),
    handler_log_name :: atom(),
    scope = undefined :: atom(),
    process_name :: atom(),
    nodes_map = #{} :: #{node() => pid()},
    multicast_pid :: pid(),
    table_by_name :: atom(),
    table_by_pid :: atom()
}).
