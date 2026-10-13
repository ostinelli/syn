---- MODULE syn ----
EXTENDS FiniteSets, Integers, Sequences, TLC

CONSTANTS Nodes, Names, MaxDisconnections

Symmetry == Permutations(Nodes)

VARIABLES inbox, registered, locally_registered, names, visible_nodes, known_nodes, disconnections, time

vars == <<inbox, registered, locally_registered, names, visible_nodes, known_nodes, disconnections, time>>

AllOtherNodes(n) ==
    Nodes \ {n}

RECURSIVE ReduceStruct(_, _, _)

ReduceStruct(keys, struct, acc) ==
    IF keys = {} THEN acc
    ELSE
        LET k == CHOOSE k \in keys: TRUE
        IN ReduceStruct(keys \ {k}, struct, acc \union DOMAIN struct[k])

AllRegisteredForNode(locals) ==
    ReduceStruct(DOMAIN locals, locals, {})

RECURSIVE AllRegisteredNames(_, _, _)

AllRegisteredNames(nodes, locals, registrations) ==
    IF nodes = {} THEN registrations
    ELSE
        LET n == CHOOSE n \in nodes: TRUE
        IN AllRegisteredNames(nodes \ {n}, locals, registrations \union DOMAIN locals[n][n])

RegisteredElsewhere(node) ==
    AllRegisteredNames(AllOtherNodes(node), locally_registered, {})

RegisteredOnThisNode(node) ==
    AllRegisteredNames({node}, locally_registered, {})

ConnectedKnownNodes(n) ==
    visible_nodes[n] \intersect known_nodes[n]

\* what node o gets when n handles a register or unregister call: a node that made the call
\* from elsewhere gets the reply first, and every node that knows n gets the sync message after it,
\* the caller included
Outgoing(o, n, requester, reply, sync) ==
    LET with_reply == IF o = requester /\ o # n /\ o \in visible_nodes[n] THEN Append(inbox[o], reply) ELSE inbox[o]
    IN IF o \in ConnectedKnownNodes(n) THEN Append(with_reply, sync) ELSE with_reply

HasReply(c) ==
    \E i \in 1..Len(inbox[c]): inbox[c][i].action = "reply"

FirstReply(c) ==
    CHOOSE i \in 1..Len(inbox[c]): inbox[c][i].action = "reply" /\ \A j \in 1..(i - 1): inbox[c][j].action # "reply"

Init ==
    /\ inbox = [n \in Nodes |-> <<>>]
    /\ registered = [n \in Names |-> 0]
    /\ locally_registered = [n1 \in Nodes |-> [n2 \in Nodes |-> <<>>]]
    /\ names = [n \in Nodes |-> Names]
    /\ disconnections = 0
    /\ visible_nodes = [n \in Nodes |-> AllOtherNodes(n)]
    /\ known_nodes = [n \in Nodes |-> AllOtherNodes(n)]
    /\ time = 0

\* register a process that lives on n, called from n itself or from a node that can see n
Register(n) ==
    /\ LET available_names == names[n] \ AllRegisteredForNode(locally_registered[n])
        IN available_names # {}
        /\ \E requester \in {n} \union visible_nodes[n]:
            LET next_val == CHOOSE o \in available_names: TRUE
            IN inbox' = [inbox EXCEPT![n] = Append(inbox[n], [action |-> "register_or_update_on_node", name |-> next_val, requester |-> requester])]
            /\ names' = [names EXCEPT![n] = names[n] \ {next_val}]
    /\ time' = time
    /\ UNCHANGED <<registered, locally_registered, visible_nodes, known_nodes, disconnections>>

