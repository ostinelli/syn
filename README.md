[![Build Status](https://travis-ci.org/ostinelli/syn.svg?branch=master)](https://travis-ci.org/ostinelli/syn)
[![Hex pm](https://img.shields.io/hexpm/v/syn.svg)](https://hex.pm/packages/syn)


# Syn
**Syn** (short for _synonym_) is a global Process Registry and Process Group manager for Erlang.

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


## Install

### Rebar3
If you're using [rebar3](https://github.com/erlang/rebar3), add `syn` as a dependency in your project's `rebar.config` file:

```erlang
{syn, {git, "git://github.com/ostinelli/syn.git", {tag, "1.6.2"}}}
```

Or, if you're using [Hex.pm](https://hex.pm/) as package manager (with the [rebar3_hex](https://github.com/hexpm/rebar3_hex) plugin):

```erlang
{syn, "1.6.2"}
```

Then, compile:

```bash
$ rebar3 compile
```


## Usage

### Setup
Ensure that your application starts Syn. This can be done by either providing it as a dependency in your `.app` file, or by starting it manually:

```erlang
syn:start().
```

Your application will have its own logic on how to connect to the other nodes in the cluster. Once it is connected, ensure that Syn gets initialized (this will set up the underlying mnesia backend):

```erlang
syn:init().
```

> Ensure that Syn is initialized **only once** on a node. Even if the node were to disconnect from the cluster and reconnect again, do not re-initialize it. This would disable Syn from being able to handle conflict resolution automatically.

A possible place to initialize Syn is in the `start/2` function in your main application module, something along the lines of:

```erlang
-module(myapp_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    %% connect to nodes
    connect_nodes(),
    %% init syn
    syn:init(),
    %% start sup
    myapp_sup:start_link().

connect_nodes() ->
	%% list of nodes contained in ENV variable `nodes`
	Nodes = application:get_env(nodes),
	%% connect to nodes
	[net_kernel:connect_node(Node) || Node <- Nodes].
```

Syn is then ready.

> You may prefer to initialize Syn inside of the root supervisor instead. This is particularly true if you are using OTP's `included_applications` feature.


### Process Registry

To register a process:

```erlang
syn:register(Key, Pid) ->
    syn:register(Key, Pid, undefined).
```

```erlang
syn:register(Key, Pid, Meta) -> ok | {error, Error}.

Types:
	Key = any()
	Pid = pid()
	Meta = any()
	Error = taken | pid_already_registered
```

| ERROR | DESC
|-----|-----
| taken | The Key is already taken by another process.
| pid_already_registered | The Pid is already registered with another Key.

> You may re-register a process multiple times, for example if you need to update its metadata.
> When a process gets registered, Syn will automatically monitor it.

Processes can also be registered as `gen_server` names, by usage of via-tuples.
This way, you can use the gen_server API with these tuples without referring to the Pid directly.

```erlang
Tuple = {via, syn, <<"your process name">>}.
gen_server:start_link(Tuple, your_module, []).
gen_server:call(Tuple, your_message).
```

To retrieve a Pid from a Key:

```erlang
syn:find_by_key(Key) -> Pid | undefined.

Types:
	Key = any()
	Pid = pid()
```

To retrieve a Pid from a Key with its metadata:

```erlang
syn:find_by_key(Key, with_meta) -> {Pid, Meta} | undefined.

Types:
	Key = any()
	Pid = pid()
	Meta = any()
```

To retrieve a Key from a Pid:

```erlang
syn:find_by_pid(Pid) -> Key | undefined.

Types:
	Pid = pid()
	Key = any()
```

To retrieve a Key from a Pid with its metadata:

```erlang
syn:find_by_pid(Pid, with_meta) -> {Key, Meta} | undefined.

Types:
	Pid = pid()
	Key = any()
	Meta = any()
```

To unregister a previously registered Key:

```erlang
syn:unregister(Key) -> ok | {error, Error}.

Types:
	Key = any()
	Error = undefined
```

> You don't need to unregister keys of processes that are about to die, since they are monitored by Syn and they will be removed automatically. If you manually unregister a process just before it dies, the callback on process exit (see here below) might not get called.

To retrieve the count of total registered processes running in the cluster:

```erlang
syn:registry_count() -> non_neg_integer().
```

To retrieve the count of total registered processes running on a specific node:

```erlang
syn:registry_count(Node) -> non_neg_integer().

Types:
	Node = atom()
```


### Process Groups

> There's no need to manually create / delete Process Groups, Syn will take care of managing those for you.

To add a process to a group:

```erlang
syn:join(Name, Pid) ->
	syn:join(Name, Pid, undefined).
```

```erlang
syn:join(Name, Pid, Meta) -> ok.

Types:
	Name = any()
	Pid = pid()
	meta = any()
```

> A process can join multiple groups. When a process joins a group, Syn will automatically monitor it.
>
> A process may join the same group multiple times, for example if you need to update its metadata, though it will still be listed only once in it.

To remove a process from a group:

```erlang
syn:leave(Name, Pid) -> ok | {error, Error}.

Types:
	Name = any()
	Pid = pid()
	Error = pid_not_in_group
```

> You don't need to remove processes that are about to die, since they are monitored by Syn and they will be removed automatically from their groups. If you manually remove a process from a group just before it dies, the callback on process exit (see here below) might not get called.

To get a list of the members of a group:

```erlang
syn:get_members(Name) -> [pid()].

Types:
	Name = any()
```

To get a list of the members of a group with their metadata:

```erlang
syn:get_members(Name, with_meta) ->
	[{pid(), Meta}].

Types:
	Name = any()
	Meta = any()
```

> The order of member pids in the returned array is guaranteed to be the same on every node, however it is not guaranteed to match the order of joins.

To know if a process is a member of a group:

```erlang
syn:member(Pid, Name) -> boolean().

Types:
	Pid = pid()
	Name = any()
```

To publish a message to all group members:

```erlang
syn:publish(Name, Message) -> {ok, RecipientCount}.

Types:
	Name = any()
	Message = any()
	RecipientCount = non_neg_integer()
```

> `RecipientCount` is the count of the intended recipients.

To call all group members and get their replies:

```erlang
syn:multi_call(Name, Message) ->
    syn:multi_call(Name, Message, 5000).
```

```erlang
syn:multi_call(Name, Message, Timeout) -> {Replies, BadPids}.

Types:
	Name = any()
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


To get a list of the local members of a group (running on the node):

```erlang
syn:get_local_members(Name) -> [pid()].

Types:
	Name = any()
```

To get a list of the local members of a group with their metadata:

```erlang
syn:get_local_members(Name, with_meta) ->
	[{pid(), Meta}].

Types:
	Name = any()
	Meta = any()
```

> The order of member pids in the returned array is guaranteed to be the same on every node, however it is not guaranteed to match the order of joins.

To publish a message to all local group members:

```erlang
syn:publish_to_local(Name, Message) -> {ok, RecipientCount}.

Types:
	Name = any()
	Message = any()
	RecipientCount = non_neg_integer()
```

> `RecipientCount` is the count of the intended recipients.


## Options
Options can be set in the environment variable `syn`. You're probably best off using an application configuration file (in releases, `sys.config`). The list of all available options is:

```erlang
{syn, [
    %% define callback function on process exit for registry
    {registry_process_exit_callback, [module1, function1]},

    %% define callback function on conflicting process (instead of kill)
    {registry_conflicting_process_callback, [module2, function2]},

    %% define callback function on process exit for groups
    {process_groups_process_exit_callback, [module3, function3]}
]}
```
These options are explained here below.

### Registry options
These allow setting the Process Registry options, and are:

 * `registry_process_exit_callback`
 * `registry_conflicting_process_callback`

#### Callback on process exit
The `registry_process_exit_callback` option allows you to specify the `module` and the `function` of the callback that will be triggered when a registered process exits. This callback will be called only on the node where the process was running.

The callback function is defined as:
```erlang
CallbackFun = fun(Key, Pid, Meta, Reason) -> any().

Types:
	Key = any()
	Pid = pid()
	Meta = any()
	Reason = any()
```
The `Key`, `Pid` and `Meta` are the ones of the process that exited with `Reason`.

For instance, if you want to print a log when a registered process exited:

```erlang
-module(my_callback).
-export([callback_on_process_exit/4]).

callback_on_process_exit(Key, Pid, Meta, Reason) ->
	error_logger:info_msg(
		"Process with Key ~p, Pid ~p and Meta ~p exited with reason ~p~n",
		[Key, Pid, Meta, Reason]
	)
```

Set it in the options:
```erlang
{syn, [
    %% define callback function
    {registry_process_exit_callback, [my_callback, callback_on_process_exit]}
]}
```
If you don't set this option, no callback will be triggered.

> If a process dies as a consequence of a conflict resolution, the process exit callback will still be called but the Key and Meta values will both be `undefined`.


#### Conflict resolution by callback
In case of race conditions, or during net splits, a specific Key might be registered simultaneously on two different nodes. In this case, the cluster experiences a registry naming conflict.

When this happens, Syn will resolve this Process Registry conflict by choosing a single process. Syn will discard the processes running on the node the conflict is being resolved on, and by default will kill it by sending a `kill` signal with `exit(Pid, kill)`.

If this is not desired, you can set the `registry_conflicting_process_callback` option to instruct Syn to trigger a callback, so that you can perform custom operations (such as a graceful shutdown). In this case, the process will not be killed by Syn, and you'll have to decide what to do with it. This callback will be called only on the node where the process is running.

The callback function is defined as:
```erlang
CallbackFun = fun(Key, Pid, Meta) -> any().

Types:
	Key = any()
	Pid = pid()
	Meta = any()
```
The `Key`, `Pid` and `Meta` are the ones of the process that is to be discarded.

For instance, if you want to send a `shutdown` message to the discarded process:

```erlang
-module(my_callback).
-export([callback_on_conflicting_process/3]).

callback_on_conflicting_process(_Key, Pid, _Meta) ->
	Pid ! shutdown
```

Set it in the options:
```erlang
{syn, [
	%% define callback function
	{registry_conflicting_process_callback, [my_callback, callback_on_conflicting_process]}
]}
```

> Important Note: The conflict resolution method SHOULD be defined in the same way across all nodes of the cluster. Having different conflict resolution options on different nodes can have unexpected results.

### Process Groups options
These allow setting the Process Groups options, and are:

 * `process_groups_process_exit_callback`

#### Callback on process exit
The `process_groups_process_exit_callback` option allows you to specify the `module` and the `function` of the callback that will be triggered when a member process of a group exits. This callback will be called only on the node where the process was running.

The callback function is defined as:
```erlang
CallbackFun = fun(Name, Pid, Meta, Reason) -> any().

Types:
	Name = any()
	Pid = pid()
	Meta = any()
	Reason = any()
```
`Name` is the Process Group that the process with `Pid` and `Meta` that exited with `Reason` was a member of.

For instance, if you want to print a log when a member process of a group exited:

```erlang
-module(my_callback).
-export([callback_on_process_exit/4]).

callback_on_process_exit(Name, Pid, Meta, Reason) ->
	error_logger:info_msg(
		"Process with Pid ~p and Meta ~p of Group ~p exited with reason ~p~n",
		[Pid, Meta, Name, Reason]
	)
```

Set it in the options:
```erlang
{syn, [
    %% define callback function
    {process_groups_process_exit_callback, [my_callback, callback_on_process_exit]}
]}
```
If you don't set this option, no callback will be triggered.

> This callback will be called for every Process Group that the process was a member of.


## Internals
Under the hood, Syn performs dirty reads and writes into distributed in-memory Mnesia tables, replicated across all the nodes of the cluster.

To automatically handle conflict resolution, Syn implements a specialized and simplified version of the mechanisms used in Ulf Wiger's [unsplit](https://github.com/uwiger/unsplit) framework.


## Contributing
So you want to contribute? That's great! Please follow the guidelines below. It will make it easier to get merged in.

Before implementing a new feature, please submit a ticket to discuss what you intend to do. Your feature might already be in the works, or an alternative implementation might have already been discussed.

Do not commit to master in your fork. Provide a clean branch without merge commits. Every pull request should have its own topic branch. In this way, every additional adjustments to the original pull request might be done easily, and squashed with `git rebase -i`. The updated branch will be visible in the same pull request, so there will be no need to open new pull requests when there are changes to be applied.

Ensure that proper testing is included. To run Syn tests you simply have to be in the project's root directory and run:

```bash
$ make test
```
