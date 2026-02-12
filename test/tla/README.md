# TLA+ Model for Syn Registry

The TLA+ specification in this directory is based on [Graham Hay's syn_tla](https://github.com/grahamrhay/syn_tla),
a formal model of Syn's distributed registry conflict resolution protocol.

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

## Running the Model Checker

Requires Java 8+:

```
cd test/tla
java -XX:+UseParallelGC -cp tla2tools.jar tlc2.TLC \
    -config syn.cfg -workers auto -cleanup syn.tla
```

The model checks three properties:

- **AllRegistered** (invariant): When all messages are processed and all nodes are connected,
  every node's view of registered names matches the global truth.
- **ThereCanBeOnlyOne** (invariant): No name is registered on two different nodes simultaneously
  on any single node's view.
- **AllMessagesProcessed** (liveness): All message queues eventually drain.

## Unit Tests

`syn_tests.tla` contains unit tests for the TLA+ helper functions (`AllRegisteredForNode`,
`AllRegisteredNames`, `Duplicates`, `MergeRegistries`). Run with:

```
java -cp tla2tools.jar tlc2.TLC -config syn_tests.cfg syn_tests.tla
```
