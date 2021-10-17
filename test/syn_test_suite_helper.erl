%% ==========================================================================================================
%% Syn - A global Process Registry and Process Group manager.
%%
%% The MIT License (MIT)
%%
%% Copyright (c) 2015-2021 Roberto Ostinelli <roberto@ostinelli.net> and Neato Robotics, Inc.
%%
%% Permission is hereby granted, free of charge, to any person obtaining a copy
%% of this software and associated documentation files (the "Software"), to deal
%% in the Software without restriction, including without limitation the rights
%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the Software is
%% furnished to do so, subject to the following conditions:
%%
%% The above copyright notice and this permission notice shall be included in
%% all copies or substantial portions of the Software.
%%
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
%% THE SOFTWARE.
%% ==========================================================================================================
-module(syn_test_suite_helper).

%% API
-export([start_slave/1, stop_slave/1]).
-export([connect_node/1, disconnect_node/1]).
-export([clean_after_test/0]).
-export([start_process/0, start_process/1, start_process/2]).
-export([kill_process/1]).
-export([wait_cluster_mesh_connected/1]).
-export([wait_process_name_ready/1, wait_process_name_ready/2]).
-export([wait_message_queue_empty/0]).
-export([assert_cluster/2]).
-export([assert_registry_scope_subcluster/3, assert_groups_scope_subcluster/3]).
-export([assert_received_messages/1]).
-export([assert_empty_queue/1]).
-export([assert_same_array_with_same_members/2]).
-export([assert_wait/2]).
-export([send_error_logger_to_disk/0]).

%% internal
-export([process_main/0]).

%% macro
-define(TIMEOUT, 5000).

%% ===================================================================
%% API
%% ===================================================================
start_slave(NodeShortName) ->
    {ok, Node} = ct_slave:start(NodeShortName, [
        {boot_timeout, 10},
        {erl_flags, "-connect_all false -kernel dist_auto_connect never"}
    ]),
    CodePath = code:get_path(),
    true = rpc:call(Node, code, set_path, [CodePath]),
    {ok, Node}.

stop_slave(NodeShortName) ->
    {ok, _} = ct_slave:stop(NodeShortName).

connect_node(Node) ->
    net_kernel:connect_node(Node).

disconnect_node(Node) ->
    erlang:disconnect_node(Node).

clean_after_test() ->
    Nodes = [node() | nodes()],
    %% shutdown
    lists:foreach(fun(Node) ->
        %% close syn
        rpc:call(Node, application, stop, [syn]),
        %% clean env
        rpc:call(Node, application, unset_env, [syn, event_handler])
    end, Nodes).

start_process() ->
    Pid = spawn(fun process_main/0),
    Pid.
start_process(Node) when is_atom(Node) ->
    Pid = spawn(Node, fun process_main/0),
    Pid;
start_process(Loop) when is_function(Loop) ->
    Pid = spawn(Loop),
    Pid.
start_process(Node, Loop) ->
    Pid = spawn(Node, Loop),
    Pid.

kill_process(RegisteredName) when is_atom(RegisteredName) ->
    case whereis(RegisteredName) of
        undefined -> ok;
        Pid -> kill_process(Pid)
    end;
kill_process(Pid) when is_pid(Pid) ->
    case rpc:call(node(Pid), erlang, is_process_alive, [Pid]) of
        true ->
            MRef = monitor(process, Pid),
            exit(Pid, kill),
            receive
                {'DOWN', MRef, process, Pid, _Reason} -> ok
            after ?TIMEOUT ->
                ct:fail("~n\tCould not kill process ~p~n", [Pid])
            end;

        false ->
            ok
    end.

wait_cluster_mesh_connected(Nodes) ->
    wait_cluster_mesh_connected(Nodes, os:system_time(millisecond)).