RegisterOrUpdateOnNode(n) ==
    /\ Len(inbox[n]) > 0
    /\ Head(inbox[n]).action = "register_or_update_on_node"
    /\ LET message == Head(inbox[n])
        l == [locally_registered[n] EXCEPT![n] = locally_registered[n][n] @@ [r \in {message.name} |-> time]]
        already_registered == message.name \in AllRegisteredForNode(locally_registered[n])
        IN
        (IF already_registered THEN
            \* {error, taken}
            registered' = registered
            /\ locally_registered' = locally_registered
            /\ inbox' = [inbox EXCEPT![n] = Tail(inbox[n])]
        ELSE
            registered' = [registered EXCEPT![message.name] = @ + 1]
            /\ locally_registered' = [locally_registered EXCEPT![n] = l]
            /\ inbox' = [o \in Nodes |-> IF o = n THEN Tail(inbox[n]) ELSE Outgoing(o, n, message.requester,
                [action |-> "reply", result |-> "registered", name |-> message.name, from |-> n, time |-> time],
                [action |-> "sync_register", name |-> message.name, from |-> n, time |-> time]
            )]
        )
    /\ time' = time + 1
    /\ UNCHANGED <<names, visible_nodes, known_nodes, disconnections>>

Merge(left, right) ==
    LET to_keep == {name \in DOMAIN left : (name \notin DOMAIN right \/ left[name] > right[name])}
    IN [name \in to_keep |-> left[name]]

RECURSIVE Flatten(_, _, _)

Flatten(keys, struct, acc) ==
    IF keys = {} THEN acc
    ELSE
        LET k == CHOOSE k \in keys: TRUE
        IN Flatten(keys \ {k}, struct, acc @@ struct[k])

\* Helper: append sync_unregister messages for each name in the set
RECURSIVE AppendSyncUnregisters(_, _, _)

AppendSyncUnregisters(names_to_unregister, queue, from_node) ==
    IF names_to_unregister = {} THEN queue
    ELSE
        LET name == CHOOSE name \in names_to_unregister: TRUE
        IN AppendSyncUnregisters(
            names_to_unregister \ {name},
            Append(queue, [action |-> "sync_unregister", name |-> name, from |-> from_node]),
            from_node
        )

MergeRegistries(local, remote, remote_node) ==
    LET all_registered == Flatten(DOMAIN local, local, << >>)
    IN [r \in DOMAIN local |-> CASE
        (r = remote_node) -> local[r] @@ Merge(remote, all_registered)
        [] OTHER -> Merge(local[r], remote)
    ]

MergeRegistrySnapshot(local, remote, remote_node) ==
    LET all_registered == Flatten(DOMAIN local \ {remote_node}, local, << >>)
    IN [r \in DOMAIN local |-> CASE
        (r = remote_node) -> Merge(remote, all_registered)
        [] OTHER -> Merge(local[r], remote)
    ]

SyncRegister(n) ==
    /\ Len(inbox[n]) > 0
    /\ Head(inbox[n]).action = "sync_register"
    /\ LET message == Head(inbox[n])
        known_sender == message.from \in known_nodes[n]
        conflict == message.name \in DOMAIN locally_registered[n][n]
        remote_wins == conflict /\ message.time > locally_registered[n][n][message.name]
        losers == IF remote_wins THEN {message.name} ELSE {}
        l == MergeRegistries(locally_registered[n], [r \in {message.name} |-> message.time], message.from)
        IN
        (IF known_sender THEN
            locally_registered' = [locally_registered EXCEPT![n] = l]
            /\ registered' = (IF remote_wins THEN [registered EXCEPT![message.name] = @ - 1] ELSE registered)
            /\ inbox' = [o \in Nodes |-> CASE
                (o = n) -> Tail(inbox[n])
                [] (o \in ConnectedKnownNodes(n)) -> AppendSyncUnregisters(losers, inbox[o], n)
                [] OTHER -> inbox[o]
            ]
        ELSE
            \* sync_register is ignored until the remote scope node is discovered
            locally_registered' = locally_registered
            /\ registered' = registered
            /\ inbox' = [inbox EXCEPT![n] = Tail(inbox[n])]
        )
    /\ time' = time
    /\ UNCHANGED <<names, visible_nodes, known_nodes, disconnections>>

ItemToRemove(n) ==
    CHOOSE r \in DOMAIN locally_registered[n][n]: TRUE

