# Syn
**Syn** (short for _synonym_) is a global process registry for Erlang.

## Introduction
Syn is a process registry that has the following features:

 * Global (i.e. a process is uniquely identified with a Key across all the nodes of a cluster).
 * Any term can be used as Key.
 * Fast writes.
 * Automatically handles net splits.


## Notes
In any distributed system you are faced with a consistency challenge, which is often resolved by having one master arbiter performing all write operations (chosen with a mechanism of [leader election](http://en.wikipedia.org/wiki/Leader_election)), or through [atomic transactions](http://en.wikipedia.org/wiki/Atomicity_(database_systems)).

Syn was born for applications of the [IoT](http://en.wikipedia.org/wiki/Internet_of_Things) field. In this context, Keys used to identify a process are often the physical object's unique identifier (for instance, its serial or mac address), and are therefore already defined and unique _before_ hitting the system.  The consistency challenge is less of a problem in this case, since the likelihood of concurrent incoming requests that would register processes with the same Key on different nodes is extremely low and, in most cases, acceptable.

In addition, write speeds were a determining factor in the architecture of Syn.

Therefore, Availability has been chosen over Consistency and Syn is [eventually consistent](http://en.wikipedia.org/wiki/Eventual_consistency).


## Install

If you're using [rebar](https://github.com/rebar/rebar) , add `syn` as a dependency in your project's `rebar.config` file:

```erlang
{syn, ".*", {git, "git://github.com/ostinelli/syn.git", "master"}}
```

Then, get and compile your dependencies:

```bash
$ rebar get-deps
$ rebar compile
```

## Usage

### Setup
Ensure to start Syn from your application. This can be done by either providing it as a dependency in your `.app` file, or by starting it manually:

```erlang
syn:start().
```

### Basic
To register a process:

```erlang
syn:register(Key, Port)
```

To retrieve a Pid for a Key:

```erlang
syn:find(Key)
```

Processes are automatically monitored and removed from the registry if they die.

### Conflict resolution
After a net split, when nodes reconnect, Syn will merge the data from all the nodes in the cluster.

If the same Key was used to register a process on different nodes during a net split, then there will be a conflict. By default, Syn will kill the processes of the node the conflict is being resolved on. The killing of the unwanted process happens by sending a `kill` signal with `exit(Pid, kill)`.

If this is not desired, you can set a resolve callback function to be called for the conflicting items. The resolve function is defined as follows:

```erlang
ResolveFun = fun((Key, {LocalPid, LocalNode}, {RemotePid, RemoteNode}) -> ChosenPid)
Key = term()
LocalPid = RemotePid = ChosenPid = pid()
LocalNode = RemoteNode = atom()
```

Where:
  * `Key` is the conflicting Key.
  * `LocalPid` is the Pid of the process running on the node where the conflict resolution is running (i.e. `LocalNode`, which corresponds to the value returned by `node/1`).
  * `RemotePid` and `RemoteNode` are the Pid and Node of the other conflicting process.

Once the resolve function is defined, you can set it with `syn:resolve_fun/1`.

The following is an example on how to set a resolve function to choose the process running on the remote node, and send a graceful `shutdown` signal to the local process instead of the abrupt killing of the process.

```erlang
%% define the resolve fun
ResolveFun = fun(_Key, {LocalPid, _LocalNode}, {RemotePid, _RemoteNode}) ->
	%% send a shutdown message to the local pid
	LocalPid ! shutdown,
	%% select to keep the remote process
	RemotePid
end,

%% set the fun
syn:resolve_fun(ResolveFun).
```

## Internals
Under the hood, Syn performs dirty reads and writes into a distributed in-memory Mnesia table, synchronized across nodes.

To automatically handle net splits, Syn implements a specialized and simplified version of the mechanisms used in Ulf Wiger's [unsplit](https://github.com/uwiger/unsplit) framework.


## Contributing
So you want to contribute? That's great! Please follow the guidelines below. It will make it easier to get merged in.

Before implementing a new feature, please submit a ticket to discuss what you intend to do. Your feature might already be in the works, or an alternative implementation might have already been discussed.

Do not commit to master in your fork. Provide a clean branch without merge commits. Every pull request should have its own topic branch. In this way, every additional adjustments to the original pull request might be done easily, and squashed with `git rebase -i`. The updated branch will be visible in the same pull request, so there will be no need to open new pull requests when there are changes to be applied.

Ensure to include proper testing. To run Syn tests you simply have to be in the project's root directory and run:

```bash
$ make tests
```
