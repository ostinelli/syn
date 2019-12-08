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
%% records
-record(syn_registry_table, {
    name = undefined :: any(),
    pid = undefined :: atom() | pid(),
    node = undefined :: atom(),
    meta = undefined :: any(),
    monitor_ref = undefined :: atom() | reference()
}).
-record(syn_groups_table, {
    name = undefined :: any(),
    pid = undefined :: atom() | pid(),
    node = undefined :: atom(),
    meta = undefined :: any(),
    monitor_ref = undefined :: atom() | reference()
}).

%% types
-type syn_registry_tuple() :: {
    Name :: any(),
    Pid :: pid(),
    Meta :: any()
}.
-type syn_group_tuple() :: {
    GroupName :: any(),
    Pid :: pid(),
    Meta :: any()
}.
-export_type([
    syn_registry_tuple/0,
    syn_group_tuple/0
]).
