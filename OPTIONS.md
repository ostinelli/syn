# Options
Syn accepts the following options that can be set as keys in the environment variable `syn`.

## event_handler
Please see [`syn_event_handler`](syn_event_handler.html) for information on callbacks.

The event handler module can be defined either by using the [`set_event_handler/1`](syn.html#set_event_handler/1) method, or
by setting the `event_handler` configuration variable.

#### Elixir

```elixir
config :syn,
  event_handler: MyCustomEventHandler
```

#### Erlang

```erlang
{syn, [
  {event_handler, my_custom_event_handler}
]}
```

## scopes
Please see [`here`](syn.html) for information on Scopes.

Scopes can be defined either by using the [`add_node_to_scopes/1`](syn.html#add_node_to_scopes/1) method, or
by setting the `scopes` configuration variable.

#### Elixir

```elixir
config :syn,
  scopes: [:devices, :users]
```

#### Erlang

```erlang
{syn, [
  {scopes, [devices, users]}
]}
```

## strict_mode
By default, Syn doesn't enforce which process performs the Registry and Process Groups operations:
for instance, a process can be registered by a call running in another process.
While this is fine in standard operations, those that would end up updating a process' metadata
return a `{error, non_strict_update}` tuple when `strict_mode` is not enabled (the default).

This is because enabling any process to update another process' metadata could lead to potential race conditions.

Operations are serialized by the [authority node](internals.html#node-authority) responsible for a process, however
simultaneous requests coming from different processes to update a specific process' metadata would result
in having the metadata of the first incoming request to be overwritten by the second request.
While this doesn't compromise Syn's strict eventual consistency (i.e. the data across the cluster will eventually converge),
an application might overwrite metadata and have unexpected logical consequences.

Imagine for instance that a process A has a metadata of attributes, such as `[{color, "blue"}]`. A different process
might request to update process A's metadata to include size, by setting its metadata to `[{color, "blue"}, {size, 100}]`.
At almost the same time another process issues the request to update process A's metadata to include weight, by setting
its metadata to `[{color, "blue"}, {weight, 1.0}]`. The first request to set size will then be overwritten shortly after
by the second incoming request to set the weight, thus resulting in the loss of the size information,
and the process A' metadata will be propagated to `[{color, "blue"}, {weight, 1.0}]` in all the cluster.

For this reason, if an application needs to update process' metadata, `strict_mode` needs to be turned on.
When enabled, only a process can perform Registry and Process Groups operations for itself.
This basically means that the `Pid` parameter of most methods must be `self()`.

This is a global setting that cannot be specified on a per-scope basis. The same setting SHOULD be set
on every Erlang cluster node running Syn.

#### Elixir
With `strict_mode` turned off (the default):

```elixir
iex> pid = spawn(fn -> receive do _ -> :ok end end)
#PID<0.108.0>
iex> :syn.register(:users, "hedy", pid).
:ok
iex> :syn.register(:users, "hedy", pid).
ok
iex> :syn.register(:users, "hedy", pid, :new_metadata).
{:error, :non_strict_update}
```

With `strict_mode` turned on:

```elixir
iex> pid = spawn(fn -> receive do _ -> :ok end end)
#PID<0.108.0>
iex> :syn.register(:users, "hedy", pid).
{:error, :not_self}
iex> :syn.register(:users, "hedy", self()).
:ok
iex> :syn.register(:users, "hedy", self(), :new_metadata).
:ok
```

#### Erlang
With `strict_mode` turned off (the default):

```erlang
1> Pid = spawn(fun() -> receive _ -> ok end end).
<0.83.0>
2> syn:register(users, "hedy", Pid).
ok
3> syn:register(users, "hedy", Pid).
ok
4> syn:register(users, "hedy", Pid, new_metadata).
{error, non_strict_update}
```

With `strict_mode` turned on:

```erlang
1> Pid = spawn(fun() -> receive _ -> ok end end).
<0.83.0>
2> syn:register(users, "hedy", Pid).
{error, not_self}
3> syn:register(users, "hedy", self()).
ok
4> syn:register(users, "hedy", self(), new_metadata).
ok
```

`strict_mode` can be turned on by setting the `strict_mode` configuration variable.

#### Elixir
```elixir
config :syn,
  strict_mode: true
```

#### Erlang
```erlang
{syn, [
  {strict_mode, true}
]}
```