\* unregister a name held by a process on n, called from n itself or from a node that can see n
\* and has the name in its own table
\* only one unregister per name can be waiting: more would just fail with {error, undefined}, and
\* without this limit the inbox can grow forever and the model checker never finishes
Unregister(n) ==
    /\ \E requester \in {n} \union visible_nodes[n]:
        /\ Cardinality(DOMAIN locally_registered[requester][n]) > 0
        /\ LET item_to_remove == CHOOSE r \in DOMAIN locally_registered[requester][n]: TRUE
            IN (~\E i \in 1..Len(inbox[n]): inbox[n][i].action = "unregister_on_node" /\ inbox[n][i].name = item_to_remove)
            /\ inbox' = [inbox EXCEPT![n] = Append(inbox[n], [action |-> "unregister_on_node", name |-> item_to_remove, requester |-> requester])]
    /\ time' = time
    /\ UNCHANGED <<registered, locally_registered, visible_nodes, known_nodes, disconnections, names>>

UnregisterOnNode(n) ==
    /\ Len(inbox[n]) > 0
    /\ Head(inbox[n]).action = "unregister_on_node"
    /\ LET message == Head(inbox[n])
        l == [r \in (DOMAIN locally_registered[n][n] \ {message.name}) |-> locally_registered[n][n][r]]
        already_removed == message.name \notin RegisteredOnThisNode(n)
        IN
        (IF already_removed THEN
            \* {error, undefined}
            registered' = registered
            /\ locally_registered' = locally_registered
            /\ inbox' = [inbox EXCEPT![n] = Tail(inbox[n])]
            /\ names' = names
        ELSE
            registered' = [registered EXCEPT![message.name] = @ - 1]
            /\ locally_registered' = [locally_registered EXCEPT![n] = ([locally_registered[n] EXCEPT![n] = l])]
            /\ inbox' = [o \in Nodes |-> IF o = n THEN Tail(inbox[n]) ELSE Outgoing(o, n, message.requester,
                [action |-> "reply", result |-> "unregistered", name |-> message.name, from |-> n],
                [action |-> "sync_unregister", name |-> message.name, from |-> n]
            )]
        )
    /\ time' = time
    /\ UNCHANGED <<names, visible_nodes, known_nodes, disconnections>>

SyncUnregister(n) ==
    /\ Len(inbox[n]) > 0
    /\ Head(inbox[n]).action = "sync_unregister"
    /\ LET message == Head(inbox[n])
        l == [r \in (DOMAIN locally_registered[n][message.from] \ {message.name}) |-> locally_registered[n][message.from][r]]
        IN locally_registered' = [locally_registered EXCEPT![n] = [locally_registered[n] EXCEPT![message.from] = l]]
    /\ inbox' = [inbox EXCEPT![n] = Tail(inbox[n])]
    /\ time' = time
    /\ UNCHANGED <<registered, names, visible_nodes, known_nodes, disconnections>>

ProcessDown(n) ==
    /\ Cardinality(DOMAIN locally_registered[n][n]) > 0
    /\ LET item_to_remove == ItemToRemove(n)
        l == [r \in (DOMAIN locally_registered[n][n] \ {item_to_remove}) |-> locally_registered[n][n][r]]
        IN registered' = [registered EXCEPT![item_to_remove] = @ - 1]
        /\ locally_registered' = [locally_registered EXCEPT![n] = ([locally_registered[n] EXCEPT![n] = l])]
        /\ inbox' = [o \in Nodes |-> CASE
            (o \in ConnectedKnownNodes(n)) -> Append(inbox[o], [action |-> "sync_unregister", name |-> item_to_remove, from |-> n])
            [] OTHER -> inbox[o]
        ]
    /\ time' = time
    /\ UNCHANGED <<names, visible_nodes, known_nodes, disconnections>>

