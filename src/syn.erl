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
%% @doc Exposes all of the global Process Registry and Process Group APIs.
%%
%% Syn implement Scopes. You may think of Scopes such as database tables, so a set of data elements,
%% but that's where the analogy ends.
%%
%% A Scope is a way to create a namespaced, logical overlay network running on top of the Erlang distribution cluster.
%% Nodes that belong to the same Scope will form a subcluster: they will synchronize data between themselves,
%% and themselves only.
%%
%% For instance, you may have nodes in your Erlang cluster that need to handle connections to users, and other nodes
%% that need to handle connections to physical devices. One approach is to create two Scopes: `users' and `devices',
%% where you can register your different types of connections.
%%
%% Scopes are therefore a way to properly namespace your logic, but they also allow to build considerably larger
%% scalable architectures, as it is possible to divide an Erlang cluster into subclusters which hold specific portions
%% of data.
%%
%% Please note any of the methods documented here will raise:
%% <ul>
%% <li>An `error({invalid_scope, Scope})' if the local node has not been added to the specified Scope.</li>
%% <li>An `error({invalid_remote_scope, Scope, RemoteNode})' if the Pid passed in as variable is running on a
%% node that has not been added to the specified Scope, or if the remote scope process is temporarily down.</li>
%% </ul>
%%
%% <h2>Quickstart</h2>
%% <h3>Registry</h3>
%% <h4>Elixir</h4>
%% ```
%% iex> :syn.add_node_to_scopes([:users])
%% :ok
%% iex> pid = self()
%% #PID<0.105.0>
%% iex> :syn.register(:users, "hedy", pid)
%% :ok
%% iex> :syn.lookup(:users, "hedy")
%% {#PID<0.105.0>,:undefined}
%% iex> :syn.register(:users, "hedy", pid, [city: "Milan"])
%% :ok
%% iex> :syn.lookup(:users, "hedy")
%% {#PID<0.105.0>,[city: "Milan"]}
%% iex> :syn.registry_count(:users)
%% 1
%% '''
%% <h4>Erlang</h4>
%% ```
%% 1> syn:add_node_to_scopes([users]).
%% ok
%% 2> Pid = self().
%% <0.93.0>
%% 3> syn:register(users, "hedy", Pid).
%% ok
%% 4> syn:lookup(users, "hedy").
%% {<0.93.0>,undefined}
%% 5> syn:register(users, "hedy", Pid, [{city, "Milan"}]).
%% ok
%% 6> syn:lookup(users, "hedy").
%% {<0.93.0>,[{city, "Milan"}]}
%% 7> syn:registry_count(users).
%% 1
%% '''
%% <h3>Process Groups</h3>
%% <h4>Elixir</h4>
%% ```
%% iex> :syn.add_node_to_scopes([:users])
%% :ok
%% iex> pid = self()
%% #PID<0.88.0>
%% iex> :syn.join(:users, {:italy, :lombardy}, pid)
%% :ok
%% iex> :syn.members(:users, {:italy, :lombardy})
%% [{#PID<0.88.0>,:undefined}]
%% iex> :syn.is_member(:users, {:italy, :lombardy}, pid)
%% true
%% iex> :syn.publish(:users, {:italy, :lombardy}, "hello lombardy!")
%% {:ok,1}
%% iex> flush()
%% Shell got "hello lombardy!"
%% ok
%% '''
%% <h4>Erlang</h4>
%% ```
%% 1> syn:add_node_to_scopes([users]).
%% ok
%% 2> Pid = self().
%% <0.88.0>
%% 3> syn:join(users, {italy, lombardy}, Pid).
%% ok
%% 4> syn:members(users, {italy, lombardy}).
%% [{<0.88.0>,undefined}]
%% 5> syn:is_member(users, {italy, lombardy}, Pid).
%% true
%% 6> syn:publish(users, {italy, lombardy}, "hello lombardy!").
%% {ok,1}
%% 7> flush().
%% Shell got "hello lombardy!"
%% ok
%% '''
%% @end
%% ===================================================================
-module(syn).

%% API
-export([start/0, stop/0]).
%% scopes
-export([node_scopes/0, add_node_to_scopes/1]).
-export([subcluster_nodes/2]).
-export([set_event_handler/1]).
%% registry
-export([lookup/2]).
-export([register/3, register/4, update_registry/3]).
-export([unregister/2]).
-export([registry_count/1, registry_count/2]).
-export([local_registry_count/1]).
%% gen_server via interface
-export([register_name/2, unregister_name/1, whereis_name/1, send/2]).
%% groups
-export([members/2, member/3, is_member/3, update_member/4]).
-export([local_members/2, is_local_member/3]).
-export([join/3, join/4]).
-export([leave/3]).
-export([group_count/1, group_count/2]).
-export([local_group_count/1]).
-export([group_names/1, group_names/2]).
-export([local_group_names/1]).
-export([publish/3]).
-export([local_publish/3]).
-export([multi_call/3, multi_call/4, multi_call_reply/2]).

%% macros
-define(DEFAULT_MULTI_CALL_TIMEOUT_MS, 5000).

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
-spec stop() -> ok | {error, Reason :: term()}.
stop() ->
    application:stop(syn).

%% ----- \/ scopes ---------------------------------------------------
%% @doc Retrieves the Scopes that the node has been added to.
-spec node_scopes() -> [atom()].
node_scopes() ->
    syn_sup:node_scopes().

%% @doc Add the local node to the specified `Scopes'.
%%
%% There are 2 ways to add a node to Scopes. One is by using this method, the other is to set the environment variable `syn'
%% with the key `scopes'. In this latter case, you're probably best off using an application configuration file:
%%
%% You only need to add a node to a scope once.
%% <h3>Elixir</h3>
%% ```
%% config :syn,
%%   scopes: [:devices, :users]
%% '''
%% <h3>Erlang</h3>
%% ```
%% {syn, [
%%   {scopes, [devices, users]}
%% ]}
%% '''
%%
%% <h2>Examples</h2>
%% <h3>Elixir</h3>
%% ```
%% iex> :syn.add_node_to_scopes([:devices])
%% :ok
%% '''
%% <h3>Erlang</h3>
%% ```
%% 1> syn:add_node_to_scopes([devices]).
%% ok
%% '''
-spec add_node_to_scopes(Scopes :: [atom()]) -> ok.
add_node_to_scopes(Scopes) when is_list(Scopes) ->
    lists:foreach(fun(Scope) ->
        syn_sup:add_node_to_scope(Scope)
    end, Scopes).

%% @doc Returns the nodes of the subcluster for the specified Scope.
-spec subcluster_nodes(Manager :: registry | pg, Scope :: atom()) -> [node()].
subcluster_nodes(registry, Scope) ->
    syn_registry:subcluster_nodes(Scope);
subcluster_nodes(pg, Scope) ->
    syn_pg:subcluster_nodes(Scope).

%% @doc Sets the handler module.
%%
%% Please see {@link syn_event_handler} for information on callbacks.
%%
%% There are 2 ways to set a handler module. One is by using this method, the other is to set the environment variable `syn'
%% with the key `event_handler'. In this latter case, you're probably best off using an application configuration file:
%%
%% <h3>Elixir</h3>
%% ```
%% config :syn,
%%   event_handler: MyCustomEventHandler
%% '''
%% <h3>Erlang</h3>
%% ```
%% {syn, [
%%   {event_handler, my_custom_event_handler}
%% ]}
%% '''
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
    application:set_env(syn, event_handler, Module),
    %% ensure event handler is loaded
    syn_event_handler:ensure_event_handler_loaded().

