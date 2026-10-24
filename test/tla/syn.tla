-------------------------------- MODULE syn --------------------------------
(***************************************************************************)
(* A model of how Syn 3.5 keeps registrations in sync between nodes, as    *)
(* described in INTERNALS.md. TLC checks it against every order in which   *)
(* messages can arrive, with connections dropping and scope processes      *)
(* restarting along the way.                                               *)
(*                                                                         *)
(* A "claim" is a registration as held by the node that runs the process.  *)
(* Every node keeps a copy of the claims of the nodes it knows, and shows  *)
(* one claim per name.                                                     *)
(*                                                                         *)
(* Messages from one scope process to one node arrive in the order they    *)
(* were sent, unless some are lost when the connection drops. Nothing else *)
(* is ordered. Instead of using a mailbox, a scope process takes the next  *)
(* message from any of its incoming channels, which covers every order a   *)
(* mailbox could hold them in.                                             *)
(***************************************************************************)
EXTENDS Naturals, Sequences, FiniteSets, TLC

CONSTANTS
    NONE,               \* a model value meaning "nothing": no claim, no process
    Nodes,              \* the nodes running the scope: 1..N, in the order their names sort
    Names,              \* the names that can be registered
    Times,              \* the clock readings a claim can get; any node can get any of them
    Resolver,           \* how conflicts are decided: "newest", "oldest", "oldest_time", "neither" or "cyclic"
    MonotonicClocks,    \* TRUE: updating a claim never gives it an earlier time
    RegisterNodes,      \* the nodes whose processes get registered
    CutPairs,           \* the pairs of nodes whose connection can drop, as sets {n, m}
    RestartNodes,       \* the nodes whose scope process can restart
    MaxRegister,        \* how many registrations are made on the process' own node
    MaxRemoteCall,      \* how many registrations and updates are called from another node
    MaxUpdate,          \* how many updates are made on the process' own node
    MaxUnregister,      \* how many unregistrations
    MaxExit,            \* how many registered processes exit
    MaxDisconnect,      \* how many times a connection drops
    MaxRestart,         \* how many times a scope process restarts
    \* switches that bring back known mistakes: each must make TLC report a failure, which shows the
    \* checks below would catch it
    HideAfterConflict,      \* a node that loses a conflict makes the others hide every claim for the name
    RefreshWinner,          \* the node that keeps its process gives it a new time and tells everyone
    WithdrawBeforeResult,   \* the caller of an update hears that the claim was withdrawn before hearing the update
    NoRediscover,           \* a node that loses track of a connected node doesn't ask it for its data again
    NoAskOnAdopt            \* a node that learns of a new scope process through a call doesn't ask for its data

ASSUME Nodes = 1..Cardinality(Nodes)
ASSUME RegisterNodes \subseteq Nodes
ASSUME RestartNodes \subseteq Nodes
ASSUME Resolver \in {"newest", "oldest", "oldest_time", "neither", "cyclic"}

Incs == 1..(MaxRestart + 1)
NodeSeq == [i \in 1..Cardinality(Nodes) |-> i]
MaxTime == CHOOSE t \in Times: \A u \in Times: u <= t

VARIABLES
    alive,      \* processes that are running, as <<node, id>>
    own,        \* own[n][nm]: the claim node n holds for name nm, or NONE
    remote,     \* remote[n][m][nm]: n's copy of node m's claim for nm, or NONE
    known,      \* known[n][m]: the scope process n believes is m's, and watches with a monitor, or NONE
    asked,      \* asked[n]: nodes n asked for their data and hasn't heard back from
    inc,        \* inc[n]: how many times n's scope process started; that process is <<n, inc[n]>>
    conn,       \* the pairs of nodes that are connected, as sets {n, m}
    chan,       \* chan[<<n, i, m>>]: messages the i-th scope process of node n sent to node m, not handled yet
    dlv,        \* dlv[k]: how many of the first messages in chan[k] already reached the receiver's mailbox,
                \* so that a dropped connection doesn't lose them
    pdown,      \* pdown[n]: scope processes whose "went away" notice (DOWN) is on its way to n
    pexit,      \* pexit[n]: n's registered processes that exited, with the notice on its way to n's scope process
    pnodeup,    \* pnodeup[n]: nodes that connected to n, with the notice on its way
    pcall,      \* pcall[n]: calls from other nodes on their way to n's scope process
    up,         \* up[n]: n's scope process is running
    nextPid,    \* the id the next new process gets
    counts,     \* how many times each outside action happened so far, and how many claims were created
    resMsgs,    \* how many messages conflict resolutions sent
    held,       \* the names that got registered at some point
    removed     \* the names whose process got unregistered or exited at some point