wait_cluster_mesh_connected(Nodes, StartAt) ->
    AllSynced = lists:all(fun(Node) ->
        RemoteNodes = rpc:call(Node, erlang, nodes, []),
        AllNodes = [Node | RemoteNodes],
        lists:sort(AllNodes) == lists:sort(Nodes)
    end, Nodes),

    case AllSynced of
        true ->
            ok;

        false ->
            case os:system_time(millisecond) - StartAt > ?TIMEOUT of
                true ->
                    {error, {could_not_init_cluster, Nodes}};

                false ->
                    timer:sleep(50),
                    wait_cluster_mesh_connected(Nodes, StartAt)
            end
    end.

wait_process_name_ready(Name) ->
    wait_process_name_ready(Name, os:system_time(millisecond)).
wait_process_name_ready(Name, StartAt) ->
    timer:sleep(50),
    case whereis(Name) of
        undefined ->
            case os:system_time(millisecond) - StartAt > ?TIMEOUT of
                true ->
                    ct:fail("~n\tProcess with name ~p didn't come alive~n", [Name]);

                false ->

                    wait_process_name_ready(Name, StartAt)
            end;

        Pid ->
            case process_info(Pid, status) of
                {status, waiting} ->
                    ok;

                Other ->
                    case os:system_time(millisecond) - StartAt > ?TIMEOUT of
                        true ->
                            ct:fail("~n\tProcess with name ~p didn't come ready~n\tStatus: ~p~n", [Name, Other]);

                        false ->
                            wait_process_name_ready(Name, StartAt)
                    end
            end
    end.

wait_message_queue_empty() ->
    timer:sleep(500),
    syn_test_suite_helper:assert_wait(
        ok,
        fun() ->
            flush_inbox(),
            syn_test_suite_helper:assert_empty_queue(self())
        end
    ).

assert_cluster(Node, ExpectedNodes) ->
    assert_cluster(Node, ExpectedNodes, os:system_time(millisecond)).
assert_cluster(Node, ExpectedNodes, StartAt) ->
    Nodes = rpc:call(Node, erlang, nodes, []),
    case do_assert_cluster(Nodes, ExpectedNodes, StartAt) of
        continue -> assert_cluster(Node, ExpectedNodes, StartAt);
        _ -> ok
    end.

assert_registry_scope_subcluster(Node, Scope, ExpectedNodes) ->
    do_assert_scope_subcluster(syn_registry, Node, Scope, ExpectedNodes).

assert_groups_scope_subcluster(Node, Scope, ExpectedNodes) ->
    do_assert_scope_subcluster(syn_pg, Node, Scope, ExpectedNodes).

assert_received_messages(Messages) ->
    assert_received_messages(Messages, []).
assert_received_messages([], UnexpectedMessages) ->
    do_assert_received_messages([], UnexpectedMessages);
assert_received_messages(Messages, UnexpectedMessages) ->
    receive
        Message ->
            case lists:member(Message, Messages) of
                true ->
                    Messages1 = lists:delete(Message, Messages),
                    assert_received_messages(Messages1, UnexpectedMessages);

                false ->
                    assert_received_messages(Messages, [Message | UnexpectedMessages])
            end
    after ?TIMEOUT ->
        do_assert_received_messages(Messages, UnexpectedMessages)
    end.

assert_empty_queue(Pid) when is_pid(Pid) ->
    case process_info(Pid, message_queue_len) of
        {message_queue_len, 0} ->
            ok;

        _ ->
            {messages, Messages} = process_info(Pid, messages),
            ct:fail("~n\tMessage queue was not empty, got:~n\t~p~n", [Messages])
    end.

assert_same_array_with_same_members(Arr1, Arr2) ->
    assert_same_array_with_same_members(Arr1, Arr2, []).
assert_same_array_with_same_members([], [], []) ->
    ok;
assert_same_array_with_same_members([], RemArr2, RemArr1) ->
    ct:fail("~n\tIn 1 only: ~p~n\tIn 2 only: ~p~n", [RemArr1, RemArr2]);
