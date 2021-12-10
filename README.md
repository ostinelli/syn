![CI](https://github.com/ostinelli/syn/actions/workflows/ci.yml/badge.svg) [![Hex pm](https://img.shields.io/hexpm/v/syn.svg)](https://hex.pm/packages/syn)

# Syn
**Syn** (short for _synonym_) is a scalable global Process Registry and Process Group manager for Erlang and Elixir,
able to automatically manage dynamic clusters (addition / removal of nodes) and to recover from net splits.

Syn is a replacement for Erlang/OTP
[global](https://www.erlang.org/doc/man/global.html)'s registry and
[pg](https://www.erlang.org/doc/man/pg.html) modules. The main differences with these OTP's implementations are:

* OTP's `global` module chooses Consistency over Availability, therefore it can become difficult to scale
  when registration rates are elevated and the cluster becomes larger. If eventual consistency is acceptable in your
  case, Syn can considerably increase the registry's performance.
* Syn allows to attach metadata to every process, which also gets synchronized across the cluster.
* Syn implements [cluster-wide callbacks](syn_event_handler.html) on the main events, which are also properly triggered
  after net splits.

[[Documentation](https://hexdocs.pm/syn/)]

## Introduction

### What is a Process Registry?
A global Process Registry allows registering a process on all the nodes of a cluster with a single Key.
Consider this the process equivalent of a DNS server: in the same way you can retrieve an IP address from a domain name,
you can retrieve a process from its Key.

Typical Use Case: registering on a system a process that handles a physical device (using its serial number).

### What is a Process Group?
A global Process Group is a named group which contains many processes, possibly running on different nodes.
With the group Name, you can retrieve on any cluster node the list of these processes, or publish a message to all of them.
This mechanism allows for Publish / Subscribe patterns.

Typical Use Case: a chatroom.

### What is Syn?
Syn is a Process Registry and Process Group manager that has the following features:

* Global Process Registry (i.e. a process is uniquely identified with a Key across all the nodes of a cluster).
* Global Process Group manager (i.e. a group is uniquely identified with a Name across all the nodes of a cluster).
* Any term can be used as Key and Name.
* PubSub mechanism: messages can be published to all members of a Process Group (_globally_ on all the cluster or _locally_ on a single node). 
* Subclusters by using Scopes allows great scalability.
* Dynamically sized clusters (addition / removal of nodes is handled automatically).
* Net Splits automatic resolution.
* Fast writes.
* Configurable callbacks.
* Processes are automatically monitored and removed from the Process Registry and Process Groups if they die.

## Notes
In any distributed system you are faced with a consistency challenge, which is often resolved by having one master arbiter
performing all write operations (chosen with a mechanism of [leader election](http://en.wikipedia.org/wiki/Leader_election)),
or through [atomic transactions](http://en.wikipedia.org/wiki/Atomicity_(database_systems)).

Syn was born for applications of the [IoT](http://en.wikipedia.org/wiki/Internet_of_Things) field. In this context,
Keys used to identify a process are often the physical object's unique identifier (for instance, its serial or MAC address),
and are therefore already defined and unique _before_ hitting the system. The consistency challenge is less of a problem in this case,
since the likelihood of concurrent incoming requests that would register processes with the same Key is extremely low and, in most cases, acceptable.

In addition, write speeds were a determining factor in the architecture of Syn.

Therefore, Availability has been chosen over Consistency and Syn implements
[strong eventual consistency](http://en.wikipedia.org/wiki/Eventual_consistency).

## Installation

### For Elixir
Add it to your deps:

```elixir
defp deps do
  [{:syn, "~> 3.0"}]
end
```

### For Erlang
If you're using [rebar3](https://github.com/erlang/rebar3), add `syn` as a dependency in your project's `rebar.config` file:

```erlang
{deps, [
  {syn, {git, "git://github.com/ostinelli/syn.git", {tag, "3.0.1"}}}
]}.
```
Or, if you're using [Hex.pm](https://hex.pm/) as package manager (with the [rebar3_hex](https://github.com/hexpm/rebar3_hex) plugin):

```erlang
{deps, [
  {syn, "3.0.1"}
]}.
```

Ensure that `syn` is started with your application, for example by adding it in your `.app` file to the list of `applications`:

```erlang
{application, my_app, [
    %% ...
    {applications, [
        kernel,
        stdlib,
        sasl,
        syn,
        %% ...
    ]},
    %% ...
]}.
```

## Contributing
So you want to contribute? That's great! Please follow the guidelines below. It will make it easier to get merged in.

Before implementing a new feature, please submit a ticket to discuss what you intend to do. Your feature might already be in the works, or an alternative implementation might have already been discussed.

Do not commit to master in your fork. Provide a clean branch without merge commits. Every pull request should have its own topic branch. In this way, every additional adjustments to the original pull request might be done easily, and squashed with `git rebase -i`. The updated branch will be visible in the same pull request, so there will be no need to open new pull requests when there are changes to be applied.

Ensure that proper testing is included. To run Syn tests you simply have to be in the project's root directory and run:

```bash
$ make test
```

## License

Copyright (c) 2015-2021 Roberto Ostinelli and Neato Robotics, Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
