# Internals

## Node Authority
In Syn, every node is the authority in terms of the processes that run on it. This means that all register / unregister
/ join / leave operations for a specific process are routed to the syn process (registry, pg) that runs on the
specific process' node.

It is then the responsibility of this node to communicate the operation results and propagate
them to the other nodes.

This serializes per node operations and allows keeping per node consistency.

When the operation is called from another node, the result is sent to the scope process of the calling node
in format `{'3.0', sync_register_reply, ...}` (or `sync_unregister_reply`, `sync_join_reply`, `sync_leave_reply`),
through the same process that sends it all the other data, so that it gets processed in order with it. The calling
scope process applies it like any other sync message and only then replies to the caller, so that its tables are
already updated when the call returns.

If the process' node doesn't know the calling node yet, it first sends it its local data, as when it receives a
discover message, so that the calling node knows it by the time the result gets there.

If the call is made from a scope process (i.e. from a callback), that process can't wait for one: the process' node
replies to it right away, and the scope process of the calling node applies the result in the same way when it gets to it.
Such a call returns the result of the process' node, and never `race_condition`.

If the process' node runs a version of Syn that does not support this, it replies to the caller directly, and the caller
updates the tables of its node. That node logs the unknown call the first time, and then gets direct calls until it disconnects.

## Scope Subclusters
Syn implements Scopes, which are a way to create namespaced, logical overlay networks running on top of the Erlang
distribution cluster. Nodes that belong to the same Scope will form a "subcluster": they will synchronize data
between themselves, and themselves only.

Note that _all_ of the data related to a Scope will be replicated to every node of a subcluster, so that every
node has a quick read access to it.

### Scope processes
When you add a node to a scope (see [`add_node_to_scopes/1`](syn.html#add_node_to_scopes/1)) i.e. `users`,
the following happens:

  * 2 new `gen_server` processes get created (aka "scope processes"), in the given example named `syn_registry_users` (for registry)
  and `syn_pg_users` (for process groups).
    * 4 new ETS tables get created:
      * `syn_registry_by_name_users` (of type `set`).
      * `syn_registry_by_pid_users` (of type `bag`).
      * `syn_pg_by_name_users` (of type `ordered_set`).
      * `syn_pg_by_pid_users` (of type `ordered_set`).
    
      These tables are owned by the `syn_backbone` process, so that if the related scope processes were to crash the data is not lost.
      In such case, upon respawn the scope process purges the data of all remote nodes, rebuilds the monitors
      for the local processes that are still alive and removes from the tables the ones that died meanwhile.
      The remote data will then get synchronized again.
  * The 2 newly created scope processes each join a subcluster (one for registry, one for process groups)
  with the other processes in the Erlang distributed cluster that handle the same Scope (which have the same name).

### Subcluster protocol

#### Joining

  * Just after initialization, every scope process tries to send a discovery message in format `{'3.0', discover, self()}`
    to every process with the _same name_ running on all the nodes in the Erlang cluster.
  * Scope processes monitor node events, so when a new node joins the cluster the same discovery message is sent to the
    new node.
  * When a scope process receives the discovery message, it:
    * Replies with its local data with an ack message in format `{'3.0', ack_sync, self(), LocalData}`.
    * Starts monitoring the remote scope node process.
    * Adds the remote node to the list of the subcluster nodes.
  * The scope process that receives the `ack_sync` message:
    * If it's an unknown node, it first:
      * Starts monitoring the remote scope node process.
      * Adds the remote node to the list of the subcluster nodes.
      * Sends it its local data with another ack message, before a conflict resolution can change that data.
    * Stores the received data of the remote node.
  
#### Leaving

  * When a scope process of a remote node dies, all the other scope processes are notified because they were monitoring it.
  * The data related to the remote node that left the subcluster is removed locally on every node.