%% ----- \/ registry -------------------------------------------------
%% @doc Looks up a registry entry in the specified Scope.
%%
%% <h2>Examples</h2>
%% <h3>Elixir</h3>
%% ```
%% iex> :syn.register(:devices, "SN-123-456789", self())
%% :ok
%% iex> :syn.lookup(:devices, "SN-123-456789")
%% {#PID<0.105.0>, undefined}
%% '''
%% <h3>Erlang</h3>
%% ```
%% 1> syn:register(devices, "SN-123-456789", self()).
%% ok
%% 2> syn:lookup(devices, "SN-123-456789").
%% {<0.79.0>, undefined}
%% '''
-spec lookup(Scope :: atom(), Name :: term()) -> {pid(), Meta :: term()} | undefined.
lookup(Scope, Name) ->
    syn_registry:lookup(Scope, Name).

%% @equiv register(Scope, Name, Pid, undefined)
%% @end
-spec register(Scope :: atom(), Name :: term(), Pid :: term()) -> ok | {error, Reason :: term()}.
register(Scope, Name, Pid) ->
    register(Scope, Name, Pid, undefined).

%% @doc Registers a process with metadata in the specified Scope.
%%
%% You may register the same process with different names.
%% You may also re-register a process multiple times, for example if you need to update its metadata, however it is
%% recommended to be aware of the implications of updating metadata, see the <a href="options.html#strict_mode">`strict_mode'</a>
%% option for more information.
%%
%% If you want to update a process' metadata by modifying its existing one, you may consider using
%% {@link update_registry/3} instead.
%%
%% When a process gets registered, Syn will automatically monitor it.
%%
%% Possible error reasons:
%% <ul>
%% <li>`not_alive': The `pid()' being registered is not alive.</li>
%% <li>`taken': name is already registered with another `pid()'.</li>
%% <li>`not_self': the method is being called from a process other than `self()',
%% but <a href="options.html#strict_mode">`strict_mode'</a> is enabled.</li>
%% </ul>
%%
%% <h2>Examples</h2>
%% <h3>Elixir</h3>
%% ```
%% iex> :syn.register(:devices, "SN-123-456789", self(), [meta: :one])
%% :ok
%% iex> :syn.lookup(:devices, "SN-123-456789")
%% {#PID<0.105.0>, [meta: :one]}
%% '''
%% <h3>Erlang</h3>
%% ```
%% 1> syn:register(devices, "SN-123-456789", self(), [{meta, one}]).
%% ok
%% 2> syn:lookup(devices, "SN-123-456789")
%% {<0.105.0>,[{meta, one}]}
%% '''
%%
%% Processes can also be registered as `gen_server' names, by usage of via-tuples. This way, you can use the `gen_server'
%% API with these tuples without referring to the Pid directly. If you do so, you MUST use a `gen_server' name
%% in format `{Scope, Name}', i.e. your via tuple will look like `{via, syn, {my_scope, <<"process name">>}}'.
%% See here below for examples.
%% <h2>Examples</h2>
%% <h3>Elixir</h3>
%% ```
%% iex> tuple = {:via, :syn, {:devices, "SN-123-456789"}}.
%% {:via, :syn, {:devices, "SN-123-456789"}}
%% iex> GenServer.start_link(__MODULE__, [], name: tuple)
%% {ok, #PID<0.105.0>}
%% iex> GenServer.call(tuple, :your_message)
%% :your_message
%% '''
%% <h3>Erlang</h3>
%% ```
%% 1> Tuple = {via, syn, {devices, "SN-123-456789"}}.
%% {via, syn, {devices, "SN-123-456789"}}
%% 2> gen_server:start_link(Tuple, your_module, []).
%% {ok, <0.79.0>}
%% 3> gen_server:call(Tuple, your_message).
%% your_message
%% '''
-spec register(Scope :: atom(), Name :: term(), Pid :: pid(), Meta :: term()) -> ok | {error, Reason :: term()}.
register(Scope, Name, Pid, Meta) ->
    syn_registry:register(Scope, Name, Pid, Meta).

%% @doc Updates the registered Name metadata in the specified Scope.
%%
%% Atomically calls Fun with the current metadata, and stores the return value as new metadata. It is
%% recommended to be aware of the implications of updating metadata, see the <a href="options.html#strict_mode">`strict_mode'</a>
%% option for more information.
%%
%% Possible error reasons:
%% <ul>
%% <li>`undefined': The Name cannot be found.</li>
%% <li>`{update_fun, {Reason, Stacktrace}}': An error has occurred in applying the supplied Fun.</li>
%% </ul>
%%
%% <h2>Examples</h2>
%% <h3>Elixir</h3>
%% ```
%% iex> :syn.register(:devices, "SN-123-456789", self(), 10)
%% :ok
%% iex> :syn.update_registry(:devices, "area-1", fn _pid, existing_meta -> existing_meta * 2 end)
%% {:ok, {#PID<0.105.0>, 20}}
%% '''
%% <h3>Erlang</h3>
%% ```
%% 1> syn:register(devices, "SN-123-456789", self(), 10).
%% ok
%% 2> syn:update_registry(devices, "SN-123-456789", fun(_Pid, ExistingMeta) -> ExistingMeta * 2 end).
%% {ok, {<0.69.0>, 20}}
%% '''
-spec update_registry(Scope :: atom(), Name :: term(), Fun :: function()) ->
    {ok, {Pid :: pid(), Meta :: term()}} | {error, Reason :: term()}.
update_registry(Scope, Name, Fun) ->
    syn_registry:update(Scope, Name, Fun).

%% @doc Unregisters a process from specified Scope.
%%
%% Possible error reasons:
%% <ul>
%% <li>`undefined': name is not registered.</li>
%% <li>`race_condition': the local `pid()' does not correspond to the cluster value, so Syn will not succeed
%% unregistering the value and will wait for the cluster to synchronize. This is a rare occasion.</li>
%% </ul>
%%
%% You don't need to unregister names of processes that are about to die, since they are monitored by Syn
%% and they will be removed automatically.
-spec unregister(Scope :: atom(), Name :: term()) -> ok | {error, Reason :: term()}.
unregister(Scope, Name) ->
    syn_registry:unregister(Scope, Name).

