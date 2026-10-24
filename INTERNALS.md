# Internals

## Node Authority
In Syn, every node is the authority in terms of the processes that run on it. This means that all register / unregister
/ join / leave operations for a specific process are routed to the syn process (registry, pg) that runs on the
specific process' node.

It is then the responsibility of this node to communicate the operation results and propagate
them to the other nodes.

This serializes per node operations and allows keeping per node consistency.

### What each node has
Every node keeps a copy of the registrations and group memberships held by each of the other nodes, as that node last
told it. A node only changes its copy of another node's data when that node tells it to: with its full data when the two
nodes find each other, and with each change after that.

### Which registration a node shows
A name can be registered on two nodes at once, for example while they can't see each other. A node that holds the name
for one of its own processes shows its own. Any other node shows the most recent of the registrations it has, the node
name breaking ties, so that every node shows the same one. It keeps the others aside: if the one it shows goes, it shows
the next one. A node never hides a registration because it expects another node to drop it.

### Conflicts
When a node holds a name and learns that another node holds it too, it runs the conflict resolution, see
[`syn_event_handler`](syn_event_handler.html). If its own process loses, it drops the name, kills the process if the
default resolution is used, and tells every other node. If its own process wins, it does nothing: the other node drops
its own. Each of the two nodes decides on its own, so the resolution must keep the same process on both. Both nodes
pass it the two registrations in the same order, by node name, so that a resolution that only looks at what it gets
decides the same on both.

### Calls for a process on another node
When the operation is called from another node, the result is sent to the scope process of the calling node
in format `{'3.5', sync_register_reply, ...}` (or `sync_unregister_reply`, `sync_join_reply`, `sync_leave_reply`),
through the same process that sends it all the other data, so that it gets processed in order with it. The calling
scope process applies it like any other sync message and only then replies to the caller, so that its tables are
already updated when the call returns.

If the operation makes the process' node lose a conflict, for example an update that changes what the resolution
compares, the result goes out before the node drops the name, so that the calling node doesn't show the name again
after it was dropped.

If the process' node doesn't know the scope process of the calling node, it first sends it its local data and asks for
the calling node's data, so that the two nodes know each other by the time the result gets there. If the calling node
still doesn't know the scope process of the process' node when the result gets there, it doesn't apply it and the call
returns success: the data of that node reaches it with its snapshot.

If the scope process of the calling node crashes before it applies the result, nothing replies to the caller: the call
exits after the usual 5 second timeout of a call, although the process' node did the operation. The restarted scope
process gets the change with that node's snapshot.

If the call is made from a scope process (i.e. from a callback), that process can't wait for one: the process' node
replies to it right away, and the scope process of the calling node applies the result in the same way when it gets to it.
Such a call returns the result of the process' node: `race_condition` then only comes from the process' node itself,
for example for an unregister of a name it holds for another process.

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

      These tables hold what the node shows, and are owned by the `syn_backbone` process, so that if the related scope
      processes were to crash the data is not lost. In such case, upon respawn the scope process purges the data of all
      remote nodes, rebuilds the monitors for the local processes that are still alive and removes from the tables the
      ones that died meanwhile. The remote data will then get synchronized again.
    * The registry scope process also keeps, in a table of its own, the registrations of other nodes that it doesn't show.
  * The 2 newly created scope processes each join a subcluster (one for registry, one for process groups)
  with the other processes in the Erlang distributed cluster that handle the same Scope (which have the same name).

### Subcluster protocol

#### Messages
  * Everything a scope process sends to other nodes goes through its sender process, so that another node gets it in
    the order it was sent.
  * Syn's scope processes don't open connections between nodes: a message to a node that isn't connected is dropped,
    and that node gets the data again when it connects. There is one narrow exception: if the connection drops between
    the moment a scope process checks it and the moment it starts monitoring the other node's scope process, Erlang
    connects the two nodes again, as it does whenever any process sends something to a node it isn't connected to. With
    the kernel parameter `dist_auto_connect` set to `once`, Erlang doesn't reconnect nodes on its own, and this can't
    happen. A call made through the API for a process on another node connects the nodes, as any call does.
  * Every message carries the scope process that sent it. A node only applies messages from the scope process it knows
    for that node: once it knows the new scope process of a node that restarted, it ignores what the old one sent. A
    late message from the old one can still make the node take it for a while; the old one's DOWN then makes the node
    ask that node for its data again.
  * Messages are tagged with the version of the protocol, `'3.5'`, so that nodes running a version of Syn with another
    protocol ignore each other.

#### Joining

  * Just after initialization, every scope process sends a discovery message in format `{'3.5', discover, self()}`
    to every process with the _same name_ running on all the nodes in the Erlang cluster.
  * Scope processes monitor node events, so when a new node joins the cluster the same discovery message is sent to the
    new node.
  * When a scope process receives the discovery message, it replies with its local data with an ack message in format
    `{'3.5', ack_sync, self(), LocalData}`. If it didn't know the scope process that sent it, it starts monitoring it,
    adds its node to the list of the subcluster nodes, and asks it for its own data unless it already did.
  * When a scope process receives an `ack_sync` message from a scope process it didn't know, it first starts monitoring
    it, adds its node to the list of the subcluster nodes, and sends it its local data, before a conflict resolution
    can change that data.
  * The data in an `ack_sync` replaces everything the scope process had from that node.
  * A discovery or `ack_sync` message from a node this one isn't connected to was sent before the connection dropped:
    it is ignored, and the two nodes find each other again when they reconnect.
  * A scope process from a node whose scope process this one already knows means the other one restarted: the data of
    the old one goes.

#### Leaving

  * When a scope process of a remote node dies, or the connection to its node drops, all the other scope processes are
    notified because they were monitoring it.
  * The data related to the remote node that left the subcluster is removed locally on every node.
  * If the node is still connected when the notification gets handled, its scope process restarted, or the notification
    comes from a connection that dropped and came back: the scope process asks that node for its data again.
