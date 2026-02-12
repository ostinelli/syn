---- MODULE syn ----
EXTENDS FiniteSets, Integers, Sequences, TLC

CONSTANTS Nodes, Names, MaxDisconnections

Symmetry == Permutations(Nodes)

VARIABLES inbox, registered, locally_registered, names, visible_nodes, states, disconnections, time

vars == <<inbox, registered, locally_registered, names, visible_nodes, states, disconnections, time>>

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

Init ==
    /\ inbox = [n \in Nodes |-> <<>>]
    /\ registered = [n \in Names |-> 0]
    /\ locally_registered = [n1 \in Nodes |-> [n2 \in Nodes |-> <<>>]]
    /\ names = [n \in Nodes |-> Names]
    /\ disconnections = 0
    /\ visible_nodes = [n \in Nodes |-> AllOtherNodes(n)]
    /\ time = 0
    /\ states = <<>>

Register(n) ==
    /\ LET available_names == names[n] \ AllRegisteredForNode(locally_registered[n])
        IN available_names # {}
        /\ LET next_val == CHOOSE o \in available_names: TRUE
            IN inbox' = [inbox EXCEPT![n] = Append(inbox[n], [action |-> "register_or_update_on_node", name |-> next_val])]
            /\ states' = Append(states, <<"Register", n, next_val>>)
            /\ names' = [names EXCEPT![n] = names[n] \ {next_val}]
    /\ time' = time + 1
    /\ UNCHANGED <<registered, locally_registered, visible_nodes, disconnections>>

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
            /\ inbox' = [o \in Nodes |-> CASE
                (o = n) -> Tail(inbox[n])
                [] (o \in visible_nodes[n]) -> Append(inbox[o], [action |-> "sync_register", name |-> message.name, from |-> n, time |-> time])
                [] OTHER -> inbox[o]
            ]
        )
        /\ states' = Append(states, <<"RegisterOrUpdateOnNode", n, message.name>>)
    /\ time' = time + 1
    /\ UNCHANGED <<names, visible_nodes, disconnections>>

Merge(left, right) ==
    LET to_keep == {name \in DOMAIN left : (name \notin DOMAIN right \/ left[name] > right[name])}
    IN [name \in to_keep |-> left[name]]

RECURSIVE Flatten(_, _, _)

Flatten(keys, struct, acc) ==
    IF keys = {} THEN acc
    ELSE
        LET k == CHOOSE k \in keys: TRUE
        IN Flatten(keys \ {k}, struct, acc @@ struct[k])

MergeRegistries(local, remote, remote_node) ==
    LET all_registered == Flatten(DOMAIN local, local, << >>)
    IN [r \in DOMAIN local |-> CASE
        (r = remote_node) -> local[r] @@ Merge(remote, all_registered)
        [] OTHER -> Merge(local[r], remote)
    ]

SyncRegister(n) ==
    /\ Len(inbox[n]) > 0
    /\ Head(inbox[n]).action = "sync_register"
    /\ LET message == Head(inbox[n])
        conflict == message.name \in DOMAIN locally_registered[n][n]
        l == MergeRegistries(locally_registered[n], [r \in {message.name} |-> message.time], message.from)
        IN locally_registered' = [locally_registered EXCEPT![n] = l]
        /\ registered' = IF conflict /\ message.time > locally_registered[n][n][message.name] THEN [registered EXCEPT![message.name] = @ - 1] ELSE registered
    /\ inbox' = [inbox EXCEPT![n] = Tail(inbox[n])]
    /\ time' = time + 1
    /\ states' = Append(states, <<"SyncRegister", n, Head(inbox[n]).name>>)
    /\ UNCHANGED <<names, visible_nodes, disconnections>>

ItemToRemove(n) ==
    CHOOSE r \in DOMAIN locally_registered[n][n]: TRUE

Unregister(n) ==
    /\ Cardinality(DOMAIN locally_registered[n][n]) > 0
    /\ LET item_to_remove == ItemToRemove(n)
        IN inbox' = [inbox EXCEPT![n] = Append(inbox[n], [action |-> "unregister_on_node", name |-> item_to_remove])]
        /\ states' = Append(states, <<"Unregister", n, item_to_remove>>)
    /\ time' = time + 1
    /\ UNCHANGED <<registered, locally_registered, visible_nodes, disconnections, names>>

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
            /\ inbox' = [o \in Nodes |-> CASE
                (o = n) -> Tail(inbox[n])
                [] (o \in visible_nodes[n]) -> Append(inbox[o], [action |-> "sync_unregister", name |-> message.name, from |-> n])
                [] OTHER -> inbox[o]
            ]
        )
        /\ states' = Append(states, <<"UnregisterOnNode", n, message.name>>)
    /\ time' = time + 1
    /\ UNCHANGED <<names, visible_nodes, disconnections>>