Disconnect(n) ==
    /\ disconnections < MaxDisconnections
    /\ Cardinality(visible_nodes[n]) > 0
    /\ LET other_node == CHOOSE o \in visible_nodes[n]: TRUE
        IN visible_nodes' = [o \in Nodes |-> CASE
            (o = other_node) -> visible_nodes[o] \ {n}
            [] (o = n) -> visible_nodes[o] \ {other_node}
            [] OTHER -> visible_nodes[o]
        ]
        /\ inbox' = [o \in Nodes |-> CASE
            (o = n) -> Append(inbox[o], [action |-> "DOWN", from |-> other_node])
            [] (o = other_node) -> Append(inbox[o], [action |-> "DOWN", from |-> n])
            [] OTHER -> inbox[o]
        ]
    /\ disconnections' = disconnections + 1
    /\ time' = time
    /\ UNCHANGED <<registered, locally_registered, known_nodes, names>>

Reconnect(n) ==
    /\ Cardinality(AllOtherNodes(n) \ visible_nodes[n]) > 0
    /\ LET other_node == CHOOSE o \in (AllOtherNodes(n) \ visible_nodes[n]): TRUE
        IN visible_nodes' = [o \in Nodes |-> CASE
            (o = other_node) -> visible_nodes[o] \union {n}
            [] (o = n) -> visible_nodes[o] \union {other_node}
            [] OTHER -> visible_nodes[o]
        ]
        /\ inbox' = [o \in Nodes |-> CASE
            (o = n) -> Append(inbox[o], [action |-> "discover", from |-> other_node])
            [] (o = other_node) -> Append(inbox[o], [action |-> "discover", from |-> n])
            [] OTHER -> inbox[o]
        ]
    /\ time' = time
    /\ UNCHANGED <<registered, locally_registered, known_nodes, names, disconnections>>

Discover(n) ==
    /\ Len(inbox[n]) > 0
    /\ LET message == Head(inbox[n])
        can_discover == message.from \in visible_nodes[n]
        IN message.action = "discover"
        /\ inbox' = [o \in Nodes |-> CASE
            (o = n) -> Tail(inbox[o])
            [] (can_discover /\ o = message.from) -> Append(inbox[o], [action |-> "ack_sync", local_data |-> locally_registered[n][n], from |-> n])
            [] OTHER -> inbox[o]
        ]
        /\ known_nodes' = (IF can_discover THEN [known_nodes EXCEPT![n] = @ \union {message.from}] ELSE known_nodes)
    /\ time' = time
    /\ UNCHANGED <<registered, names, visible_nodes, locally_registered, disconnections>>

AckSync(n) ==
    /\ Len(inbox[n]) > 0
    /\ Head(inbox[n]).action = "ack_sync"
    /\ LET message == Head(inbox[n])
        can_sync == message.from \in visible_nodes[n]
        l == MergeRegistrySnapshot(locally_registered[n], message.local_data, message.from)
        conflicts == DOMAIN locally_registered[n][n] \intersect DOMAIN message.local_data
        losers == { r \in conflicts : message.local_data[r] > locally_registered[n][n][r] }
        c1 == [c \in losers |-> registered[c] - 1]
        c2 == [c \in { r \in conflicts : locally_registered[n][n][r] > message.local_data[r] } |-> registered[c]]
        IN
        (IF can_sync THEN
            locally_registered' = [locally_registered EXCEPT![n] = l]
            /\ registered' = c1 @@ c2 @@ [r \in (DOMAIN registered \ conflicts) |-> registered[r]]
            /\ known_nodes' = [known_nodes EXCEPT![n] = @ \union {message.from}]
        ELSE
            locally_registered' = locally_registered
            /\ registered' = registered
            /\ known_nodes' = known_nodes
        )
        /\ inbox' = [o \in Nodes |-> CASE
            (o = n) -> Tail(inbox[n])
            [] (can_sync /\ o \in ConnectedKnownNodes(n)) -> AppendSyncUnregisters(losers, inbox[o], n)
            [] OTHER -> inbox[o]
        ]
    /\ time' = time
    /\ UNCHANGED <<names, visible_nodes, disconnections>>

