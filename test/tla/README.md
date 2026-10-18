# TLA+ Model for Syn Registry

The TLA+ specifications in this directory were authored by [Graham Hay](https://github.com/grahamrhay/syn_tla)
as a formal model of Syn's distributed registry conflict resolution protocol.

## The Bug

Graham's model found an invariant violation (`AllRegistered`) demonstrating a race condition
that produces zombie registry entries — entries pointing at dead processes that persist
indefinitely until the next network partition cycle.

The scenario involves two nodes (n1, n2) and a single name "a":

1. Both nodes register "a" while disconnected (n1 at time T1, n2 at time T2, T2 > T1).
2. The nodes reconnect, exchanging `discover` and `ack_sync` messages.
3. n2 unregisters "a", but this is queued behind the `discover` message in n2's gen_server mailbox.
4. n2 processes `discover` from n1 — sends `ack_sync` containing `{a, Pid2, T2}` (still registered at this point).
5. n1 processes `discover` from n2 — sends `ack_sync` containing `{a, Pid1, T1}`.
6. n1 processes n2's `ack_sync` — conflict resolution: T2 > T1, remote wins. n1 kills Pid1
   and replaces its entry with Pid2. **No broadcast is sent for the losing Pid1.**
7. n2 processes `unregister_on_node` — removes "a", broadcasts `sync_unregister` for Pid2 to n1.
8. n1 processes `sync_unregister` — removes Pid2. Now n1 has no entry for "a".
9. n2 processes n1's stale `ack_sync` (containing `{a, Pid1, T1}`) — no existing entry for "a",
   so `handle_registry_sync` adds it unconditionally. **Zombie entry created.**

The zombie entry on n2 points at Pid1 (dead on n1). n1 has no record of it.
No cleanup message will ever be sent because:

- The monitor for Pid1 on n1 was flushed during conflict resolution (`maybe_demonitor`).
- n1 already removed Pid1 from its tables; no `DOWN` will fire, no `sync_unregister` will be broadcast.

Consequences:

- `syn:lookup(Scope, a)` on n2 returns a dead pid.
- Registering "a" on n2 returns `{error, taken}`.
- The zombie persists until the next disconnect/reconnect cycle purges n1's entries on n2.

## The Fix

In `syn_registry.erl`, in the `resolve_conflict/5` function, the "keep remote" path
(where the remote process wins the conflict) updates the local table and kills the losing
process, but does not broadcast a `sync_unregister` for the loser. The "keep neither" path
already does this. The fix adds the missing broadcast:

```erlang
Pid ->
    %% -> we keep the remote pid
    ...
    %% callbacks
    syn_event_handler:call_event_handler(on_process_unregistered, ...),
    syn_event_handler:call_event_handler(on_process_registered, ...),
    %% broadcast unregister for the losing local pid
    %% so other nodes clean up stale ack_sync data
    syn_gen_scope:broadcast(
        {'3.0', sync_unregister, Name, TablePid, TableMeta, syn_conflict_resolution},
        State
    );
```

This works because of the FIFO guarantee established by PR #87 (routing `ack_sync` through
the sender process, `sender_loop`). Both the stale `ack_sync` and the corrective `sync_unregister`
flow through the same node's `sender_loop`, so the receiver always processes the stale data first
and the cleanup second. The zombie is created momentarily but immediately removed.