SyncUnregister(n) ==
    /\ Len(inbox[n]) > 0
    /\ Head(inbox[n]).action = "sync_unregister"
    /\ LET message == Head(inbox[n])
        l == [r \in (DOMAIN locally_registered[n][message.from] \ {message.name}) |-> locally_registered[n][message.from][r]]
        IN locally_registered' = [locally_registered EXCEPT![n] = [locally_registered[n] EXCEPT![message.from] = l]]
    /\ inbox' = [inbox EXCEPT![n] = Tail(inbox[n])]
    /\ time' = time + 1
    /\ states' = Append(states, <<"SyncUnregister", n, Head(inbox[n]).name>>)
    /\ UNCHANGED <<registered, names, visible_nodes, disconnections>>

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
        /\ states' = Append(states, <<"Disconnect", n, other_node>>)
    /\ disconnections' = disconnections + 1
    /\ time' = time + 1
    /\ UNCHANGED <<registered, locally_registered, names>>

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
        /\ states' = Append(states, <<"Reconnect", n, other_node>>)
    /\ time' = time + 1
    /\ UNCHANGED <<registered, locally_registered, names, disconnections>>

Discover(n) ==
    /\ Len(inbox[n]) > 0
    /\ LET message == Head(inbox[n])
        IN message.action = "discover"
        /\ inbox' = [o \in Nodes |-> CASE
            (o = n) -> Tail(inbox[o])
            [] (o = message.from) -> Append(inbox[o], [action |-> "ack_sync", local_data |-> locally_registered[n][n], from |-> n])
            [] OTHER -> inbox[o]
        ]
        /\ states' = Append(states, <<"Discover", n, message.from>>)
    /\ time' = time + 1
    /\ UNCHANGED <<registered, names, visible_nodes, locally_registered, disconnections>>

AckSync(n) ==
    /\ Len(inbox[n]) > 0
    /\ Head(inbox[n]).action = "ack_sync"
    /\ inbox' = [inbox EXCEPT![n] = Tail(inbox[n])]
    /\ LET message == Head(inbox[n])
        l == MergeRegistries(locally_registered[n], message.local_data, message.from)
        conflicts == DOMAIN locally_registered[n][n] \intersect DOMAIN message.local_data
        c1 == [c \in { r \in conflicts : message.local_data[r] > locally_registered[n][n][r] } |-> registered[c] - 1]
        c2 == [c \in { r \in conflicts : locally_registered[n][n][r] > message.local_data[r] } |-> registered[c]]
        IN locally_registered' = [locally_registered EXCEPT![n] = l]
        /\ registered' = c1 @@ c2 @@ [r \in (DOMAIN registered \ conflicts) |-> registered[r]]
        /\ states' = Append(states, <<"AckSync", n, message.from>>)
    /\ time' = time + 1
    /\ UNCHANGED <<names, visible_nodes, disconnections>>

Down(n) ==
    /\ Len(inbox[n]) > 0
    /\ Head(inbox[n]).action = "DOWN"
    /\ inbox' = [inbox EXCEPT![n] = Tail(inbox[n])]
    /\ LET message == Head(inbox[n])
        l == [locally_registered[n] EXCEPT![message.from] = <<>>]
        IN locally_registered' = [locally_registered EXCEPT![n] = l]
        /\ states' = Append(states, <<"Down", n, message.from>>)
    /\ time' = time + 1
    /\ UNCHANGED <<registered, names, visible_nodes, disconnections>>

Complete(n) ==
    /\ LET available_names == names[n] \ AllRegisteredForNode(locally_registered[n])
        IN available_names = {}
    /\ UNCHANGED <<inbox, registered, names, locally_registered, visible_nodes, disconnections, time, states>>

Next ==
    /\ \E n \in Nodes:
        \/ Register(n)
        \/ RegisterOrUpdateOnNode(n)
        \/ SyncRegister(n)
        \/ Unregister(n)
        \/ UnregisterOnNode(n)
        \/ SyncUnregister(n)
        \/ Disconnect(n)
        \/ Reconnect(n)
        \/ Discover(n)
        \/ AckSync(n)
        \/ Down(n)
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
