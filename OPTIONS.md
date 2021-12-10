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
By default, Syn doesn't enforce which processes perform the Registry and Process Groups operations:
for instance, a process can be registered by a call running in another process.
While this is fine in standard operations, those that end up updating a process' metadata could potentially
lead to race conditions if caution is not taken.

Operations are serialized by the [authority node](internals.html#node-authority) responsible for a process, however
simultaneous requests coming from different processes to update a specific process' metadata can result
in unexpected consequences, even if this doesn't compromise Syn's strict eventual consistency
(i.e. the data across the cluster will still eventually converge).

Imagine for instance that a process A has a metadata of attributes such as `[{color, "blue"}]`. A different process
might request to update process A's metadata to include size, by setting its metadata to `[{color, "blue"}, {size, 100}]`.
At almost the same time another process might also request to update process A's metadata to include weight, by setting
its metadata to `[{color, "blue"}, {weight, 1.0}]`.

These requests will be delivered to the authority node which will treat them sequentially.
Therefore, the first incoming request (for eg. the one that sets the size) will be overwritten shortly after
by the second incoming request (the one that sets the weight), thus resulting in the loss of the `{size, 100}` tuple
in the process' metadata.  The end result will be that process A' metadata will be propagated to the whole cluster as
`[{color, "blue"}, {weight, 1.0}]`.

This can be circumvented by proper application design, for instance by ensuring that a single process
is always responsible for updating a specific process' metadata.

When enabled, Syn's `strict_mode` is a helper to enforce that a process can only update its own metadata.
This basically means that the `Pid` parameter of most methods must be `self()`.

`strict_mode` is a global setting that cannot be specified on a per-scope basis. The same setting SHOULD be set
on every Erlang cluster node running Syn.

#### Elixir
With `strict_mode` turned on:

```elixir
iex> pid = spawn(fn -> receive do _ -> :ok end end)
#PID<0.108.0>
iex> :syn.register(:users, "hedy", pid).
{:error, :not_self}
iex> :syn.register(:users, "hedy", self()).
:ok
```

#### Erlang
With `strict_mode` turned on:

```erlang
1> Pid = spawn(fun() -> receive _ -> ok end end).
<0.83.0>
2> syn:register(users, "hedy", Pid).
{error, not_self}
3> syn:register(users, "hedy", self()).
ok
```

Strict mode can be turned on by setting the `strict_mode` configuration variable.

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