%% @doc Returns the count of all registered processes for the specified Scope.
%%
%% <h2>Examples</h2>
%% <h3>Elixir</h3>
%% ```
%% iex> :syn.registry_count(:devices)
%% 512473
%% '''
%% <h3>Erlang</h3>
%% ```
%% 1> syn:registry_count(devices).
%% 512473
%% '''
-spec registry_count(Scope :: atom()) -> non_neg_integer().
registry_count(Scope) ->
    syn_registry:count(Scope).

%% @doc Returns the count of all registered processes for the specified Scope running on a node.
-spec registry_count(Scope :: atom(), Node :: node()) -> non_neg_integer().
registry_count(Scope, Node) ->
    syn_registry:count(Scope, Node).

%% @equiv registry_count(Scope, node())
%% @end
-spec local_registry_count(Scope :: atom()) -> non_neg_integer().
local_registry_count(Scope) ->
    registry_count(Scope, node()).

%% ----- \/ gen_server via module interface --------------------------
%% @private
-spec register_name(Name :: term(), Pid :: pid()) -> yes | no.
register_name({Scope, Name}, Pid) ->
    case register(Scope, Name, Pid) of
        ok -> yes;
        _ -> no
    end.

%% @private
-spec unregister_name(Name :: term()) -> term().
unregister_name({Scope, Name}) ->
    case unregister(Scope, Name) of
        ok -> Name;
        _ -> nil
    end.

%% @private
-spec whereis_name(Name :: term()) -> pid() | undefined.
whereis_name({Scope, Name}) ->
    case lookup(Scope, Name) of
        {Pid, _Meta} -> Pid;
        undefined -> undefined
    end.

%% @private
-spec send(Name :: term(), Message :: term()) -> pid().
send({Scope, Name}, Message) ->
    case whereis_name({Scope, Name}) of
        undefined ->
            {badarg, {{Scope, Name}, Message}};
        Pid ->
            Pid ! Message,
            Pid
    end.

%% ----- \/ groups ---------------------------------------------------
%% @doc Returns the list of all members for GroupName in the specified Scope.
%%
%% <h2>Examples</h2>
%% <h3>Elixir</h3>
%% ```
%% iex> :syn.join(:devices, "area-1", self())
%% :ok
%% iex> :syn.members(:devices, "area-1")
%% [{#PID<0.105.0>, :undefined}]
%% '''
%% <h3>Erlang</h3>
%% ```
%% 1> syn:join(devices, "area-1", self()).
%% ok
%% 2> syn:members(devices, "area-1").
%% [{<0.69.0>, undefined}]
%% '''
-spec members(Scope :: atom(), GroupName :: term()) -> [{Pid :: pid(), Meta :: term()}].
members(Scope, GroupName) ->
    syn_pg:members(Scope, GroupName).

%% @doc Returns the member for GroupName in the specified Scope.
%%
%% <h2>Examples</h2>
%% <h3>Elixir</h3>
%% ```
%% iex> :syn.join(:devices, "area-1", self(), :meta)
%% :ok
%% iex> :syn.member(:devices, "area-1", self())
%% {#PID<0.105.0>, :meta}
%% '''
%% <h3>Erlang</h3>
%% ```
%% 1> syn:join(devices, "area-1", self(), meta).
%% ok
%% 2> syn:member(devices, "area-1", self()).
%% [{<0.69.0>, meta}]
%% '''
-spec member(Scope :: atom(), GroupName :: term(), Pid :: pid()) -> {Pid :: pid(), Meta :: term()} | undefined.
member(Scope, GroupName, Pid) ->
    syn_pg:member(Scope, GroupName, Pid).

%% @doc Returns whether a `pid()' is a member of GroupName in the specified Scope.
-spec is_member(Scope :: atom(), GroupName :: term(), Pid :: pid()) -> boolean().
is_member(Scope, GroupName, Pid) ->
    syn_pg:is_member(Scope, GroupName, Pid).

%% @doc Updates the GroupName member metadata in the specified Scope.
%%
%% Atomically calls Fun with the current metadata, and stores the return value as new metadata. It is
%% recommended to be aware of the implications of updating metadata, see the <a href="options.html#strict_mode">`strict_mode'</a>
%% option for more information.
%%
%% Possible error reasons:
%% <ul>
%% <li>`undefined': The `pid()' cannot be found in GroupName.</li>
%% <li>`{update_fun, {Reason, Stacktrace}}': An error has occurred in applying the supplied Fun.</li>
%% </ul>
%%
%% <h2>Examples</h2>
%% <h3>Elixir</h3>
%% ```
%% iex> :syn.join(:devices, "area-1", self(), 10)
%% :ok
%% iex> :syn.update_member(:devices, "area-1", self(), fn existing_meta -> existing_meta * 2 end)
%% {:ok, {#PID<0.105.0>, 20}}
%% '''
%% <h3>Erlang</h3>
%% ```
%% 1> syn:join(devices, "area-1", self(), 10).
%% ok
%% 2> syn:update_member(devices, "area-1", self(), fun(ExistingMeta) -> ExistingMeta * 2 end).
%% {ok, {<0.69.0>, 20}}
%% '''
-spec update_member(Scope :: atom(), GroupName :: term(), Pid :: pid(), Fun :: function()) ->
    {ok, {Pid :: pid(), Meta :: term()}} | {error, Reason :: term()}.
update_member(Scope, GroupName, Pid, Fun) ->
    syn_pg:update_member(Scope, GroupName, Pid, Fun).

%% @doc Returns the list of all members for GroupName in the specified Scope running on the local node.
-spec local_members(Scope :: atom(), GroupName :: term()) -> [{Pid :: pid(), Meta :: term()}].
local_members(Scope, GroupName) ->
    syn_pg:local_members(Scope, GroupName).

%% @doc Returns whether a `pid()' is a member of GroupName in the specified Scope running on the local node.
-spec is_local_member(Scope :: atom(), GroupName :: term(), Pid :: pid()) -> boolean().
is_local_member(Scope, GroupName, Pid) ->
    syn_pg:is_local_member(Scope, GroupName, Pid).

%% @equiv join(Scope, GroupName, Pid, undefined)
%% @end
-spec join(Scope :: term(), Name :: term(), Pid :: term()) -> ok | {error, Reason :: term()}.
join(Scope, GroupName, Pid) ->
    join(Scope, GroupName, Pid, undefined).

%% @doc Adds a `pid()' with metadata to GroupName in the specified Scope.
%%
%% A process can join multiple groups.
%% A process may also join the same group multiple times, for example if you need to update its metadata, however it is
%% recommended to be aware of the implications of updating metadata, see the <a href="options.html#strict_mode">`strict_mode'</a>
%% option for more information.
%%
%% If you want to update a process' metadata by modifying its existing one, you may consider using
%% {@link update_member/4} instead.
%%
%% When a process joins a group, Syn will automatically monitor it.
%%
%% Possible error reasons:
%% <ul>
%% <li>`not_alive': The `pid()' being added is not alive.</li>
%% <li>`not_self': the method is being called from a process other than `self()',
%% but <a href="options.html#strict_mode">`strict_mode'</a> is enabled.</li>
%% </ul>
%%
%% <h2>Examples</h2>
%% <h3>Elixir</h3>
%% ```
%% iex> :syn.join(:devices, "area-1", self(), [meta: :one])
%% :ok
%% '''
%% <h3>Erlang</h3>
%% ```
%% 1> syn:join(devices, "area-1", self(), [{meta, one}]).
%% ok
%% '''
-spec join(Scope :: atom(), GroupName :: term(), Pid :: pid(), Meta :: term()) -> ok | {error, Reason :: term()}.
join(Scope, GroupName, Pid, Meta) ->
    syn_pg:join(Scope, GroupName, Pid, Meta).

%% @doc Removes a `pid()' from GroupName in the specified Scope.
%%
%% Possible error reasons:
%% <ul>
%% <li>`not_in_group': The `pid()' is not in GroupName for the specified Scope.</li>
%% </ul>
%%
%% You don't need to remove processes that are about to die, since they are monitored by Syn and they will be removed
%% automatically from their groups.
-spec leave(Scope :: atom(), GroupName :: term(), Pid :: pid()) -> ok | {error, Reason :: term()}.
leave(Scope, GroupName, Pid) ->
    syn_pg:leave(Scope, GroupName, Pid).

%% @doc Returns the count of all the groups for the specified Scope.
%%
%% <h2>Examples</h2>
%% <h3>Elixir</h3>
%% ```
%% iex> :syn.group_count(:users)
%% 321778
%% '''
%% <h3>Erlang</h3>
%% ```
%% 1> syn:group_count(users).
%% 321778
%% '''
-spec group_count(Scope :: atom()) -> non_neg_integer().
group_count(Scope) ->
    syn_pg:count(Scope).

%% @doc Returns the count of all the groups for the specified Scope which have at least 1 process running on `Node'.
-spec group_count(Scope :: atom(), Node :: node()) -> non_neg_integer().
group_count(Scope, Node) ->
    syn_pg:count(Scope, Node).

%% @equiv group_count(Scope, node())
%% @end
-spec local_group_count(Scope :: atom()) -> non_neg_integer().
local_group_count(Scope) ->
    group_count(Scope, node()).

%% @doc Returns the group names for the specified Scope.
%%
%% The order of the group names is not guaranteed to be the same on all calls.
%%
%% <h2>Examples</h2>
%% <h3>Elixir</h3>
%% ```
%% iex> :syn.group_names(:users)
%% ["area-1", "area-2"]
%% '''
%% <h3>Erlang</h3>
%% ```
%% 1> syn:group_names(users).
%% ["area-1", "area-2"]
%% '''
-spec group_names(Scope :: atom()) -> [GroupName :: term()].
group_names(Scope) ->
    syn_pg:group_names(Scope).

%% @doc Returns the group names for the specified Scope which have at least 1 process running on `Node'.
%%
%% The order of the group names is not guaranteed to be the same on all calls.
-spec group_names(Scope :: atom(), Node :: node()) -> [GroupName :: term()].
group_names(Scope, Node) ->
    syn_pg:group_names(Scope, Node).

%% @equiv group_names(Scope, node())
%% @end
-spec local_group_names(Scope :: atom()) -> [GroupName :: term()].
local_group_names(Scope) ->
    group_names(Scope, node()).

%% @doc Publish a message to all group members in the specified Scope.
%%
%% `RecipientCount' is the count of the intended recipients.
%%
%% <h2>Examples</h2>
%% <h3>Elixir</h3>
%% ```
%% iex> :syn.join(:users, "area-1", self())
%% :ok
%% iex> :syn.publish(:users, "area-1", :my_message)
%% {:ok,1}
%% iex> flush()
%% Shell got :my_message
%% :ok
%% '''
%% <h3>Erlang</h3>
%% ```
%% 1> syn:join(users, "area-1", self()).
%% ok
%% 2> syn:publish(users, "area-1", my_message).
%% {ok,1}
%% 3> flush().
%% Shell got my_message
%% ok
%% '''
-spec publish(Scope :: atom(), GroupName :: term(), Message :: term()) -> {ok, RecipientCount :: non_neg_integer()}.
publish(Scope, GroupName, Message) ->
    syn_pg:publish(Scope, GroupName, Message).

%% @doc Publish a message to all group members running on the local node in the specified Scope.
%%
%% Works similarly to {@link publish/3} for local processes.
-spec local_publish(Scope :: atom(), GroupName :: term(), Message :: term()) -> {ok, RecipientCount :: non_neg_integer()}.
local_publish(Scope, GroupName, Message) ->
    syn_pg:local_publish(Scope, GroupName, Message).

%% @equiv multi_call(Scope, GroupName, Message, 5000)
%% @end
-spec multi_call(Scope :: atom(), GroupName :: term(), Message :: term()) ->
    {
        Replies :: [{{pid(), Meta :: term()}, Reply :: term()}],
        BadReplies :: [{pid(), Meta :: term()}]
    }.
multi_call(Scope, GroupName, Message) ->
    multi_call(Scope, GroupName, Message, ?DEFAULT_MULTI_CALL_TIMEOUT_MS).

%% @doc Calls all group members in the specified Scope and collects their replies.
%%
%% When this call is issued, all members will receive a tuple in the format:
%%
%% `{syn_multi_call, TestMessage, Caller, Meta}'
%%
%% To reply, every member MUST use the method {@link multi_call_reply/2}.
%%
%% Syn will wait up to the value specified in `Timeout' to receive all replies from the members.
%% The responses will be added to the `Replies' list, while the members that do not reply in time or that crash
%% before sending a reply will be added to the `BadReplies' list.
-spec multi_call(Scope :: atom(), GroupName :: term(), Message :: term(), Timeout :: non_neg_integer()) ->
    {
        Replies :: [{{pid(), Meta :: term()}, Reply :: term()}],
        BadReplies :: [{pid(), Meta :: term()}]
    }.
multi_call(Scope, GroupName, Message, Timeout) ->
    syn_pg:multi_call(Scope, GroupName, Message, Timeout).

%% @doc Allows a group member to reply to a multi call.
%%
%% See {@link multi_call/4} for info.
-spec multi_call_reply(Caller :: term(), Reply :: term()) -> any().
multi_call_reply(Caller, Reply) ->
    syn_pg:multi_call_reply(Caller, Reply).