vars == <<alive, own, remote, known, asked, inc, conn, chan, dlv, pdown, pexit, pnodeup, pcall, up, nextPid, counts,
          resMsgs, held, removed>>

ChanKeys == Nodes \X Incs \X Nodes

Me(n) == <<n, inc[n]>>
ScopeAlive(s) == up[s[1]] /\ inc[s[1]] = s[2]
Connected(n, m) == {n, m} \in conn
NoClaims == [nm \in Names |-> NONE]
\* the length of the longest of the channels in S, 0 if none
Longest(S) == IF S = {} THEN 0 ELSE CHOOSE l \in {Len(chan[k]): k \in S}: \A k \in S: Len(chan[k]) <= l

-----------------------------------------------------------------------------
(* Which claim a node shows for a name *)

\* the newer of two claims from different nodes: the later time, or with equal times the node that sorts last
Newer(c, d) == \/ c.time > d.time
               \/ c.time = d.time /\ c.pid[1] > d.pid[1]

\* a node holding its own claim shows it; otherwise it shows the newest claim it has a copy of
ShownIn(ownN, remoteN, n, nm) ==
    IF ownN[nm] # NONE THEN ownN[nm]
    ELSE LET cs == {remoteN[m][nm]: m \in Nodes \ {n}} \ {NONE}
         IN IF cs = {} THEN NONE ELSE CHOOSE c \in cs: \A d \in cs: c = d \/ Newer(c, d)

Shown(n, nm) == ShownIn(own[n], remote[n], n, nm)

-----------------------------------------------------------------------------
(* Conflicts: which of two processes keeps the name, or NONE for neither. Both nodes involved *)
(* decide it on their own and must get the same answer.                                      *)

PidLess(p, q) == p[2] < q[2]
Beats(a, b) == (a = 2 /\ b = 1) \/ (a = 3 /\ b = 2) \/ (a = 1 /\ b = 3)

Keep(c, d) ==
    CASE Resolver = "newest" ->        \* Syn's default: the newer registration wins
            IF c.time # d.time THEN (IF c.time > d.time THEN c.pid ELSE d.pid)
            ELSE IF PidLess(c.pid, d.pid) THEN d.pid ELSE c.pid
      [] Resolver = "oldest" ->        \* the one started first wins, judged by something that never changes
            IF PidLess(c.pid, d.pid) THEN c.pid ELSE d.pid
      [] Resolver = "oldest_time" ->   \* the older time wins, but an update gives the claim a new time
            IF c.time # d.time THEN (IF c.time < d.time THEN c.pid ELSE d.pid)
            ELSE IF PidLess(c.pid, d.pid) THEN c.pid ELSE d.pid
      [] Resolver = "neither" -> NONE
      [] Resolver = "cyclic" ->        \* like rock-paper-scissors: node 2 beats 1, 3 beats 2, 1 beats 3
            IF Beats(c.pid[1], d.pid[1]) THEN c.pid ELSE d.pid

