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
`multicast_loop`). Both the stale `ack_sync` and the corrective `sync_unregister` flow through
the same node's `multicast_loop`, so the receiver always processes the stale data first and the
cleanup second. The zombie is created momentarily but immediately removed.

Fix applied in [this commit](https://github.com/ostinelli/syn/commit/7716a9885924643ce84bb47cbc36b5efb891e577).

## Calls Made From Another Node

The model only has nodes registering and unregistering their own processes. In the code, a node can
also register or unregister a process that lives on another node: the call goes to that node, and when
the reply comes back the calling node writes the result straight into its own table, so that a lookup
right after the call already sees it. The node that handled the call doesn't send the calling node a
`sync_register` / `sync_unregister`, since it already has the change.

That write doesn't go through the calling node's scope process, so it isn't lined up with what the
other node sends to that scope. When this path was added to the model, TLC found that an older
`ack_sync` snapshot still waiting in the calling node's scope queue could undo it:

- A name registered from another node got removed again when the older snapshot was reconciled.
  This is fixed: the calling node marks what it writes from a reply, and reconciliation keeps a marked
  entry that is newer than everything in the snapshot, since the snapshot can't know about it yet.
  An older snapshot also can't put back an older meta for the same process anymore.
- A name unregistered from another node can come back if the older snapshot still has it.
- An unregister the other node sent before the call can arrive after it, and remove the entry the call
  just wrote for the same process.
- If the calling node processes a `DOWN` for the other node after writing, it drops the entry, and a
  snapshot sent before the call won't bring it back.
- If two nodes register the same name on each other's processes at the same time, each one writes
  the other's process over its own entry, and the conflict is never resolved.

The last four need the other node's updates to reach the calling node too, without the calling
node firing its callbacks twice. They are not fixed yet, and the model doesn't cover this path.

## Running the Model Checker

Requires Java 8+:

```
cd test/tla
java -XX:+UseParallelGC -cp tla2tools.jar tlc2.TLC \
    -metadir /tmp/syn-tla-states \
    -config syn.cfg -workers auto -cleanup syn.tla
```

The model checks three properties:

- **AllRegistered** (invariant): When all messages are processed and all nodes are connected,
  every node's view of registered names matches the global truth.
- **ThereCanBeOnlyOne** (invariant): No name is registered on two different nodes simultaneously
  on any single node's view.
- **AllMessagesProcessed** (liveness): All message queues eventually drain.

The model starts from an already discovered, fully connected subcluster. It then models
membership loss and rediscovery through disconnect/reconnect cycles. This keeps startup
discovery out of scope while covering the protocol races that happen after a known
remote scope process goes down and later rejoins.

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
