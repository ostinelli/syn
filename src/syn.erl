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

%% ===================================================================
%% @doc `syn' exposes all of the global Process Registry and Process Group APIs.
%%
%% Syn implement Scopes. A Scope is a way to create a logical overlay network running on top of the Erlang distribution cluster.
%% Nodes that belong to the same Scope will form a "sub-cluster", and will synchronize data between themselves and themselves only.
%%
%% This allows for improved scalability, as it is possible to divide an Erlang cluster into sub-clusters which
%% hold specific portions of data.
%%
%% Every node in an Erlang cluster is automatically added to the Scope `default'. It is therefore not mandatory
%% to use scopes, but it is advisable to do so when scalability is a concern.
%%
%% Please note that most of the methods documented here that allow to specify a Scope will raise a
%% `error({invalid_scope, Scope})' if the local node has not been added to the specified Scope or if the Pids
%% passed in as variables are running on a node that has not been added to the specified Scope.
%%
%% @end
%% ===================================================================
-module(syn).

%% API
-export([start/0, stop/0]).
%% scopes
-export([node_scopes/0, add_node_to_scope/1, add_node_to_scopes/1]).
-export([set_event_handler/1]).
%% registry
-export([lookup/1, lookup/2]).
-export([register/2, register/3, register/4]).
-export([unregister/1, unregister/2]).
-export([registry_count/0, registry_count/1, registry_count/2]).
-export([local_registry_count/0, local_registry_count/1]).
%% gen_server via interface
-export([register_name/2, unregister_name/1, whereis_name/1, send/2]).
%% groups
-export([members/1, members/2]).
-export([is_member/2, is_member/3]).
-export([local_members/1, local_members/2]).
-export([is_local_member/2, is_local_member/3]).
-export([join/2, join/3, join/4]).
-export([leave/2, leave/3]).
-export([group_count/0, group_count/1, group_count/2]).
-export([local_group_count/0, local_group_count/1]).
-export([group_names/0, group_names/1, group_names/2]).
-export([local_group_names/0, local_group_names/1]).
-export([publish/2, publish/3]).
-export([local_publish/2, local_publish/3]).
-export([multi_call/2, multi_call/3, multi_call/4, multi_call_reply/2]).


%% API
%% ===================================================================
%% @doc Starts Syn manually.
%%
%% In most cases Syn will be started as one of your application's dependencies,
%% however you may use this helper method to start it manually.
-spec start() -> ok.
start() ->
    {ok, _} = application:ensure_all_started(syn),
    ok.

%% @doc Stops Syn manually.
-spec stop() -> ok | {error, Reason :: any()}.
stop() ->
    application:stop(syn).

%% ----- \/ scopes ---------------------------------------------------
%% @doc Retrieves the Scopes that the node has been added to.
-spec node_scopes() -> [atom()].
node_scopes() ->
    syn_sup:node_scopes().

%% @doc Add the local node to the specified `Scope'.
%%
%% <h2>Examples</h2>
%% The following adds the local node to the scope "devices" and then register a process handling a device in that scope:
-spec add_node_to_scope(Scope :: atom()) -> ok.
add_node_to_scope(Scope) ->
    syn_sup:add_node_to_scope(Scope).

%% @doc Add the local node to the specified `Scope's.
-spec add_node_to_scopes(Scopes :: [atom()]) -> ok.
add_node_to_scopes(Scopes) ->
    lists:foreach(fun(Scope) ->
        syn_sup:add_node_to_scope(Scope)
    end, Scopes).

%% @doc Sets the handler module.
%%
%% Please see {@link syn_event_handler} for information on callbacks.
%%
%% <h2>Examples</h2>
%% <h3>Elixir</h3>
%% ```
%% iex> :syn.set_event_handler(MyCustomEventHandler)
%% ok
%% '''
%% <h3>Erlang</h3>
%% ```
%% 1> syn:set_event_handler(my_custom_event_handler).
%% ok
%% '''
-spec set_event_handler(module()) -> ok.
set_event_handler(Module) ->
    application:set_env(syn, event_handler, Module).