-----------------------------------------------------------------------------
(* Each step of a scope process works on a copy of its node's data (St), collects the messages *)
(* it sends in st.out, and then saves everything at once (Commit).                             *)

St(n) == [own |-> own[n], remote |-> remote[n], known |-> known[n], asked |-> asked[n], pdown |-> pdown[n],
          out |-> <<>>, res |-> 0, created |-> 0, names |-> {}]

Send(st, m, msg) == [st EXCEPT !.out = Append(@, <<m, msg>>)]

Broadcast(st, msg, excluded) ==
    LET ts == SelectSeq(NodeSeq, LAMBDA m: st.known[m] # NONE /\ m \notin excluded)
    IN [st EXCEPT !.out = @ \o [i \in 1..Len(ts) |-> <<ts[i], msg>>]]

Snapshot(n, st) == [type |-> "ack_sync", from |-> Me(n), data |-> st.own]
Discover(n) == [type |-> "discover", from |-> Me(n)]
ClaimMsg(n, nm, c) == [type |-> "claim", from |-> Me(n), name |-> nm, claim |-> c]
WithdrawMsg(n, nm, p, why) == [type |-> "withdraw", from |-> Me(n), name |-> nm, pid |-> p, why |-> why]

\* n starts watching scope process s of node m, instead of whatever it watched for m before; a "went away"
\* notice still pending from the old one is thrown away
Monitor(st, n, m, s) ==
    [st EXCEPT !.known[m] = s,
               !.pdown = {d \in @: d[1] # m} \cup (IF ScopeAlive(s) THEN {} ELSE {s})]

Forget(st, m) == [st EXCEPT !.remote[m] = NoClaims]

\* n starts treating s as node m's scope process, which it only does while connected to m; if it knew another one
\* for m, that one restarted, so the claims n had from it go
Adopt(st, n, s) ==
    LET m == s[1]
    IN Monitor(IF st.known[m] # NONE /\ st.known[m] # s THEN Forget(st, m) ELSE st, n, m, s)

\* n asks node m for its data, unless it already asked and is waiting for the answer
Ask(st, n, m) ==
    IF m \in st.asked THEN st
    ELSE [Send(st, m, Discover(n)) EXCEPT !.asked = @ \cup {m}]

\* the same, when n learns of m's scope process through a call
AskForCall(st, n, m) == IF NoAskOnAdopt THEN st ELSE Ask(st, n, m)

\* n drops its own claim for nm and tells everyone
Withdraw(st, n, nm, why) ==
    LET p == st.own[nm].pid
    IN Broadcast([st EXCEPT !.own[nm] = NONE], WithdrawMsg(n, nm, p, why), {})

\* n holds a claim for nm and has copies of other nodes' claims for it: n keeps its own only if it wins against
\* every one of them, and otherwise drops it
Resolve(st, n, nm) ==
    LET others == {m \in Nodes \ {n}: st.remote[m][nm] # NONE}
    IN IF st.own[nm] = NONE \/ others = {} THEN st
       ELSE IF \A m \in others: Keep(st.remote[m][nm], st.own[nm]) = st.own[nm].pid
            THEN IF RefreshWinner
                 THEN LET c == [st.own[nm] EXCEPT !.time = MaxTime]
                      IN Broadcast([st EXCEPT !.own[nm] = c, !.res = @ + 1], ClaimMsg(n, nm, c), {})
                 ELSE st
            ELSE [Withdraw(st, n, nm, "conflict") EXCEPT !.res = @ + 1]

RECURSIVE ResolveSet(_, _, _)
ResolveSet(st, n, S) ==
    IF S = {} THEN st
    ELSE LET nm == CHOOSE x \in S: TRUE IN ResolveSet(Resolve(st, n, nm), n, S \ {nm})

RECURSIVE WithdrawSet(_, _, _)
WithdrawSet(st, n, S) ==
    IF S = {} THEN st
    ELSE LET nm == CHOOSE x \in S: TRUE IN WithdrawSet(Withdraw(st, n, nm, "normal"), n, S \ {nm})

\* saves st as node n's data and queues its messages; ch is the channels to add them to, base the counts to
\* add its new claims to
Commit(n, st, ch, base) ==
    /\ own' = [own EXCEPT ![n] = st.own]
    /\ remote' = [remote EXCEPT ![n] = st.remote]
    /\ known' = [known EXCEPT ![n] = st.known]
    /\ asked' = [asked EXCEPT ![n] = st.asked]
    /\ pdown' = [pdown EXCEPT ![n] = st.pdown]
    /\ chan' = [k \in ChanKeys |->
                    IF k[1] = n /\ k[2] = inc[n]
                    THEN LET sel == SelectSeq(st.out, LAMBDA e: e[1] = k[3])
                         IN ch[k] \o [i \in 1..Len(sel) |-> sel[i][2]]
                    ELSE ch[k]]
    /\ resMsgs' = resMsgs + st.res
    /\ counts' = [base EXCEPT !.created = @ + st.created]
    /\ held' = held \cup st.names

-----------------------------------------------------------------------------
(* What a scope process does with each kind of message *)

\* a handshake from a node n isn't connected to was sent before the connection dropped: n ignores it, as the other
\* node asks again once the connection is back
OnDiscover(n, msg, st0) ==
    LET s == msg.from
        m == s[1]
    IN IF ~Connected(n, m) THEN st0
       ELSE IF st0.known[m] = s THEN Send(st0, m, Snapshot(n, st0))
       ELSE Ask(Send(Adopt(st0, n, s), m, Snapshot(n, st0)), n, m)

OnAckSync(n, msg, st0) ==
    LET s == msg.from
        m == s[1]
        \* a node n didn't know gets n's data first, before a conflict decided below can change it
        st1 == IF st0.known[m] = s THEN st0 ELSE Send(Adopt(st0, n, s), m, Snapshot(n, st0))
        st2 == [st1 EXCEPT !.remote[m] = msg.data, !.asked = @ \ {m}]
    IN IF ~Connected(n, m) THEN st0 ELSE ResolveSet(st2, n, Names)

OnClaim(n, msg, st0) ==
    LET m == msg.from[1]
    IN IF st0.known[m] = msg.from
       THEN Resolve([st0 EXCEPT !.remote[m][msg.name] = msg.claim], n, msg.name)
       ELSE st0

OnWithdraw(n, msg, st0) ==
    LET m == msg.from[1]
        nm == msg.name
        cur == st0.remote[m][nm]
    IN IF st0.known[m] = msg.from /\ cur # NONE /\ cur.pid = msg.pid
       THEN IF HideAfterConflict /\ msg.why = "conflict"
            THEN [st0 EXCEPT !.remote = [k \in Nodes |-> [@[k] EXCEPT ![nm] = NONE]]]
            ELSE [st0 EXCEPT !.remote[m][nm] = NONE]
       ELSE st0

Handle(n, msg, st0) ==
    CASE msg.type = "discover" -> OnDiscover(n, msg, st0)
      [] msg.type = "ack_sync" -> OnAckSync(n, msg, st0)
      [] msg.type = "claim" -> OnClaim(n, msg, st0)
      [] msg.type = "withdraw" -> OnWithdraw(n, msg, st0)

\* the scope process of node k[3] handles the next message in channel k
Receive(k) ==
    /\ chan[k] # <<>>
    /\ up[k[3]]
    /\ dlv[k] > 0 \/ Connected(k[1], k[3])
    /\ Commit(k[3], Handle(k[3], Head(chan[k]), St(k[3])), [chan EXCEPT ![k] = Tail(@)], counts)
    /\ dlv' = [dlv EXCEPT ![k] = IF @ > 0 THEN @ - 1 ELSE 0]
    /\ UNCHANGED <<alive, inc, conn, pexit, pnodeup, pcall, up, nextPid, removed>>

\* the next message in channel k that hasn't reached a mailbox is sent while the two nodes are apart, or while the
\* receiving scope process isn't running: it is lost
Lose(k) ==
    /\ Len(chan[k]) > dlv[k]
    /\ ~Connected(k[1], k[3]) \/ ~up[k[3]]
    /\ chan' = [chan EXCEPT ![k] = SubSeq(@, 1, dlv[k]) \o SubSeq(@, dlv[k] + 2, Len(@))]
    /\ UNCHANGED <<alive, own, remote, known, asked, inc, conn, dlv, pdown, pexit, pnodeup, pcall, up, nextPid, counts,
                   resMsgs, held, removed>>

\* if n is connected to the node when the notice arrives, the node didn't go: its scope process restarted, or the
\* notice is from a connection that dropped and came back. n asks whatever scope process runs there now for its data
ReceiveDown(n, s) ==
    /\ s \in pdown[n]
    /\ up[n]
    /\ LET m == s[1]
           st0 == [St(n) EXCEPT !.pdown = @ \ {s}]
           st1 == [Forget(st0, m) EXCEPT !.known[m] = NONE]
           st2 == IF st0.known[m] # s THEN st0
                  ELSE IF Connected(n, m) /\ ~NoRediscover
                       THEN [Send(st1, m, Discover(n)) EXCEPT !.asked = @ \cup {m}]
                       ELSE st1
       IN Commit(n, st2, chan, counts)
    /\ UNCHANGED <<alive, inc, conn, dlv, pexit, pnodeup, pcall, up, nextPid, removed>>

ReceiveExit(n, p) ==
    /\ p \in pexit[n]
    /\ up[n]
    /\ LET st0 == St(n)
       IN Commit(n, WithdrawSet(st0, n, {nm \in Names: st0.own[nm] # NONE /\ st0.own[nm].pid = p}), chan, counts)
    /\ pexit' = [pexit EXCEPT ![n] = @ \ {p}]
    /\ UNCHANGED <<alive, inc, conn, dlv, pnodeup, pcall, up, nextPid, removed>>

ReceiveNodeup(n, m) ==
    /\ m \in pnodeup[n]
    /\ up[n]
    /\ Commit(n, [Send(St(n), m, Discover(n)) EXCEPT !.asked = @ \cup {m}], chan, counts)
    /\ pnodeup' = [pnodeup EXCEPT ![n] = @ \ {m}]
    /\ UNCHANGED <<alive, inc, conn, dlv, pexit, pcall, up, nextPid, removed>>

-----------------------------------------------------------------------------
(* Calls made on one node for a process running on another, handled by the scope process of the *)
(* process' node. The result goes to the caller's node like the other messages; what the caller   *)
(* gets back is decided from what its node shows then, and is checked by the Erlang tests.        *)

\* the times a node can give a new version of claim c
NextTimes(c) == IF MonotonicClocks /\ c # NONE THEN {t \in Times: t >= c.time} ELSE Times

ReceiveCall(y, call) ==
    /\ call \in pcall[y]
    /\ up[y]
    /\ LET x == call.caller
           nm == call.name
           st0 == St(y)
           \* if the caller's scope process is new to y, y sends it its data and asks for the caller node's
           st1 == IF call.requester = NONE \/ st0.known[x] = call.requester \/ ~Connected(y, x) THEN st0
                  ELSE AskForCall(Send(Adopt(st0, y, call.requester), x, Snapshot(y, st0)), y, x)
       IN \E t \in NextTimes(st1.own[nm]):
            LET st2 ==
                  CASE call.pid \notin alive -> st1
                    [] call.kind = "register" ->
                         IF ShownIn(st1.own, st1.remote, y, nm) # NONE THEN st1
                         ELSE LET c == [pid |-> call.pid, time |-> t, ver |-> 1]
                                  st3 == [st1 EXCEPT !.own[nm] = c, !.created = @ + 1, !.names = @ \cup {nm}]
                              IN Send(Broadcast(st3, ClaimMsg(y, nm, c), {x}), x, ClaimMsg(y, nm, c))
                    [] call.kind = "update" ->
                         IF st1.own[nm] = NONE \/ st1.own[nm].pid # call.pid THEN st1
                         ELSE LET c == [st1.own[nm] EXCEPT !.time = t, !.ver = @ + 1]
                                  st3 == Broadcast([st1 EXCEPT !.own[nm] = c], ClaimMsg(y, nm, c), {x})
                              IN IF WithdrawBeforeResult
                                 THEN Send(Resolve(st3, y, nm), x, ClaimMsg(y, nm, c))
                                 ELSE Resolve(Send(st3, x, ClaimMsg(y, nm, c)), y, nm)
            IN Commit(y, st2, chan, counts)
    /\ pcall' = [pcall EXCEPT ![y] = @ \ {call}]
    /\ UNCHANGED <<alive, inc, conn, dlv, pexit, pnodeup, up, nextPid, removed>>

-----------------------------------------------------------------------------
(* Things that happen from outside: calls made by applications, processes exiting, connections *)
(* dropping and coming back, scope processes restarting                                        *)

Register(n) ==
    /\ counts.reg < MaxRegister
    /\ n \in RegisterNodes
    /\ up[n]
    /\ \E nm \in Names, t \in Times:
        /\ Shown(n, nm) = NONE
        /\ LET p == <<n, nextPid>>
               c == [pid |-> p, time |-> t, ver |-> 1]
               st == [St(n) EXCEPT !.own[nm] = c, !.created = 1, !.names = {nm}]
           IN /\ Commit(n, Broadcast(st, ClaimMsg(n, nm, c), {}), chan, [counts EXCEPT !.reg = @ + 1])
              /\ alive' = alive \cup {p}
    /\ nextPid' = nextPid + 1
    /\ UNCHANGED <<inc, conn, dlv, pexit, pnodeup, pcall, up, removed>>

\* the caller's node gives its scope process with the call, if it is running
Requester(x) == IF up[x] THEN Me(x) ELSE NONE

RegisterCall(x, y) ==
    /\ counts.call < MaxRemoteCall
    /\ y \in RegisterNodes
    /\ x # y
    /\ Connected(x, y)
    /\ up[y]
    /\ \E nm \in Names:
        pcall' = [pcall EXCEPT ![y] = @ \cup {[id |-> counts.call + 1, kind |-> "register", name |-> nm,
                                                pid |-> <<y, nextPid>>, caller |-> x, requester |-> Requester(x)]}]
    /\ alive' = alive \cup {<<y, nextPid>>}
    /\ nextPid' = nextPid + 1
    /\ counts' = [counts EXCEPT !.call = @ + 1]
    /\ UNCHANGED <<own, remote, known, asked, inc, conn, chan, dlv, pdown, pexit, pnodeup, up, resMsgs, held, removed>>

\* an update called on node x for the process x shows under nm, which runs on node y
UpdateCall(x, y) ==
    /\ counts.call < MaxRemoteCall
    /\ x # y
    /\ Connected(x, y)
    /\ up[y]
    /\ \E nm \in Names:
        /\ Shown(x, nm) # NONE
        /\ Shown(x, nm).pid[1] = y
        /\ pcall' = [pcall EXCEPT ![y] = @ \cup {[id |-> counts.call + 1, kind |-> "update", name |-> nm,
                                                   pid |-> Shown(x, nm).pid, caller |-> x, requester |-> Requester(x)]}]
    /\ counts' = [counts EXCEPT !.call = @ + 1]
    /\ UNCHANGED <<alive, own, remote, known, asked, inc, conn, chan, dlv, pdown, pexit, pnodeup, up, nextPid, resMsgs,
                   held, removed>>

Update(n) ==
    /\ counts.upd < MaxUpdate
    /\ up[n]
    /\ \E nm \in Names:
        /\ own[n][nm] # NONE
        /\ own[n][nm].pid \in alive
        /\ \E t \in NextTimes(own[n][nm]):
            LET c == [own[n][nm] EXCEPT !.time = t, !.ver = @ + 1]
            IN Commit(n, Resolve(Broadcast([St(n) EXCEPT !.own[nm] = c], ClaimMsg(n, nm, c), {}), n, nm),
                      chan, [counts EXCEPT !.upd = @ + 1])
    /\ UNCHANGED <<alive, inc, conn, dlv, pexit, pnodeup, pcall, up, nextPid, removed>>

Unregister(n) ==
    /\ counts.unreg < MaxUnregister
    /\ up[n]
    /\ \E nm \in Names:
        /\ own[n][nm] # NONE
        /\ Commit(n, Withdraw(St(n), n, nm, "normal"), chan, [counts EXCEPT !.unreg = @ + 1])
        /\ removed' = removed \cup {nm}
    /\ UNCHANGED <<alive, inc, conn, dlv, pexit, pnodeup, pcall, up, nextPid>>

\* a process exits; if it is registered, its node's scope process hears of it, if it is running
Exit(p) ==
    /\ counts.exit < MaxExit
    /\ p \in alive
    /\ LET names == {nm \in Names: own[p[1]][nm] # NONE /\ own[p[1]][nm].pid = p}
       IN /\ pexit' = IF names # {} /\ up[p[1]] THEN [pexit EXCEPT ![p[1]] = @ \cup {p}] ELSE pexit
          /\ removed' = removed \cup names
    /\ alive' = alive \ {p}
    /\ counts' = [counts EXCEPT !.exit = @ + 1]
    /\ UNCHANGED <<own, remote, known, asked, inc, conn, chan, dlv, pdown, pnodeup, pcall, up, nextPid, resMsgs, held>>

\* the connection between n and m drops: messages already in a mailbox stay, messages on the wire are lost, and
\* messages a sender hasn't sent yet stay in its queue
Disconnect(n, m) ==
    /\ counts.disc < MaxDisconnect
    /\ {n, m} \in CutPairs
    /\ Connected(n, m)
    /\ LET k1 == <<n, inc[n], m>>
           k2 == <<m, inc[m], n>>
           \* the sender of a scope process that restarted is gone: what it left is in a mailbox or on the wire
           olds == {k \in ChanKeys: ((k[1] = n /\ k[3] = m) \/ (k[1] = m /\ k[3] = n)) /\ k # k1 /\ k # k2 /\ Len(chan[k]) > dlv[k]}
       IN \E a1, b1 \in dlv[k1]..Len(chan[k1]), a2, b2 \in dlv[k2]..Len(chan[k2]), keep \in [olds -> 0..Longest(olds)]:
            /\ a1 <= b1 /\ a2 <= b2
            /\ \A k \in olds: dlv[k] <= keep[k] /\ keep[k] <= Len(chan[k])
            \* nothing reaches the mailbox of a scope process that isn't running
            /\ ~up[m] => a1 = 0
            /\ ~up[n] => a2 = 0
            /\ \A k \in olds: ~up[k[3]] => keep[k] = 0
            /\ chan' = [k \in ChanKeys |->
                           IF k = k1 THEN SubSeq(chan[k], 1, a1) \o SubSeq(chan[k], b1 + 1, Len(chan[k]))
                           ELSE IF k = k2 THEN SubSeq(chan[k], 1, a2) \o SubSeq(chan[k], b2 + 1, Len(chan[k]))
                           ELSE IF k \in olds THEN SubSeq(chan[k], 1, keep[k])
                           ELSE chan[k]]
            /\ dlv' = [k \in ChanKeys |->
                          IF k = k1 THEN a1
                          ELSE IF k = k2 THEN a2
                          ELSE IF k \in olds THEN keep[k]
                          ELSE dlv[k]]
    /\ conn' = conn \ {{n, m}}
    /\ pdown' = [o \in Nodes |->
                    IF o \in {n, m} /\ up[o] /\ known[o][IF o = n THEN m ELSE n] # NONE
                    THEN pdown[o] \cup {known[o][IF o = n THEN m ELSE n]}
                    ELSE pdown[o]]
    /\ \E keptN \in SUBSET {c \in pcall[n]: c.caller = m}, keptM \in SUBSET {c \in pcall[m]: c.caller = n}:
        pcall' = [o \in Nodes |->
                     IF o = n THEN {c \in pcall[n]: c.caller # m} \cup keptN
                     ELSE IF o = m THEN {c \in pcall[m]: c.caller # n} \cup keptM
                     ELSE pcall[o]]
    /\ counts' = [counts EXCEPT !.disc = @ + 1]
    /\ UNCHANGED <<alive, own, remote, known, asked, inc, pexit, pnodeup, up, nextPid, resMsgs, held, removed>>

Reconnect(n, m) ==
    /\ n # m
    /\ ~Connected(n, m)
    /\ conn' = conn \cup {{n, m}}
    /\ pnodeup' = [pnodeup EXCEPT ![n] = IF up[n] THEN @ \cup {m} ELSE @, ![m] = IF up[m] THEN @ \cup {n} ELSE @]
    /\ UNCHANGED <<alive, own, remote, known, asked, inc, chan, dlv, pdown, pexit, pcall, up, nextPid, counts, resMsgs,
                   held, removed>>

\* the scope process of n is killed: its mailbox is lost, and so is what its sender hadn't sent yet; the nodes
\* watching it get a DOWN. Syn's tables, and so the claims n holds, survive
Crash(n) ==
    /\ counts.restart < MaxRestart
    /\ n \in RestartNodes
    /\ up[n]
    /\ LET old == Me(n)
           outgoing == {k \in ChanKeys: k[1] = n /\ k[2] = inc[n] /\ k[3] # n /\ Len(chan[k]) > dlv[k]}
           incoming == {k \in ChanKeys: k[3] = n /\ k[1] # n}
           \* while connected, any number of the messages sent to n can be in its mailbox already
           open == {k \in incoming: Connected(k[1], n) /\ Len(chan[k]) > dlv[k]}
       IN /\ \E keep \in [outgoing -> 0..Longest(outgoing)], lost \in [open -> 0..Longest(open)]:
               /\ \A k \in outgoing: dlv[k] <= keep[k] /\ keep[k] <= Len(chan[k])
               /\ \A k \in open: dlv[k] <= lost[k] /\ lost[k] <= Len(chan[k])
               /\ chan' = [k \in ChanKeys |->
                              IF k \in outgoing THEN SubSeq(chan[k], 1, keep[k])
                              ELSE IF k \in open THEN SubSeq(chan[k], lost[k] + 1, Len(chan[k]))
                              ELSE IF k \in incoming THEN SubSeq(chan[k], dlv[k] + 1, Len(chan[k]))
                              ELSE chan[k]]
          /\ dlv' = [k \in ChanKeys |-> IF k \in incoming THEN 0 ELSE dlv[k]]
          /\ pdown' = [o \in Nodes |->
                          IF o = n THEN {}
                          ELSE IF up[o] /\ known[o][n] = old THEN pdown[o] \cup {old}
                          ELSE pdown[o]]
    /\ up' = [up EXCEPT ![n] = FALSE]
    /\ pexit' = [pexit EXCEPT ![n] = {}]
    /\ pnodeup' = [pnodeup EXCEPT ![n] = {}]
    /\ pcall' = [pcall EXCEPT ![n] = {}]
    /\ counts' = [counts EXCEPT !.restart = @ + 1]
    /\ UNCHANGED <<alive, own, remote, known, asked, inc, conn, nextPid, resMsgs, held, removed>>

\* a new scope process starts on n: it keeps the claims of n's processes that are still alive, forgets the other
\* nodes, and asks the connected ones for their data
Start(n) ==
    /\ ~up[n]
    /\ LET new == inc[n] + 1
           peers == {m \in Nodes \ {n}: Connected(n, m)}
       IN /\ inc' = [inc EXCEPT ![n] = new]
          /\ chan' = [k \in ChanKeys |->
                         IF k[1] = n /\ k[2] = new /\ k[3] \in peers THEN <<[type |-> "discover", from |-> <<n, new>>]>>
                         ELSE chan[k]]
          /\ asked' = [asked EXCEPT ![n] = peers]
    /\ up' = [up EXCEPT ![n] = TRUE]
    /\ own' = [own EXCEPT ![n] = [nm \in Names |-> IF @[nm] # NONE /\ @[nm].pid \in alive THEN @[nm] ELSE NONE]]
    /\ remote' = [remote EXCEPT ![n] = [m \in Nodes |-> NoClaims]]
    /\ known' = [known EXCEPT ![n] = [m \in Nodes |-> NONE]]
    /\ UNCHANGED <<alive, conn, dlv, pdown, pexit, pnodeup, pcall, nextPid, counts, resMsgs, held, removed>>

-----------------------------------------------------------------------------

Init ==
    /\ alive = {}
    /\ own = [n \in Nodes |-> NoClaims]
    /\ remote = [n \in Nodes |-> [m \in Nodes |-> NoClaims]]
    /\ known = [n \in Nodes |-> [m \in Nodes |-> IF m = n THEN NONE ELSE <<m, 1>>]]
    /\ asked = [n \in Nodes |-> {}]
    /\ inc = [n \in Nodes |-> 1]
    /\ conn = {{n, m}: n \in Nodes, m \in Nodes} \ {{n}: n \in Nodes}
    /\ chan = [k \in ChanKeys |-> <<>>]
    /\ dlv = [k \in ChanKeys |-> 0]
    /\ pdown = [n \in Nodes |-> {}]
    /\ pexit = [n \in Nodes |-> {}]
    /\ pnodeup = [n \in Nodes |-> {}]
    /\ pcall = [n \in Nodes |-> {}]
    /\ up = [n \in Nodes |-> TRUE]
    /\ nextPid = 1
    /\ counts = [reg |-> 0, call |-> 0, upd |-> 0, unreg |-> 0, exit |-> 0, disc |-> 0, restart |-> 0, created |-> 0]
    /\ resMsgs = 0
    /\ held = {}
    /\ removed = {}

Internal ==
    \/ \E k \in ChanKeys: Receive(k) \/ Lose(k)
    \/ \E n \in Nodes:
        \/ \E s \in pdown[n]: ReceiveDown(n, s)
        \/ \E p \in pexit[n]: ReceiveExit(n, p)
        \/ \E m \in pnodeup[n]: ReceiveNodeup(n, m)
        \/ \E c \in pcall[n]: ReceiveCall(n, c)

External ==
    \/ \E n \in Nodes: Register(n) \/ Update(n) \/ Unregister(n) \/ Crash(n) \/ Start(n)
    \/ \E x, y \in Nodes: RegisterCall(x, y) \/ UpdateCall(x, y) \/ Disconnect(x, y) \/ Reconnect(x, y)
    \/ \E p \in alive: Exit(p)

Next == Internal \/ External

Fairness ==
    /\ \A k \in ChanKeys: WF_vars(Receive(k)) /\ WF_vars(Lose(k))
    /\ \A n \in Nodes:
        /\ WF_vars(\E s \in pdown[n]: ReceiveDown(n, s))
        /\ WF_vars(\E p \in pexit[n]: ReceiveExit(n, p))
        /\ WF_vars(\E m \in pnodeup[n]: ReceiveNodeup(n, m))
        /\ WF_vars(\E c \in pcall[n]: ReceiveCall(n, c))

Spec == Init /\ [][Next]_vars /\ Fairness

-----------------------------------------------------------------------------
(* Properties *)

\* nothing left to deliver or handle
Quiet ==
    /\ \A k \in ChanKeys: chan[k] = <<>>
    /\ \A n \in Nodes: pdown[n] = {} /\ pexit[n] = {} /\ pnodeup[n] = {} /\ pcall[n] = {}

AllConnected == \A n, m \in Nodes: n # m => Connected(n, m)
AllUp == \A n \in Nodes: up[n]

\* the bookkeeping of what reached a mailbox stays within the channel
DeliveredInChannel == \A k \in ChanKeys: dlv[k] <= Len(chan[k])

\* once things settle, each running scope process knows the current scope process of every node it's connected to
\* that runs one, and has an exact copy of that node's claims; it has nothing from the other nodes
Membership ==
    Quiet => \A n, m \in Nodes:
        n # m /\ up[n] =>
            IF Connected(n, m) /\ up[m]
            THEN known[n][m] = Me(m) /\ remote[n][m] = own[m]
            ELSE known[n][m] = NONE /\ remote[n][m] = NoClaims

\* once things settle with every node connected and running: all nodes show the same claim for each name, the claim
\* shown is still held by its node, and a name that some node holds is shown everywhere
Agreement ==
    Quiet /\ AllConnected /\ AllUp =>
        \A nm \in Names:
            /\ \A n, m \in Nodes: Shown(n, nm) = Shown(m, nm)
            /\ \A n \in Nodes: Shown(n, nm) # NONE => own[Shown(n, nm).pid[1]][nm] = Shown(n, nm)
            /\ (\E m \in Nodes: own[m][nm] # NONE) => \A n \in Nodes: Shown(n, nm) # NONE

\* once things settle with every node connected and running, at most one node holds each name
OneOwner ==
    Quiet /\ AllConnected /\ AllUp => \A nm \in Names: Cardinality({m \in Nodes: own[m][nm] # NONE}) <= 1

\* conflicts only ever make a node drop its claim, and each claim is dropped at most once: no endless back and forth
ResolutionBounded == resMsgs <= counts.created

\* with a resolver that compares things that don't change during the conflict, a name that got registered, and
\* whose processes were never unregistered and never exited, is still held by someone once things settle
SurvivorResolver ==
    \/ Resolver = "oldest"
    \/ Resolver = "newest" /\ (MonotonicClocks \/ Cardinality(Times) = 1)
Survivor ==
    SurvivorResolver /\ Quiet => \A nm \in held \ removed: \E m \in Nodes: own[m][nm] # NONE

\* message traffic always stops, and stays stopped, once outside actions stop
Termination == <>[]Quiet

=============================================================================
