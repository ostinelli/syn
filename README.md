[![Build Status](https://travis-ci.org/ostinelli/syn.svg?branch=master)](https://travis-ci.org/ostinelli/syn) [![Hex pm](https://img.shields.io/hexpm/v/syn.svg)](https://hex.pm/packages/syn)


# Syn (v2)
**Syn** (short for _synonym_) is a global Process Registry and Process Group manager for Erlang and Elixir. Syn automatically manages addition / removal of nodes from the cluster, and is also able to recover from net splits.

## Introduction

##### What is a Process Registry?
A global Process Registry allows registering a process on all the nodes of a cluster with a single Key. Consider this the process equivalent of a DNS server: in the same way you can retrieve an IP address from a domain name, you can retrieve a process from its Key.

Typical Use Case: registering on a system a process that handles a physical device (using its serial number).

##### What is a Process Group?
A global Process Group is a named group which contains many processes, possibly running on different nodes. With the group Name, you can retrieve on any cluster node the list of these processes, or publish a message to all of them. This mechanism allows for Publish / Subscribe patterns.

Typical Use Case: a chatroom.

##### What is Syn?
Syn is a Process Registry and Process Group manager that has the following features:

 * Global Process Registry (i.e. a process is uniquely identified with a Key across all the nodes of a cluster).
 * Global Process Group manager (i.e. a group is uniquely identified with a Name across all the nodes of a cluster).
 * Any term can be used as Key and Name.
 * A message can be published to all members of a Process Group (PubSub mechanism).
 * Fast writes.
 * Automatically handles conflict resolution (such as net splits).
 * Configurable callbacks.
 * Processes are automatically monitored and removed from the Process Registry and Process Groups if they die.

## Notes
In any distributed system you are faced with a consistency challenge, which is often resolved by having one master arbiter performing all write operations (chosen with a mechanism of [leader election](http://en.wikipedia.org/wiki/Leader_election)), or through [atomic transactions](http://en.wikipedia.org/wiki/Atomicity_(database_systems)).

Syn was born for applications of the [IoT](http://en.wikipedia.org/wiki/Internet_of_Things) field. In this context, Keys used to identify a process are often the physical object's unique identifier (for instance, its serial or MAC address), and are therefore already defined and unique _before_ hitting the system.  The consistency challenge is less of a problem in this case, since the likelihood of concurrent incoming requests that would register processes with the same Key is extremely low and, in most cases, acceptable.

In addition, write speeds were a determining factor in the architecture of Syn.

Therefore, Availability has been chosen over Consistency and Syn is [eventually consistent](http://en.wikipedia.org/wiki/Eventual_consistency).

## Setup

### For Elixir
Add it to your deps:

```elixir
defp deps do
  [{:syn, "~> 2.1"}]
end
```

### For Erlang
If you're using [rebar3](https://github.com/erlang/rebar3), add `syn` as a dependency in your project's `rebar.config` file:

```erlang
{deps, [
  {syn, {git, "git://github.com/ostinelli/syn.git", {tag, "2.1.4"}}}
]}.
```
Or, if you're using [Hex.pm](https://hex.pm/) as package manager (with the [rebar3_hex](https://github.com/hexpm/rebar3_hex) plugin):

```erlang
{deps, [
  {syn, "2.1.4"}
]}.
```

Ensure that `syn` is started with your application, for example by adding it in your `.app` file to the list of `applications`:

```erlang
{application, my_app, [
    %% ...
    {applications, [
        kernel,
        stdlib,
        sasl,
        syn,
        %% ...
    ]},
    %% ...
]}.
```

## API

Example code here below is in Erlang. Thanks to Elixir interoperability with Erlang, the equivalent code in Elixir is straightforward.

### Process Registry

To register a process:

```erlang
syn:register(Name, Pid) ->
    syn:register(Name, Pid, undefined).
```

```erlang
syn:register(Name, Pid, Meta) -> ok | {error, Error}.

Types:
    Name = any()
    Pid = pid()
    Meta = any()
    Error = taken
```

| ERROR | DESC
|-----|-----
| taken | The Name is already taken by another process.

> You may re-register a process multiple times, for example if you need to update its metadata. When a process gets registered, Syn will automatically monitor it. You may also register the same process with different names.

Processes can also be registered as `gen_server` names, by usage of via-tuples.
This way, you can use the `gen_server` API with these tuples without referring to the Pid directly.

```erlang
Tuple = {via, syn, <<"your process name">>}.
gen_server:start_link(Tuple, your_module, []).
gen_server:call(Tuple, your_message).
```

To retrieve a Pid from a Name:

```erlang
syn:whereis(Name) -> Pid | undefined.

Types:
    Key = any()
    Pid = pid()
```

To retrieve a Pid from a Name with its metadata:

```erlang
syn:whereis(Key, with_meta) -> {Pid, Meta} | undefined.

Types:
    Key = any()
    Pid = pid()
    Meta = any()
```

To unregister a previously registered Name:

```erlang
syn:unregister(Name) -> ok | {error, Error}.

Types:
    Key = any()
    Error = undefined
```

> You don't need to unregister names of processes that are about to die, since they are monitored by Syn and they will be removed automatically. If you manually unregister a process just before it dies, the callback on process exit (see here below) might not get called.

To register a previously registered Name with a _different_ Pid:

```erlang
syn:unregister_and_register(Name, Pid) ->
    syn:unregister_and_register(Name, Pid, undefined).
```
```erlang
syn:unregister_and_register(Name, Pid, Meta) -> ok.

Types:
    Name = any()
    Pid = pid()
    Meta = any()
```

> Due to Syn being eventually consistent, if you were to sequentially `unregister/1` a name and `register/2,3` a process you might experience a `{error, taken}` response to the latter, since the unregistration may not have yet properly propagated when the registration call is made. This call ensures that the registration succeeds and propagates properly.
>
>Note that the previously registered process will not be killed and will be demonitored, so that the `on_process_exit/4` callback will _not_ be called (even if implemented) when the process dies.

To retrieve the total count of registered names:

```erlang
syn:registry_count() -> non_neg_integer().
```

To retrieve the total count of registered names of processes running on a specific node:

```erlang
syn:registry_count(Node) -> non_neg_integer().

Types:
    Node = atom()
```

> This is a non-optimized call, use for debugging / monitoring purposes only.

### Process Groups

> There's no need to manually create / delete Process Groups, Syn will take care of managing those for you.

To add a process to a group:

```erlang
syn:join(GroupName, Pid) ->
    syn:join(GroupName, Pid, undefined).
```

```erlang
syn:join(GroupName, Pid, Meta) -> ok.

Types:
    GroupName = any()
    Pid = pid()
    meta = any()
```

> A process can join multiple groups. When a process joins a group, Syn will automatically monitor it. A process may join the same group multiple times, for example if you need to update its metadata, though it will still be listed only once in it.

To remove a process from a group:

```erlang
syn:leave(GroupName, Pid) -> ok | {error, Error}.

Types:
    GroupName = any()
    Pid = pid()
    Error = not_in_group
```

> You don't need to remove processes that are about to die, since they are monitored by Syn and they will be removed automatically from their groups.

To get a list of the members of a group:

```erlang
syn:get_members(GroupName) -> [pid()].

Types:
    GroupName = any()
```

To get a list of the members of a group with their metadata:

```erlang
syn:get_members(GroupName, with_meta) ->
    [{pid(), Meta}].

Types:
    GroupName = any()
    Meta = any()
```

> The order of member pids in the returned array is guaranteed to be the same on every node, however it is not guaranteed to match the order of joins.

To know if a process is a member of a group:

```erlang
syn:member(Pid, GroupName) -> boolean().

Types:
    Pid = pid()
    GroupName = any()
```

To get a list of the existing groups:

```erlang
syn:get_group_names() -> [GroupName].

Types:
    GroupName = any()
```

To publish a message to all group members:

```erlang
syn:publish(GroupName, Message) -> {ok, RecipientCount}.

Types:
    GroupName = any()
    Message = any()
    RecipientCount = non_neg_integer()
```

> `RecipientCount` is the count of the _intended_ recipients.

To call all group members and get their replies:

```erlang
syn:multi_call(GroupName, Message) ->
    syn:multi_call(GroupName, Message, 5000).
```

```erlang
syn:multi_call(GroupName, Message, Timeout) -> {Replies, BadPids}.

Types:
    GroupName = any()
    Message = any()
    Timeout = non_neg_integer()
    Replies = [{MemberPid, Reply}]
    BadPids = [MemberPid]
      MemberPid = pid()
      Reply = any()
```

> Syn will wait up to the value specified in `Timeout` to receive all replies from the members. The members that do not reply in time or that crash before sending a reply will be added to the `BadPids` list.

When this call is issued, all members will receive a tuple in the format:

```erlang
{syn_multi_call, CallerPid, Message}

Types:
    CallerPid = pid()
    Message = any()
```

To reply, every member must use the method:

```erlang
syn:multi_call_reply(CallerPid, Reply) -> ok.

Types:
    CallerPid = pid()
    Reply = any()
```

To get a list of the local members of a group (= running on the node):

```erlang
syn:get_local_members(GroupName) -> [pid()].

Types:
    GroupName = any()
```

To get a list of the local members of a group with their metadata:

```erlang
syn:get_local_members(GroupName, with_meta) ->
    [{pid(), Meta}].

Types:
    GroupName = any()
    Meta = any()
```

> The order of member pids in the returned array is guaranteed to be the same on every node, however it is not guaranteed to match the order of joins.

To know if a process is a local member of a group:

```erlang
syn:local_member(Pid, GroupName) -> boolean().

Types:
    Pid = pid()
    GroupName = any()
```

To publish a message to all local group members:

```erlang
syn:publish_to_local(GroupName, Message) -> {ok, RecipientCount}.

Types:
    GroupName = any()
    Message = any()
    RecipientCount = non_neg_integer()
```

> `RecipientCount` is the count of the intended recipients.

To retrieve the total count of groups in the cluster:

```erlang
syn:groups_count() -> non_neg_integer().
```

> This is a non-optimized call, use for debugging / monitoring purposes only.

To retrieve the count of groups that have at least 1 process running on a specific node:

```erlang
syn:groups_count(Node) -> non_neg_integer().

Types:
    Node = atom()
```

> This is a non-optimized call, use for debugging / monitoring purposes only.

## Callbacks
In Syn you can specify a custom callback module if you want to:

  * Receive and handle the event of a registered / joined process' exit.
  * Customize the method to resolve registry naming conflict in case of net splits or race conditions.

### Setup
The callback module can be set in the environment variable `syn`, with the `event_handler` key. You're probably best off using an application configuration file.

#### Elixir
In `config.exs` you can specify your callback module:

```elixir
config :syn,
  event_handler: MyCustomEventHandler
```

In your module you then need to specify the behavior and the callbacks. All callbacks are _optional_, so you just need to define the ones you need.

```elixir
defmodule MyCustomEventHandler do
  @behaviour :syn_event_handler

  @impl true
  @spec on_process_exit(
    name :: any(),
    pid :: pid(),
    meta :: any(),
    reason :: any()
  ) :: any()
  def on_process_exit(name, pid, meta, reason) do
  end

  @impl true
  @spec on_group_process_exit(
    group_name :: any(),
    pid :: pid(),
    meta :: any(),
    reason :: any()
  ) :: any()
  def on_group_process_exit(group_name, pid, meta, reason) do
  end

  @impl true
  @spec resolve_registry_conflict(
    name :: any(),
    {pid1 :: pid(), meta1 :: any()},
    {Pid2 :: pid(), meta2 :: any()}
  ) -> pid_to_keep :: pid()
  def resolve_registry_conflict(name, {pid1, meta1}, {pid2, meta2})
    pid1
  end
end
```
See details about the callback methods here below.

#### Erlang
In `sys.config` you can specify your callback module:

```erlang
{syn, [
    {event_handler, my_custom_event_handler}
]}
```

In your module you then need to specify the behavior and the callbacks. All callbacks are _optional_, so you just need to define the ones you need.

```erlang
-module(my_custom_event_handler).
-behaviour(syn_event_handler).

-export([on_process_exit/4]).
-export([on_group_process_exit/4]).
-export([resolve_registry_conflict/3]).

-spec on_process_exit(
    Name :: any(),
    Pid :: pid(),
    Meta :: any(),
    Reason :: any()
) -> any().
on_process_exit(Name, Pid, Meta, Reason) ->
    ok.

-spec on_group_process_exit(
    GroupName :: any(),
    Pid :: pid(),
    Meta :: any(),
    Reason :: any()
) -> any().
on_group_process_exit(GroupName, Pid, Meta, Reason) ->
    ok.

-spec resolve_registry_conflict(
    Name :: any(),
    {Pid1 :: pid(), Meta1 :: any()},
    {Pid2 :: pid(), Meta2 :: any()}
) -> PidToKeep :: pid().
resolve_registry_conflict(Name, {Pid1, Meta1}, {Pid2, Meta2}) ->
    Pid1.
```

See details about the callback methods here below.

### Callback methods

#### `on_process_exit/4`
Called when a registered process exits. It will be called only on the node where the process was running. If a process was registered under _n_ names, this callback will be called _n_ times (1 per registered name).

#### `on_group_process_exit/4`
Called when a process in a group exits. It will be called only on the node where the process was running. If a process was part of _n_ groups, this callback will be called _n_ times (1 per joined group).

#### `resolve_registry_conflict/3`
In case of net splits or race conditions, a specific Name might get registered simultaneously on two different nodes. In this case, the cluster experiences a registry naming conflict.

When this happens, Syn will resolve this Process Registry conflict by choosing a single process. By default, Syn keeps track of the time a registration takes place with [`erlang:system_time/0`](http://erlang.org/doc/man/erlang.html#system_time-0), compares values between conflicting processes and:

  * Keeps the one with the higher value (the process that was registered more recently).
  * Kills the other process by sending a `kill` signal with `exit(Pid, {syn_resolve_kill, Name, Meta})`.

This is a very simple mechanism that can be imprecise, as system clocks are not perfectly aligned in a cluster. If something more elaborate is desired (such as vector clocks), or if you do not want the discarded process to be killed (i.e. to perform a graceful shutdown), you MAY specify a custom handler that implements this `resolve_registry_conflict/3` callback. To this effect, you may also store additional data to resolve conflicts in the `Meta` field, since it will be passed into the callback for both of the conflicting processes.

If implemented, this method MUST return the `pid()` of the process that you wish to keep. The other process will be _not_ be killed, so you will have to decide what to do with it.

> Important Note: the conflict resolution method SHOULD be defined in the same way across all nodes of the cluster. Having different conflict resolution options on different nodes can have unexpected results.

## Anti-Entropy
Anti-entropy is a mechanism to force alignment between nodes. It isn't needed with Syn in most cases. However, despite Syn's best efforts and under rare conditions, depending on your cluster topology and other factors, it _might_ be possible that registry and groups get misaligned.

> Anti-entropy in Syn is an **experimental** feature. As with every anti-entropy feature, it comes with a cost: during the forced syncing, the local tables will be rebuilt with data that gets sent from other nodes. This takes time, due to the sending of data across nodes and subsequent storage. As an example, a node that handles 1,000,000 local registry / groups processes will have to send data for ~80MB (depending on your metadata's size) to other nodes. During the syncing, Syn might time out some calls. Your mileage may vary, so it is recommended that you benchmark your use case.

### Setup
To activate anti-entropy you need to set in the environment variable `syn` the key `anti_entropy`. You're probably best off using an application configuration file. If you do not specify the `anti_entropy` key, the anti-entropy mechanism will be disabled by default.

#### Elixir
In `config.exs` you can specify your anti-entropy settings:

```elixir
config :syn,
  anti_entropy: [
    registry: [interval: 300, interval_max_deviation: 60],
    groups: [interval: 300, interval_max_deviation: 60]
  ]
```

#### Erlang
In `sys.config` you can specify your anti-entropy settings:

```erlang
{syn, [
    {anti_entropy, [
        {registry, [{interval, 300}, {interval_max_deviation, 60}],
        {groups, [{interval, 300}, {interval_max_deviation, 60}]
    ]}
]}
```

`interval` specifies in seconds the interval between every anti-entropy syncing, while `interval_max_deviation` the max deviation in seconds from the `interval`. For instance, with an `interval` of 300 seconds and an `interval_max_deviation` of 60, anti-entropy will be called with an interval range of 240 to 360 seconds.

### Manual sync
You can force an anti-entropy sync on the whole cluster by calling the following:

```erlang
syn:force_cluster_sync(registry | groups) -> ok.
```

> As per the notes above, in normal conditions Syn doesn't need to be manually synced. This function will force a full mesh sync on all of the cluster and is **experimental**. Use it as a last resort.

## Internals
As of v2.1, Syn uses ETS for memory storage and doesn't have any external dependency. Syn has its own replication and naming conflict resolution mechanisms.

## Contributing
So you want to contribute? That's great! Please follow the guidelines below. It will make it easier to get merged in.

Before implementing a new feature, please submit a ticket to discuss what you intend to do. Your feature might already be in the works, or an alternative implementation might have already been discussed.

Do not commit to master in your fork. Provide a clean branch without merge commits. Every pull request should have its own topic branch. In this way, every additional adjustments to the original pull request might be done easily, and squashed with `git rebase -i`. The updated branch will be visible in the same pull request, so there will be no need to open new pull requests when there are changes to be applied.

Ensure that proper testing is included. To run Syn tests you simply have to be in the project's root directory and run:

```bash
$ make test
```