%% ----- \/ registry -------------------------------------------------
%% @doc Looks up a registry entry in the `default' scope.
%%
%% Same as calling `lookup(default, Name)', see {@link lookup/2}.
%%
%% <h2>Examples</h2>
%% <h3>Elixir</h3>
%% ```
%% iex> :syn.register("SN-123-456789", self())
%% :ok
%% iex> :syn.lookup("SN-123-456789")
%% {#PID<0.105.0>, undefined}
%% '''
%% <h3>Erlang</h3>
%% ```
%% 1> syn:register("SN-123-456789", self()).
%% ok
%% 2> syn:lookup(devices, "SN-123-456789").
%% {<0.79.0>, undefined}
%% '''
-spec lookup(Name :: any()) -> {pid(), Meta :: any()} | undefined.
lookup(Name) ->
    syn_registry:lookup(Name).

%% @doc Looks up a registry entry in the specified `Scope'.
-spec lookup(Scope :: atom(), Name :: any()) -> {pid(), Meta :: any()} | undefined.
lookup(Scope, Name) ->
    syn_registry:lookup(Scope, Name).

%% @doc Registers a process in the `default' scope.
%%
%% Same as calling `register(default, Name, Pid, undefined)', see {@link register/4}.
%%
%% <h2>Examples</h2>
%% <h3>Elixir</h3>
%% ```
%% iex> :syn.register("SN-123-456789", self())
%% :ok
%% iex> :syn.lookup("SN-123-456789")
%% {#PID<0.105.0>, undefined}
%% '''
%% <h3>Erlang</h3>
%% ```
%% 1> syn:register("SN-123-456789", self()).
%% ok
%% 2> syn:lookup(devices, "SN-123-456789").
%% {<0.79.0>, undefined}
%% '''
-spec register(Name :: any(), Pid :: pid()) -> ok | {error, Reason :: any()}.
register(Name, Pid) ->
    syn_registry:register(Name, Pid).

%% @doc Registers a process with metadata in the `default' scope OR with undefined metadata in the specified `Scope'.
%%
%% Same as calling `register(default, Name, Pid, Meta)' or `register(Scope, Name, Pid, undefined)'
%% depending on the position of the `pid()' value. See {@link register/4} for more info.
-spec register(NameOrScope :: any(), PidOrName :: any(), MetaOrPid :: any()) -> ok | {error, Reason :: any()}.
register(NameOrScope, PidOrName, MetaOrPid) ->
    syn_registry:register(NameOrScope, PidOrName, MetaOrPid).

%% @doc Registers a process with metadata in the specified `Scope'.
%%
%% Possible error reasons:
%% <ul>
%% <li>`taken': name is already registered with another `pid()'.</li>
%% <li>`not_alive': The `pid()' being registered is not alive.</li>
%% </ul>
%%
%% You may re-register a process multiple times, for example if you need to update its metadata.
%% When a process gets registered, Syn will automatically monitor it. You may also register the same process with different names.
%%
%% Processes can also be registered as `gen_server' names, by usage of via-tuples. This way, you can use the `gen_server'
%% API with these tuples without referring to the Pid directly.
%%
%% <h2>Examples</h2>
%% <h3>Elixir</h3>
%% ```
%% iex> :syn.add_node_to_scope(:devices).
%% :ok
%% iex> :syn.register(:devices, "SN-123-456789", self(), [meta: :one])
%% :ok
%% iex> :syn.lookup(:devices, "SN-123-456789")
%% {#PID<0.105.0>, [meta: :one]}
%% '''
%% ```
%% iex> tuple = {:via, :syn, <<"your process name">>}.
%% :ok
%% iex> GenServer.start_link(__MODULE__, [], name: tuple)
%% {ok, #PID<0.105.0>}
%% iex> GenServer.call(tuple, :your_message).
%% :your_message
%% '''
%% <h3>Erlang</h3>
%% ```
%% 1> syn:add_node_to_scope(devices).
%% ok
%% 2> syn:register(devices, "SN-123-456789", self(), [{meta, one}]).
%% ok
%% 3> syn:lookup(devices, "SN-123-456789").
%% {<0.79.0>, [{meta, one}]}
%% '''
%% ```
%% 1> Tuple = {via, syn, <<"your process name">>}.
%% ok
%% 2> gen_server:start_link(Tuple, your_module, []).
%% {ok, <0.79.0>}
%% 3> gen_server:call(Tuple, your_message).
%% your_message
%% '''
-spec register(Scope :: atom(), Name :: any(), Pid :: pid(), Meta :: any()) -> ok | {error, Reason :: any()}.
register(Scope, Name, Pid, Meta) ->
    syn_registry:register(Scope, Name, Pid, Meta).

%% @doc Unregisters a process.
%%
%% Same as calling `unregister(default, Name)', see {@link unregister/2}.
-spec unregister(Name :: any()) -> ok | {error, Reason :: any()}.
unregister(Name) ->
    syn_registry:unregister(Name).

%% @doc Unregisters a process.
%%
%% Possible error reasons:
%% <ul>
%% <li>`undefined': name is not registered.</li>
%% <li>`race_condition': the local `pid()' does not correspond to the cluster value. This is a rare occasion.</li>
%% </ul>
%%
%% You don't need to unregister names of processes that are about to die, since they are monitored by Syn
%% and they will be removed automatically. If you manually unregister a process before it dies, the Syn callbacks will not be called.
-spec unregister(Scope :: atom(), Name :: any()) -> ok | {error, Reason :: any()}.
unregister(Scope, Name) ->
    syn_registry:unregister(Scope, Name).

%% @doc Returns the count of all registered processes for the `default' scope.
%%
%% Same as calling `registry_count(default)', see {@link registry_count/1}.
%%
%% <h2>Examples</h2>
%% <h3>Elixir</h3>
%% ```
%% iex> :syn.registry_count()
%% 512473
%% '''
%% <h3>Erlang</h3>
%% ```
%% 1> syn:registry_count().
%% 512473
%% '''
-spec registry_count() -> non_neg_integer().
registry_count() ->
    syn_registry:count().

%% @doc Returns the count of all registered processes for the specified `Scope'.
-spec registry_count(Scope :: atom()) -> non_neg_integer().
registry_count(Scope) ->
    syn_registry:count(Scope).

%% @doc Returns the count of all registered processes for the specified `Scope' running on a node.
-spec registry_count(Scope :: atom(), Node :: node()) -> non_neg_integer().
registry_count(Scope, Node) ->
    syn_registry:count(Scope, Node).

%% @doc Returns the count of all registered processes for the `default' scope running on the local node.
%%
%% Same as calling `registry_count(default, node())', see {@link registry_count/2}.
-spec local_registry_count() -> non_neg_integer().
local_registry_count() ->
    syn_registry:local_count().

%% @doc Returns the count of all registered processes for the specified `Scope' running on the local node.
%%
%% Same as calling `registry_count(Scope, node())', see {@link registry_count/2}.
-spec local_registry_count(Scope :: atom()) -> non_neg_integer().
local_registry_count(Scope) ->
    syn_registry:local_count(Scope).

%% ----- \/ gen_server via module interface --------------------------
-spec register_name(Name :: any(), Pid :: pid()) -> yes | no.
register_name(Name, Pid) ->
    case syn_registry:register(Name, Pid) of
        ok -> yes;
        _ -> no
    end.

-spec unregister_name(Name :: any()) -> any().
unregister_name(Name) ->
    case syn_registry:unregister(Name) of
        ok -> Name;
        _ -> nil
    end.

-spec whereis_name(Name :: any()) -> pid() | undefined.
whereis_name(Name) ->
    case syn_registry:lookup(Name) of
        {Pid, _Meta} -> Pid;
        undefined -> undefined
    end.

-spec send(Name :: any(), Message :: any()) -> pid().
send(Name, Message) ->
    case whereis_name(Name) of
        undefined ->
            {badarg, {Name, Message}};
        Pid ->
            Pid ! Message,
            Pid
    end.

%% ----- \/ groups ---------------------------------------------------
%% @doc Returns the list of all members for GroupName in the `default' Scope.
%%
%% Same as calling `members(default, GroupName)', see {@link members/2}.
%%
%% <h2>Examples</h2>
%% <h3>Elixir</h3>
%% ```
%% iex> :syn.join("area-1").
%% :ok
%% iex> :syn.members("area-1").
%% [{#PID<0.105.0>, :undefined}]
%% '''
%% <h3>Erlang</h3>
%% ```
%% 1> syn:join("area-1", self()).
%% ok
%% 2> syn:members("area-1").
%% [{<0.69.0>, undefined}]
%% '''
-spec members(GroupName :: term()) -> [{Pid :: pid(), Meta :: term()}].
members(GroupName) ->
    syn_groups:members(GroupName).

%% @doc Returns the list of all members for GroupName in the specified `Scope'.
%%
%% <h2>Examples</h2>
%% <h3>Elixir</h3>
%% ```
%% iex> :syn.add_node_to_scope(:devices)
%% :ok
%% iex> :syn.join(:devices, "area-1").
%% :ok
%% iex> :syn.members(:devices, "area-1").
%% [{#PID<0.105.0>, :undefined}]
%% '''
%% <h3>Erlang</h3>
%% ```
%% 1> syn:add_node_to_scope(devices)
%% ok
%% 2> syn:join(devices, "area-1", self()).
%% ok
%% 3> syn:members(devices, "area-1").
%% [{<0.69.0>, undefined}]
%% '''
-spec members(Scope :: atom(), GroupName :: term()) -> [{Pid :: pid(), Meta :: term()}].
members(Scope, GroupName) ->
    syn_groups:members(Scope, GroupName).

%% @doc Returns whether a `pid()' is a member of GroupName in the `default' scope.
%%
%% Same as calling `is_member(default, GroupName, Pid)', see {@link is_member/3}.
-spec is_member(GroupName :: any(), Pid :: pid()) -> boolean().
is_member(GroupName, Pid) ->
    syn_groups:is_member(GroupName, Pid).

%% @doc Returns whether a `pid()' is a member of GroupName in the specified `Scope'.
%%
%% This method will raise a `error({invalid_scope, Scope})' if the node has not been added to the specified `Scope'.
-spec is_member(Scope :: atom(), GroupName :: any(), Pid :: pid()) -> boolean().
is_member(Scope, GroupName, Pid) ->
    syn_groups:is_member(Scope, GroupName, Pid).

%% @doc Returns the list of all members for GroupName in the `default' scope running on the local node.
%%
%% Same as calling `local_members(default, GroupName)', see {@link local_members/2}.
-spec local_members(GroupName :: term()) -> [{Pid :: pid(), Meta :: term()}].
local_members(GroupName) ->
    syn_groups:local_members(GroupName).

%% @doc Returns the list of all members for GroupName in the specified `Scope' running on the local node.
%%
%% This method will raise a `error({invalid_scope, Scope})' if the node has not been added to the specified `Scope'.
-spec local_members(Scope :: atom(), GroupName :: term()) -> [{Pid :: pid(), Meta :: term()}].
local_members(Scope, GroupName) ->
    syn_groups:local_members(Scope, GroupName).

%% @doc Returns whether a `pid()' is a member of GroupName in the `default' scope running on the local node.
%%
%% Same as calling `is_local_member(default, GroupName, Pid)', see {@link is_local_member/3}.
-spec is_local_member(GroupName :: any(), Pid :: pid()) -> boolean().
is_local_member(GroupName, Pid) ->
    syn_groups:is_local_member(GroupName, Pid).

%% @doc Returns whether a `pid()' is a member of GroupName in the specified `Scope' running on the local node.
%%
%% This method will raise a `error({invalid_scope, Scope})' if the node has not been added to the specified `Scope'.
-spec is_local_member(Scope :: atom(), GroupName :: any(), Pid :: pid()) -> boolean().
is_local_member(Scope, GroupName, Pid) ->
    syn_groups:is_local_member(Scope, GroupName, Pid).

%% @doc Adds a `pid()' to GroupName in the `default' scope.
%%
%% Same as calling `join(default, GroupName, Pid)', see {@link join/4}.
%%
%% <h2>Examples</h2>
%% <h3>Elixir</h3>
%% ```
%% iex> :syn.join(:"area-1", self()).
%% :ok
%% '''
%% <h3>Erlang</h3>
%% ```
%% 1> syn:join("area-1", self()).
%% ok
%% '''
-spec join(GroupName :: any(), Pid :: pid()) -> ok | {error, Reason :: any()}.
join(GroupName, Pid) ->
    syn_groups:join(GroupName, Pid).

%% @doc Adds a `pid()' with metadata to GroupName in the `default' scope OR with undefined metadata in the specified `Scope'.
-spec join(GroupNameOrScope :: any(), PidOrGroupName :: any(), MetaOrPid :: any()) -> ok | {error, Reason :: any()}.
join(GroupNameOrScope, PidOrGroupName, MetaOrPid) ->
    syn_groups:join(GroupNameOrScope, PidOrGroupName, MetaOrPid).

%% @doc Adds a `pid()' with metadata to GroupName in the specified `Scope'.
%%
%% Possible error reasons:
%% <ul>
%% <li>`not_alive': The `pid()' being added is not alive.</li>
%% </ul>
%%
%% A process can join multiple groups. When a process joins a group, Syn will automatically monitor it.
%% A process may join the same group multiple times, for example if you need to update its metadata,
%% though it will still be listed only once in it.
%%
%% <h2>Examples</h2>
%% <h3>Elixir</h3>
%% ```
%% iex> :syn.add_node_to_scope(:devices)
%% :ok
%% iex> :syn.join(:devices, "area-1", self(), [meta: :one]).
%% :ok
%% '''
%% <h3>Erlang</h3>
%% ```
%% 1> syn:add_node_to_scope(devices).
%% ok
%% 2> syn:join(devices, "area-1", self(), [{meta, one}]).
%% ok
%% '''
-spec join(Scope :: atom(), GroupName :: any(), Pid :: pid(), Meta :: any()) -> ok | {error, Reason :: any()}.
join(Scope, GroupName, Pid, Meta) ->
    syn_groups:join(Scope, GroupName, Pid, Meta).

%% @doc Removes a `pid()' from GroupName in the `default' Scope.
%%
%% Same as calling `leave(default, GroupName, Pid)', see {@link leave/3}.
-spec leave(GroupName :: any(), Pid :: pid()) -> ok | {error, Reason :: any()}.
leave(GroupName, Pid) ->
    syn_groups:leave(GroupName, Pid).

%% @doc Removes a `pid()' from GroupName in the specified `Scope'.
%%
%% Possible error reasons:
%% <ul>
%% <li>`not_in_group': The `pid()' is not in GroupName for the specified `Scope'.</li>
%% </ul>
%%
%% You don't need to remove processes that are about to die, since they are monitored by Syn and they will be removed
%% automatically from their groups.
-spec leave(Scope :: atom(), GroupName :: any(), Pid :: pid()) -> ok | {error, Reason :: any()}.
leave(Scope, GroupName, Pid) ->
    syn_groups:leave(Scope, GroupName, Pid).

%% @doc Returns the count of all the groups for the `default' scope.
%%
%% Same as calling `group_count(default)', see {@link group_count/1}.
%%
%% <h2>Examples</h2>
%% <h3>Elixir</h3>
%% ```
%% iex> :syn.group_count()
%% 321778
%% '''
%% <h3>Erlang</h3>
%% ```
%% 1> syn:group_count().
%% 321778
%% '''
-spec group_count() -> non_neg_integer().
group_count() ->
    syn_groups:count().

%% @doc Returns the count of all the groups for the specified `Scope'.
-spec group_count(Scope :: atom()) -> non_neg_integer().
group_count(Scope) ->
    syn_groups:count(Scope).

%% @doc Returns the count of all the groups for the specified `Scope' which have at least 1 process running on `Node'.
-spec group_count(Scope :: atom(), Node :: node()) -> non_neg_integer().
group_count(Scope, Node) ->
    syn_groups:count(Scope, Node).

%% @doc Returns the count of all the groups which have at least 1 process running on `Node' for the `default' scope.
%%
%% Same as calling `group_count(default, node())', see {@link group_count/2}.
-spec local_group_count() -> non_neg_integer().
local_group_count() ->
    syn_groups:local_count().

%% @doc Returns the count of all the groups which have at least 1 process running on `Node' for the specified `Scope'.
%%
%% Same as calling `group_count(Scope, node())', see {@link group_count/2}.
-spec local_group_count(Scope :: atom()) -> non_neg_integer().
local_group_count(Scope) ->
    syn_groups:local_count(Scope).

%% @doc Returns the group names for the `default' scope.
%%
%% The order of the group names is not guaranteed to be the same on all calls.
%% Same as calling `group_names(default)', see {@link group_names/1}.
%%
%% <h2>Examples</h2>
%% <h3>Elixir</h3>
%% ```
%% iex> :syn.group_names()
%% ["area-1", "area-2"]
%% '''
%% <h3>Erlang</h3>
%% ```
%% 1> syn:group_names().
%% ["area-1", "area-2"]
%% '''
-spec group_names() -> [GroupName :: term()].
group_names() ->
    syn_groups:group_names().

%% @doc Returns the group names for the specified `Scope'.
%%
%% The order of the group names is not guaranteed to be the same on all calls.
-spec group_names(Scope :: atom()) -> [GroupName :: term()].
group_names(Scope) ->
    syn_groups:group_names(Scope).

%% @doc Returns the group names for the specified `Scope' which have at least 1 process running on `Node'.
%%
%% The order of the group names is not guaranteed to be the same on all calls.
-spec group_names(Scope :: atom(), Node :: node()) -> [GroupName :: term()].
group_names(Scope, Node) ->
    syn_groups:group_names(Scope, Node).

%% @doc Returns the group names which have at least 1 process running on `Node' for the `default' scope.
%%
%% Same as calling `group_names(default, node())', see {@link group_names/2}.
-spec local_group_names() -> [GroupName :: term()].
local_group_names() ->
    syn_groups:local_group_names().

%% @doc Returns the group names which have at least 1 process running on `Node' for the specified `Scope'.
%%
%% Same as calling `group_names(Scope, node())', see {@link group_names/2}.
-spec local_group_names(Scope :: atom()) -> [GroupName :: term()].
local_group_names(Scope) ->
    syn_groups:local_group_names(Scope).

%% @doc Publish a message to all group members in the `default' scope.
%%
%% Same as calling `publish(default, GroupName, Message)', see {@link publish/3}.
%%
%% <h2>Examples</h2>
%% <h3>Elixir</h3>
%% ```
%% iex> :syn.join("area-1", self())
%% :ok
%% iex> :syn.publish("area-1", :my_message)
%% {:ok,1}
%% iex> flush().
%% Shell got :my_message
%% :ok
%% '''
%% <h3>Erlang</h3>
%% ```
%% 1> syn:join("area-1", self()).
%% ok
%% 2> syn:publish("area-1", my_message).
%% {ok,1}
%% 3> flush().
%% Shell got my_message
%% ok
%% '''
-spec publish(GroupName :: any(), Message :: any()) -> {ok, RecipientCount :: non_neg_integer()}.
publish(GroupName, Message) ->
    syn_groups:publish(GroupName, Message).

%% @doc Publish a message to all group members in the Specified scope.
%%
%% `RecipientCount' is the count of the intended recipients.
%%
%% <h2>Examples</h2>
%% <h3>Elixir</h3>
%% ```
%% iex> :syn.add_node_to_scope(:devices)
%% :ok
%% iex> :syn.join(:devices, "area-1", self())
%% :ok
%% iex> :syn.publish(:devices, "area-1", :my_message)
%% {:ok,1}
%% iex> flush().
%% Shell got :my_message
%% :ok
%% '''
%% <h3>Erlang</h3>
%% ```
%% 1> syn:add_node_to_scope(devices).
%% ok
%% 2> syn:join(devices, "area-1", self()).
%% ok
%% 3> syn:publish(devices, "area-1", my_message).
%% {ok,1}
%% 4> flush().
%% Shell got my_message
%% ok
%% '''
-spec publish(Scope :: atom(), GroupName :: any(), Message :: any()) -> {ok, RecipientCount :: non_neg_integer()}.
publish(Scope, GroupName, Message) ->
    syn_groups:publish(Scope, GroupName, Message).

%% @doc Publish a message to all group members running on the local node in the `default' scope.
%%
%% Same as calling `local_publish(default, GroupName, Message)', see {@link local_publish/3}.
-spec local_publish(GroupName :: any(), Message :: any()) -> {ok, RecipientCount :: non_neg_integer()}.
local_publish(GroupName, Message) ->
    syn_groups:local_publish(GroupName, Message).

%% @doc Publish a message to all group members running on the local node in the specified `Scope'.
%%
%% `RecipientCount' is the count of the intended recipients.
-spec local_publish(Scope :: atom(), GroupName :: any(), Message :: any()) -> {ok, RecipientCount :: non_neg_integer()}.
local_publish(Scope, GroupName, Message) ->
    syn_groups:local_publish(Scope, GroupName, Message).

%% @doc Calls all group members node in the `default' scope and collects their replies.
%%
%% Same as calling `multi_call(default, GroupName, Message, 5000)', see {@link multi_call/4}.
-spec multi_call(GroupName :: any(), Message :: any()) ->
    {[{pid(), Reply :: any()}], [BadPid :: pid()]}.
multi_call(GroupName, Message) ->
    syn_groups:multi_call(GroupName, Message).

%% @doc Calls all group members running in the specified `Scope' and collects their replies.
%%
%% Same as calling `multi_call(Scope, GroupName, Message, 5000)', see {@link multi_call/4}.
-spec multi_call(Scope :: atom(), GroupName :: any(), Message :: any()) ->
    {
        Replies :: [{{pid(), Meta :: term()}, Reply :: term()}],
        BadReplies :: [{pid(), Meta :: term()}]
    }.
multi_call(Scope, GroupName, Message) ->
    syn_groups:multi_call(Scope, GroupName, Message).

%% @doc Calls all group members running  in the specified `Scope' and collects their replies.
%%
%% When this call is issued, all members will receive a tuple in the format:
%%
%% `{syn_multi_call, CallerPid, Message}'
%%
%% To reply, every member MUST use the method {@link multi_call_reply/2}.
%%
%% Syn will wait up to the value specified in `Timeout' to receive all replies from the members.
%% The responses will be added to the `Replies' list, while the members that do not reply in time or that crash
%% before sending a reply will be added to the `BadReplies' list.
-spec multi_call(Scope :: atom(), GroupName :: any(), Message :: any(), Timeout :: non_neg_integer()) ->
    {
        Replies :: [{{pid(), Meta :: term()}, Reply :: term()}],
        BadReplies :: [{pid(), Meta :: term()}]
    }.
multi_call(Scope, GroupName, Message, Timeout) ->
    syn_groups:multi_call(Scope, GroupName, Message, Timeout).

%% @doc Allows a group member to reply to a multi call.
%%
%% See {@link multi_call/4} for info.
-spec multi_call_reply(CallerPid :: pid(), Reply :: any()) -> {syn_multi_call_reply, pid(), Reply :: any()}.
multi_call_reply(CallerPid, Reply) ->
    syn_groups:multi_call_reply(CallerPid, Reply).