Fix applied in [this commit](https://github.com/ostinelli/syn/commit/7716a9885924643ce84bb47cbc36b5efb891e577).

## Calls Made From Another Node

A node can register or unregister a process that lives on another node: the call goes to that node,
which handles it like one for its own processes and sends the usual `sync_register` / `sync_unregister`
to the other nodes, but not to the calling node. The calling node gets the result instead in a
`register_reply` / `unregister_reply`, through the same queue as everything else that node sends it.
Its scope process applies it like a sync message, conflict resolution included, and only then does
the call return: a lookup on the calling node right after the call sees it, and nothing the other
node sent before can undo it. If the calling node resolves a conflict on the name that doesn't keep
the process, the call returns `{error, race_condition}`. A call made from a scope process (i.e. from a
callback) can't wait for one: it gets its reply right away, and the scope process of the calling node
applies the result in the same way when it gets to it.

In the model, `Register` and `Unregister` can be called from the node that runs the process or from
any node that can see it.

When the calling node writes the result into its own table itself, outside of its scope process, the
write isn't lined up with what the other node sends to that scope. That is what happens with nodes
running a version that doesn't support the reply above, until they are upgraded. In those cases an older
`ack_sync` snapshot still waiting in the calling node's scope queue can't remove a name registered
from another node: the calling node marks what it writes from a reply, and reconciliation keeps a
marked entry that is newer than everything in the snapshot, since the snapshot can't know about it yet.
But:

- A name unregistered from another node can come back if an older snapshot still has it.
- An unregister the other node sent before the call can arrive after it, and remove the entry the call
  just wrote for the same process.
- If the calling node processes a `DOWN` for the other node after writing, it drops the entry, and a
  snapshot sent before the call won't bring it back.
- If two nodes register the same name on each other's processes at the same time, each one writes
  the other's process over its own entry, and the conflict is never resolved.

The model doesn't cover these cases.

### DOWN Messages Ahead of Earlier Messages

Erlang only guarantees the order of messages between a pair of processes. When a scope process
restarts, its `DOWN` and the messages of its sender process come from two different processes, so
the `DOWN` could reach another node ahead of messages that were sent before it. The model has no
scope restarts: with `DownOvertakes = TRUE` (see `syn_down_overtakes.cfg`), the `DOWN` of a
`Disconnect` can land anywhere in the inbox instead.

All the invariants still hold, but `ReadYourWrites` doesn't: if the calling node handles the `DOWN`
before the reply, it no longer knows the other node and doesn't apply the reply, so the call returns
`ok` while the name isn't in its table yet. It gets there with the other node's `ack_sync`, once the
two nodes have found each other again. `syn_down_overtakes.cfg` leaves `ReadYourWrites` out for this
reason.

## Running the Model Checker

Requires Java 8+:

```
cd test/tla
java -XX:+UseParallelGC -cp tla2tools.jar tlc2.TLC \
    -metadir /tmp/syn-tla-states \
    -config syn.cfg -workers auto -cleanup syn.tla
```

Use `-config syn_down_overtakes.cfg` for DOWN messages that can arrive ahead of earlier ones.

The model checks these properties:

- **AllRegistered** (invariant): When all messages are processed and all nodes are connected,
  every node's view of registered names matches the global truth.
- **ThereCanBeOnlyOne** (invariant): No name is registered on two different nodes simultaneously
  on any single node's view.
- **ViewsMatchOwners** (invariant): When all messages are processed and all nodes are connected,
  every node has each name on the node that actually runs it.
- **AllMessagesProcessed** (liveness): All message queues eventually drain.
- **ReadYourWrites** (action property): A register call made from another node that returns `ok`
  has the name in the calling node's table. A reply that the calling node applies always does, so this
  fails only when the reply comes from a node the calling node doesn't know (anymore).

The model starts from an already discovered, fully connected subcluster. It then models
membership loss and rediscovery through disconnect/reconnect cycles. This keeps startup
discovery out of scope while covering the protocol races that happen after a known
remote scope process goes down and later rejoins. It only covers the registry, without
registering a process again with other meta.

A node can only have one unregister per name waiting in its inbox. More would just fail with
`{error, undefined}`, and without that limit the inbox can grow forever, so the checker never finishes.

## Unit Tests

`syn_tests.tla` contains unit tests for the TLA+ helper functions (`AllRegisteredForNode`,
`AllRegisteredNames`, `Duplicates`, `MergeRegistries`, `MergeRegistrySnapshot`). Run with:

```
java -cp tla2tools.jar tlc2.TLC -metadir /tmp/syn-tla-unit-states \
    -config syn_tests.cfg syn_tests.tla
```

The `-metadir` arguments keep TLC's disk state outside the repository. This avoids
interference with `make test`, which copies the `test/` directory during compilation.

## Copyright

The TLA+ specifications in this directory were authored by
[Graham Hay](https://github.com/grahamrhay) and are included here with minor modifications
(the bug fix described above). The original model is available at
https://github.com/grahamrhay/syn_tla. All rights to the original work remain with
the author.