assert_same_array_with_same_members([E1 | Arr1], Arr2, RemArr1) ->
    case lists:member(E1, Arr2) of
        false ->
            assert_same_array_with_same_members(Arr1, Arr2, [E1 | RemArr1]);

        true ->
            NewArr2 = lists:delete(E1, Arr2),
            assert_same_array_with_same_members(Arr1, NewArr2, RemArr1)
    end.

assert_wait(ExpectedResult, Fun) ->
    assert_wait(ExpectedResult, Fun, os:system_time(millisecond)).
assert_wait(ExpectedResult, Fun, StartAt) ->
    case Fun() of
        ExpectedResult ->
            ok;

        Result ->
            case os:system_time(millisecond) - StartAt > ?TIMEOUT of
                true ->
                    ct:fail("~n\tExpected: ~p~n\tActual: ~p~n", [ExpectedResult, Result]);

                false ->
                    timer:sleep(50),
                    assert_wait(ExpectedResult, Fun, StartAt)
            end
    end.

send_error_logger_to_disk() ->
    error_logger:logfile({open, atom_to_list(node())}).

%% ===================================================================
%% Internal
%% ===================================================================
process_main() ->
    receive
        _ -> process_main()
    end.

do_assert_scope_subcluster(Module, Node, Scope, ExpectedNodes) ->
    do_assert_scope_subcluster(Module, Node, Scope, ExpectedNodes, os:system_time(millisecond)).
do_assert_scope_subcluster(Module, Node, Scope, ExpectedNodes, StartAt) ->
    Nodes = rpc:call(Node, Module, get_subcluster_nodes, [Scope]),
    case do_assert_cluster(Nodes, ExpectedNodes, StartAt) of
        continue -> do_assert_scope_subcluster(Module, Node, Scope, ExpectedNodes, StartAt);
        _ -> ok
    end.

do_assert_cluster(Nodes, ExpectedNodes, StartAt) ->
    ExpectedCount = length(ExpectedNodes),
    %% count nodes
    case length(Nodes) of
        ExpectedCount ->
            %% loop nodes
            RemainingNodes = lists:filter(fun(N) -> not lists:member(N, ExpectedNodes) end, Nodes),
            case length(RemainingNodes) of
                0 ->
                    ok;

                _ ->
                    case os:system_time(millisecond) - StartAt > ?TIMEOUT of
                        true ->
                            ct:fail("~n\tInvalid subcluster~n\tExpected: ~p~n\tActual: ~p~n\tLine: ~p~n",
                                [ExpectedNodes, Nodes, get_line_from_stacktrace()]
                            );

                        false ->
                            timer:sleep(50),
                            continue
                    end
            end;

        _ ->
            case os:system_time(millisecond) - StartAt > ?TIMEOUT of
                true ->
                    ct:fail("~n\tInvalid subcluster~n\tExpected: ~p~n\tActual: ~p~n\tLine: ~p~n",
                        [ExpectedNodes, Nodes, get_line_from_stacktrace()]
                    );

                false ->
                    timer:sleep(50),
                    continue
            end
    end.

do_assert_received_messages([], []) ->
    ok;
do_assert_received_messages(MissingMessages, UnexpectedMessages) ->
    ct:fail("~n\tReceive messages error~n\tMissing: ~p~n\tUnexpected: ~p~n",
        [lists:reverse(MissingMessages), lists:reverse(UnexpectedMessages)]
    ).

flush_inbox() ->
    receive
        _ -> flush_inbox()
    after 0 ->
        ok
    end.

get_line_from_stacktrace() ->
    {current_stacktrace, Stacktrace} = process_info(self(), current_stacktrace),
    [{_, _, _, FileInfo} | _] = lists:dropwhile(fun({Module, _Method, _Arity, _FileInfo}) ->
        Module =:= ?MODULE end, Stacktrace),
    proplists:get_value(line, FileInfo).