\* the node that made the call writes the result straight into its own table when the reply arrives,
\* without going through its scope. it can do this before its scope gets to messages that were already
\* waiting, but the scope can't get past the reply to anything the other node sent after it.
\* if the caller has the name on a process of another node, it leaves its table alone and waits for
\* the sync_register, which goes through conflict resolution
CallerUpdate(c) ==
    /\ HasReply(c)
    /\ LET i == FirstReply(c)
        reply == inbox[c][i]
        current == locally_registered[c][reply.from]
        held_elsewhere == \E o \in (DOMAIN locally_registered[c] \ {reply.from}): reply.name \in DOMAIN locally_registered[c][o]
        IN locally_registered' = (CASE
            (reply.result = "registered" /\ held_elsewhere) -> locally_registered
            [] (reply.result = "registered") ->
                [locally_registered EXCEPT![c][reply.from] = [r \in {reply.name} |-> reply.time] @@ current]
            [] OTHER ->
                [locally_registered EXCEPT![c][reply.from] = [r \in (DOMAIN current \ {reply.name}) |-> current[r]]]
        )
        /\ inbox' = [inbox EXCEPT![c] = SubSeq(inbox[c], 1, i - 1) \o SubSeq(inbox[c], i + 1, Len(inbox[c]))]
    /\ time' = time
    /\ UNCHANGED <<registered, names, visible_nodes, known_nodes, disconnections>>

Down(n) ==
    /\ Len(inbox[n]) > 0
    /\ Head(inbox[n]).action = "DOWN"
    /\ inbox' = [inbox EXCEPT![n] = Tail(inbox[n])]
    /\ LET message == Head(inbox[n])
        l == [locally_registered[n] EXCEPT![message.from] = <<>>]
        IN locally_registered' = [locally_registered EXCEPT![n] = l]
        /\ known_nodes' = [known_nodes EXCEPT![n] = known_nodes[n] \ {message.from}]
    /\ time' = time
    /\ UNCHANGED <<registered, names, visible_nodes, disconnections>>

Complete(n) ==
    /\ LET available_names == names[n] \ AllRegisteredForNode(locally_registered[n])
        IN available_names = {}
    /\ UNCHANGED <<inbox, registered, names, locally_registered, visible_nodes, known_nodes, disconnections, time>>

Next ==
    /\ \E n \in Nodes:
        \/ Register(n)
        \/ RegisterOrUpdateOnNode(n)
        \/ SyncRegister(n)
        \/ Unregister(n)
        \/ UnregisterOnNode(n)
        \/ SyncUnregister(n)
        \/ ProcessDown(n)
        \/ Disconnect(n)
        \/ Reconnect(n)
        \/ Discover(n)
        \/ AckSync(n)
        \/ Down(n)
        \/ CallerUpdate(n)
        \/ Complete(n)

Spec == Init /\ [][Next]_vars

AllRegistered ==
    \A n \in Nodes:
        LET reg == {r \in DOMAIN registered: registered[r] > 0}
        IN (\A o \in Nodes: Len(inbox[o]) = 0) /\ visible_nodes[n] = AllOtherNodes(n) => AllRegisteredForNode(locally_registered[n]) = reg

RECURSIVE Duplicates(_, _, _)

Duplicates(keys, struct, acc) ==
    IF Cardinality(keys) < 2 THEN acc
    ELSE
        LET k1 == CHOOSE k \in keys: TRUE
        k2 == CHOOSE k \in (keys \ {k1}): TRUE
        duplicates == DOMAIN struct[k1] \intersect DOMAIN struct[k2]
        IN Duplicates(keys \ {k1}, struct, duplicates \union acc)

ThereCanBeOnlyOne ==
    \A n \in Nodes:
        Duplicates(DOMAIN locally_registered[n], locally_registered[n], {}) = {}

AllMessagesProcessed ==
    \A n \in Nodes:
        <>(Len(inbox[n]) = 0)
====
