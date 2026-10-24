# TLA+ Model of Syn's Registry

`syn.tla` describes how Syn keeps registrations in sync between nodes. TLC, the TLA+ model checker, runs it
through every order in which messages can arrive, with connections dropping, messages getting lost and scope
processes restarting along the way, and checks that the nodes always end up agreeing.

The rules it follows are the ones described in `INTERNALS.md` at the root of the repository.

## What the model contains

- **Claims.** A claim is a registration as held by the node that runs the process. Only that node creates, changes or
  drops its claims. Every node keeps a copy of the claims of the nodes it knows.
- **What a node shows.** A node that holds its own claim for a name shows it. Otherwise it shows the newest claim it
  has a copy of, with node names breaking ties. It never hides a claim because it expects another node to drop it.
- **Conflicts.** When a node holds a claim for a name and gets a copy of another node's claim for it, it asks the
  resolver which process keeps the name. If its own loses, it drops it and tells everyone. If its own wins, it does
  nothing: the other node will drop its own.
- **Messages.** Messages from one scope process to one node arrive in the order they were sent, unless some are lost
  when the connection drops. Nothing else is ordered: messages from different nodes, "went away" notices (DOWN) and
  "connected" notices (nodeup) can arrive in any order, late included.
- **Connections.** A connection can drop: what is already in a mailbox stays, what is on the wire is lost, and what a
  sender hasn't sent yet waits in its queue and is lost if it gets sent before the connection is back. Syn never opens
  a connection itself, and ignores a handshake from a node it isn't connected to.
- **Scope process restarts.** A scope process can crash, and a new one starts later. In between, messages sent to that
  node are lost. The crash loses its mailbox and what its sender hadn't sent; the claims of the node's own processes
  survive, as Syn's tables do. Nodes find each other again by asking for each other's data (`discover`) and sending it
  (`ack_sync`). A node that loses track of another node while still connected to it asks it for its data again.
- **Calls from another node.** A registration or update called on one node for a process on another is handled by the
  process' node, which sends the result to the caller's node like any other message. If the caller's scope process is
  new to it, it sends it its data and asks for the caller node's.

It doesn't model process groups (pg), callbacks, what a call returns, or a process registered under several names.
A call returns what the caller's node shows once it applies the result, so return values, callbacks and process
groups are covered by the Erlang test suites. Monitors are modeled by the scope process they watch: the Erlang code
also checks the monitor reference.

## What it checks

Each of these holds once nothing is left to deliver or handle:

- **Membership**: every running scope process knows the current scope process of every node it's connected to that
  runs one, and has an exact copy of that node's claims; it has nothing from the other nodes.
- **Agreement**: with every node connected and running, all nodes show the same claim for each name, the claim shown
  is still held by its node, and a name that some node holds is shown everywhere.
- **OneOwner**: with every node connected and running, at most one node holds each name.
- **ResolutionBounded**: conflicts only ever make a node drop its claim, and each claim is dropped at most once, so
  there is no endless back and forth.
- **Survivor**: with a resolver that compares things that don't change during the conflict (Syn's default with clocks
  that don't go back, or a start time stored in the metadata), a name that got registered, and whose processes were
  never unregistered and never exited, is still held by someone. Other resolvers can make every node drop it; all
  nodes still agree on that.
- **DeliveredInChannel**: the model's own bookkeeping of what reached a mailbox stays consistent.
- **Termination**: message traffic always stops, and stays stopped, once outside actions stop.

## Running it

Requires Java 11 or later. From this directory:

```
java -XX:+UseParallelGC -cp tla2tools.jar tlc2.TLC -workers auto -deadlock -cleanup \
    -metadir /tmp/syn-tla-states -config syn.cfg syn.tla
```

`-deadlock` is needed because a run that has used up all its outside actions simply stops, which is expected.
`-metadir` keeps TLC's files outside the repository, so that they don't get copied into the test build.

| Config                         | What it covers                                                                   |
|--------------------------------|----------------------------------------------------------------------------------|
| `syn.cfg`                      | Two nodes register the same name, and any connection can drop once.              |
| `syn_conflict.cfg`             | Issue #96: one connection drops twice, the resolver keeps the older process.     |
| `syn_calls.cfg`                | A call from another node, clocks that disagree, a conflict lost after an update. |
| `syn_calls_two.cfg`            | Two calls from other nodes at the same time.                                     |
| `syn_skew.cfg`                 | Clocks that disagree with Syn's default resolver, an update during the conflict. |
| `syn_backward.cfg`             | The default resolver with a clock that moves backwards during the conflict.      |
| `syn_two_names.cfg`            | Two names, a dropped connection, a process exiting.                              |
| `syn_cyclic.cfg`               | Three nodes register the same name, and no process beats both others.            |
| `syn_restart.cfg`              | A scope process restarts, a connection drops, a call from another node.          |
| `syn_termination*.cfg`         | Message traffic always stops, in four smaller setups.                            |

All of them must report `Model checking completed. No error has been found.` See the comment at the top of each file
for what it covers.

### Checking the checks

The files in `mutations/` each switch on a mistake that an earlier version of Syn made, or that the design had to
avoid. Each one must make TLC report a failure: that shows the checks above would catch it.

| Config                                  | The mistake                                                                |
|-----------------------------------------|----------------------------------------------------------------------------|
| `mutations/hide_after_conflict.cfg`     | A node that loses a conflict makes the others hide every claim for the name. |
| `mutations/refresh_winner.cfg`          | The node that keeps its process gives it a new time and tells everyone.    |
| `mutations/withdraw_before_result.cfg`  | The caller of an update hears of the withdrawal before the update.         |
| `mutations/no_rediscover.cfg`           | A node that loses track of a connected node doesn't ask it for its data again. |
| `mutations/no_ask_on_adopt.cfg`         | A node that learns of a new scope process through a call doesn't ask for its data. |

Run them like the others, with `-config mutations/<name>.cfg`.

## History

The first TLA+ model of Syn was written by [Graham Hay](https://github.com/grahamrhay/syn_tla). It modeled the
registry of Syn 3.4 and found a race that left entries pointing at dead processes, which was fixed then. This model
replaces it for the redesigned registry of Syn 3.5; Graham's model remains in the repository history.
