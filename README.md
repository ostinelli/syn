[![Build Status](https://travis-ci.org/ostinelli/syn.svg?branch=master)](https://travis-ci.org/ostinelli/syn)
[![Hex pm](https://img.shields.io/hexpm/v/syn.svg)](https://hex.pm/packages/syn)


# Syn
**Syn** (short for _synonym_) is a global Process Registry and Process Group manager for Erlang.

## Introduction

##### What is a Process Registry?
A global Process Registry allows registering a process on all the nodes of a cluster with a single Key. Consider this the process equivalent of a DNS server: in the same way you can retrieve an IP address from a domain name, you can retrieve a process from its Key.

Typical Use Case: registering on a system a process that handles a physical device (using its serial number).

##### What is a Process Group?
A global Process Group is a named group which contains many processes, possibly running on different nodes. With the group Name, you can retrieve on any cluster node the list of these processes, or publish a message to all of them. This mechanism allows for Publish / Subscribe patterns.

Typical Use Case: a chatroom.

##### What is Syn?
Syn is a Process Registry and Process Group manager that has the following features:

 * Global Process Registry (i.e. a process is uniquely identified with a Key across all the nodes of a cluster).
 * Global Process Group manager (i.e. a group is uniquely identified with a Name across all the nodes of a cluster).
 * Any term can be used as Key and Name.
 * A message can be published to all members of a Process Group (PubSub mechanism).
 * Fast writes.
 * Automatically handles conflict resolution (such as net splits).
 * Configurable callbacks.
 * Processes are automatically monitored and removed from the Process Registry and Process Groups if they die.


## Notes
In any distributed system you are faced with a consistency challenge, which is often resolved by having one master arbiter performing all write operations (chosen with a mechanism of [leader election](http://en.wikipedia.org/wiki/Leader_election)), or through [atomic transactions](http://en.wikipedia.org/wiki/Atomicity_(database_systems)).

Syn was born for applications of the [IoT](http://en.wikipedia.org/wiki/Internet_of_Things) field. In this context, Keys used to identify a process are often the physical object's unique identifier (for instance, its serial or MAC address), and are therefore already defined and unique _before_ hitting the system.  The consistency challenge is less of a problem in this case, since the likelihood of concurrent incoming requests that would register processes with the same Key is extremely low and, in most cases, acceptable.

In addition, write speeds were a determining factor in the architecture of Syn.

Therefore, Availability has been chosen over Consistency and Syn is [eventually consistent](http://en.wikipedia.org/wiki/Eventual_consistency).

