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
While this is fine in most operations, those that end up updating a process' metadata can potentially
lead to race conditions if caution is not taken.

Just as for simple Key Value stores, proper application design needs to be implemented.
Otherwise, two different processes updating simultaneously the value of a key will end up overwriting each other,
with the last successful write being the data ultimately kept.

Similarly, simultaneous requests coming from different processes to update a specific process' metadata will
result in the last write received by the  [authority node](internals.html#node-authority) being propagated
to the whole cluster.

This can be circumvented by proper application design, for instance by ensuring that a single process
is always responsible for updating a specific process' metadata.

When enabled, Syn's `strict_mode` is a _helper_ which enforces that a process can only update its own metadata.
This basically means that the `Pid` parameter of most methods must be `self()`. Therefore, concurrent requests from
different processes to update another process' metadata will be rejected, which can help to control the flow.

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
