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
-export([init_cluster/1, end_cluster/2]).
-export([start_slave/1, stop_slave/1]).
-export([connect_node/1, disconnect_node/1]).
-export([clean_after_test/0]).
-export([start_process/0, start_process/1, start_process/2]).
-export([kill_process/1]).
-export([wait_cluster_mesh_connected/1]).
-export([wait_process_name_ready/1, wait_process_name_ready/2]).
-export([wait_message_queue_empty/0]).
-export([assert_cluster/2]).
-export([assert_registry_scope_subcluster/3, assert_pg_scope_subcluster/3]).
-export([assert_received_messages/1]).
-export([assert_empty_queue/0]).
-export([assert_wait/2]).
-export([send_error_logger_to_disk/0]).

%% internal
-export([process_main/0]).

%% macro
-define(DEFAULT_WAIT_TIMEOUT, 5000).
-define(UNEXPECTED_MESSAGES_WAIT_TIMEOUT, 1000).

%% ===================================================================
%% API
%% ===================================================================
init_cluster(NodesCount) ->
    SlavesCount = NodesCount - 1,
    {Nodes, NodesConfig} = lists:foldl(fun(I, {AccNodes, AccNodesConfig}) ->
        IBin = integer_to_binary(I),
        NodeShortName = list_to_atom(binary_to_list(<<"syn_slave_", IBin/binary>>)),
        {ok, SlaveNode} = start_slave(NodeShortName),
        %% connect
        lists:foreach(fun(N) ->
            rpc:call(SlaveNode, syn_test_suite_helper, connect_node, [N])
        end, AccNodes),
        %% config
        {
            [SlaveNode | AccNodes],
            [{NodeShortName, SlaveNode} | AccNodesConfig]
        }
    end, {[], []}, lists:seq(1, SlavesCount)),
    %% wait full cluster
    case syn_test_suite_helper:wait_cluster_mesh_connected([node()] ++ Nodes) of
        ok ->
            %% config
            NodesConfig;

        Other ->
            ct:pal("*********** Could not get full cluster of ~p nodes, skipping", [NodesCount]),
            {error_initializing_cluster, Other}
    end.

end_cluster(NodesCount, Config) ->
    SlavesCount = NodesCount - 1,
    %% clean
    clean_after_test(),
    %% shutdown
    lists:foreach(fun(I) ->
        IBin = integer_to_binary(I),
        NodeShortName = list_to_atom(binary_to_list(<<"syn_slave_", IBin/binary>>)),
        SlaveNode = proplists:get_value(NodeShortName, Config),
        connect_node(SlaveNode),
        stop_slave(NodeShortName)
    end, lists:seq(1, SlavesCount)),
    %% wait
    timer:sleep(1000).

start_slave(NodeShortName) ->
    %% start slave
    {ok, Node} = ct_slave:start(NodeShortName, [
        {boot_timeout, 10},
        {erl_flags, "-connect_all false -kernel dist_auto_connect never"}
    ]),
    %% add syn code path to slaves
    CodePath = lists:filter(fun(Path) ->
        nomatch =/= string:find(Path, "/syn/")
    end, code:get_path()),
    true = rpc:call(Node, code, set_path, [CodePath]),
    %% return
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
        rpc:call(Node, application, unset_env, [syn, event_handler]),
        rpc:call(Node, application, unset_env, [syn, strict_mode]),
        %% messages
        flush_inbox()
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
            after ?DEFAULT_WAIT_TIMEOUT ->
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
            case os:system_time(millisecond) - StartAt > ?DEFAULT_WAIT_TIMEOUT of
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
            case os:system_time(millisecond) - StartAt > ?DEFAULT_WAIT_TIMEOUT of
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
                    case os:system_time(millisecond) - StartAt > ?DEFAULT_WAIT_TIMEOUT of
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
    do_assert_scope_subcluster(registry, Node, Scope, ExpectedNodes).

assert_pg_scope_subcluster(Node, Scope, ExpectedNodes) ->
    do_assert_scope_subcluster(pg, Node, Scope, ExpectedNodes).

assert_received_messages(Messages) ->
    assert_received_messages(Messages, []).
assert_received_messages([], UnexpectedMessages) ->
    assert_received_messages_wait([], UnexpectedMessages);
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
    after ?DEFAULT_WAIT_TIMEOUT ->
        assert_received_messages_evaluate(Messages, UnexpectedMessages)
    end.

assert_received_messages_wait(MissingMessages, UnexpectedMessages) ->
    receive
        Message ->
            assert_received_messages_wait(MissingMessages, [Message | UnexpectedMessages])
    after ?UNEXPECTED_MESSAGES_WAIT_TIMEOUT ->
        assert_received_messages_evaluate(MissingMessages, UnexpectedMessages)
    end.

assert_received_messages_evaluate([], []) ->
    ok;
assert_received_messages_evaluate(MissingMessages, UnexpectedMessages) ->
    ct:fail("~n\tReceive messages error (line ~p)~n\tMissing: ~p~n\tUnexpected: ~p~n",
        [get_line_from_stacktrace(), lists:reverse(MissingMessages), lists:reverse(UnexpectedMessages)]
    ).

assert_empty_queue() ->
    assert_empty_queue([]).
assert_empty_queue(UnexpectedMessages) ->
    receive
        Message ->
            assert_empty_queue([Message | UnexpectedMessages])
    after ?UNEXPECTED_MESSAGES_WAIT_TIMEOUT ->
        case UnexpectedMessages of
            [] -> ok;
            _ -> ct:fail("~n\tMessage queue was not empty, got:~n\t~p~n", [UnexpectedMessages])
        end
    end.

assert_wait(ExpectedResult, Fun) ->
    assert_wait(ExpectedResult, Fun, os:system_time(millisecond)).
assert_wait(ExpectedResult, Fun, StartAt) ->
    case Fun() of
        ExpectedResult ->
            ok;

        Result ->
            case os:system_time(millisecond) - StartAt > ?DEFAULT_WAIT_TIMEOUT of
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
        {registry_update_meta, Scope, Name, NewMeta} ->
            ok = syn:register(Scope, Name, self(), NewMeta),
            process_main();

        {pg_update_meta, Scope, GroupName, NewMeta} ->
            ok = syn:join(Scope, GroupName, self(), NewMeta),
            process_main();

        _ ->
            process_main()
    end.

do_assert_scope_subcluster(Type, Node, Scope, ExpectedNodes) ->
    do_assert_scope_subcluster(Type, Node, Scope, ExpectedNodes, os:system_time(millisecond)).
do_assert_scope_subcluster(Type, Node, Scope, ExpectedNodes, StartAt) ->
    Nodes = rpc:call(Node, syn, subcluster_nodes, [Type, Scope]),
    case do_assert_cluster(Nodes, ExpectedNodes, StartAt) of
        continue -> do_assert_scope_subcluster(Type, Node, Scope, ExpectedNodes, StartAt);
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
                    case os:system_time(millisecond) - StartAt > ?DEFAULT_WAIT_TIMEOUT of
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
            case os:system_time(millisecond) - StartAt > ?DEFAULT_WAIT_TIMEOUT of
                true ->
                    ct:fail("~n\tInvalid subcluster~n\tExpected: ~p~n\tActual: ~p~n\tLine: ~p~n",
                        [ExpectedNodes, Nodes, get_line_from_stacktrace()]
                    );

                false ->
                    timer:sleep(50),
                    continue
            end
    end.

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
