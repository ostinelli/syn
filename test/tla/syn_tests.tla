---- MODULE syn_tests ----
EXTENDS syn

VARIABLE x

I == FALSE /\ x = 0
N == FALSE /\ x' = x

\* AllRegisteredForNode

ASSUME LET l == ("n1" :> <<>> @@ "n2" :> [a |-> 0, b |-> 2] @@ "n3" :> [c |-> 1])
       res == AllRegisteredForNode(l)
       IN res = {"a", "b", "c"}

\* AllRegisteredNames

ASSUME LET l == ("n1" :> ("n1" :> [a |-> 1] @@ "n2" :> <<>> @@ "n3" :> <<>>) @@ "n2" :> ("n1" :> [a |-> 1] @@ "n2" :> [b |-> 2] @@ "n3" :> <<>>) @@ "n3" :> ("n1" :> <<>> @@ "n2" :> <<>> @@ "n3" :> [c |-> 3]))
       res == AllRegisteredNames({"n2","n3"}, l, {})
       IN res = {"b", "c"}

\* Duplicates

ASSUME LET l == ("n1" :> <<>> @@ "n2" :> [a |-> 0] @@ "n3" :> [a |-> 1])
       res == Duplicates(DOMAIN l, l, {})
       IN res = {"a"}

\* MergeRegistries

ASSUME LET local == ("n1" :> [a |-> 1] @@ "n2" :> <<>> @@ "n3" :> <<>>)
           remote == [a |-> 0]
           local_node == "n1"
           remote_node == "n2"
       res == MergeRegistries(local, remote, remote_node)
       IN res = [n1 |-> [a |-> 1], n2 |-> << >>, n3 |-> <<>>]

ASSUME LET local == ("n1" :> [a |-> 1] @@ "n2" :> <<>> @@ "n3" :> <<>>)
           remote == [a |-> 2]
           local_node == "n1"
           remote_node == "n2"
       res == MergeRegistries(local, remote, remote_node)
       IN res = [n1 |-> << >>, n2 |-> [a |-> 2], n3 |-> <<>>]

ASSUME LET local == ("n1" :> <<>> @@ "n2" :> <<>> @@ "n3" :> [a |-> 1])
           remote == [a |-> 2]
           local_node == "n1"
           remote_node == "n2"
       res == MergeRegistries(local, remote, remote_node)
       IN res = [n1 |-> << >>, n2 |-> [a |-> 2], n3 |-> <<>>]

ASSUME LET local == ("n1" :> << >> @@ "n2" :> <<>> @@ "n3" :> ("a" :> 1))
           remote == ("a" :> 0)
           local_node == "n1"
           remote_node == "n2"
           res == MergeRegistries(local, remote, remote_node)
       IN res = [n1 |-> << >>, n2 |-> << >>, n3 |-> [a |-> 1]]

ASSUME LET local == ("n1" :> << >> @@ "n2" :> << >> @@ "n3" :> ("a" :> 0))
           remote == [b |-> 1]
           remote_node == "n3"
           res == MergeRegistries(local, remote, remote_node)
       IN res = [n1 |-> << >>, n2 |-> << >>, n3 |-> [a |-> 0, b |-> 1]]
====
