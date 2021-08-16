-module(syn_benchmark_v2).

-export([start/1]).
-export([process_loop/0]).
-export([collection_loop/2]).
-export([run_test_on_node/3]).
-export([register_pids/1]).
-export([join_pids/1, chunks/2]).
-export([unregister_pids/1]).
-export([wait_for_unregistered/1]).

%% macros
-define(MAX_RETRIEVE_WAITING_TIME, 60000).


start(ShardsNum) ->
  io:format("-----> Starting benchmark on node ~s~n", [node()]),
  %% init
  ConfigFilePath = filename:join([filename:dirname(code:which(?MODULE)), "syn_benchmark.config"]),
  {ok, BenchConfig} = file:consult(ConfigFilePath),
  RemoteHosts = proplists:get_value(remote_nodes, BenchConfig, []),
  ProcessCount = list_to_integer(os:getenv("SYN_PROCESS_COUNT", "100000")),
  %% start nodes
  lists:foreach(fun(RemoteHost) ->
    io:format("-----> Starting slave node ~s@~s~n", [maps:get(node, RemoteHost), maps:get(host, RemoteHost)]),
    {ok, _} = syn_test_suite_helper:start_slave(
      maps:get(node, RemoteHost),
      maps:get(host, RemoteHost),
      maps:get(user, RemoteHost),
      maps:get(pass, RemoteHost)
    )
  end, RemoteHosts),

  Nodes = [node() | nodes()],
  io:format("-----> Started ~p nodes: ~p~n", [length(Nodes), Nodes]),

  %% start syn everywhere
  case ShardsNum > 0 of
    true ->
      lists:foreach(fun(Node) ->
        ok = rpc:call(Node, syn_test_suite_helper, start_syn, [ShardsNum])
      end, Nodes);
    false ->
      syn:start()  %% start(0) to test with non-modified version of syn library
  end,

  timer:sleep(1000),

  %% compute names per node
  ProcessesPerNode = round(ProcessCount / length(Nodes)),
  io:format("-----> ~p processes per node~n", [ProcessesPerNode]),

  %% launch test everywhere
  CollectingPid = self(),
  lists:foldl(fun(Node, Acc) ->
    FromName = Acc * ProcessesPerNode + 1,
    ToName = FromName + ProcessesPerNode - 1,
    rpc:cast(Node, ?MODULE, run_test_on_node, [CollectingPid, FromName, ToName]),
    Acc + 1
  end, 0, Nodes),

  Results = collection_loop(Nodes, []),
  io:format("-----> Results: ~p~n", [Results]),

  %% stop syn everywhere
  lists:foreach(fun(Node) ->
    ok = rpc:call(Node, syn, stop, [])
                end, [node() | nodes()]),
  timer:sleep(1000),

  %% stop nodes
  lists:foreach(fun(SlaveNode) ->
    syn_test_suite_helper:connect_node(SlaveNode),
    ShortName = list_to_atom(lists:nth(1, string:split(atom_to_list(SlaveNode), "@"))),
    syn_test_suite_helper:stop_slave(ShortName)
                end, nodes()),
  io:format("-----> Stopped ~p nodes: ~p~n", [length(Nodes), Nodes]),

  %% stop node
  init:stop().

run_in_worker(FunName, WorkersNum, ChunkedPidTuples) ->
  {_, Sec0, Msec0} = os:timestamp(),
  io:format("Starting ~p at ~p.~p ~n", [FunName, Sec0, Msec0]),
  ExecTimes = syn_pmap:pmap(fun(PidTups) ->
    {ExecTime, ok} = timer:tc(?MODULE, FunName, [PidTups]),
    ExecTime
  end, ChunkedPidTuples, WorkersNum),
  MaxExecTime = lists:max(ExecTimes),
  {_, Sec1, Msec1} = os:timestamp(),
  io:format("End ~p at ~p.~p ~n~n", [FunName, Sec1, Msec1]),
  MaxExecTime.

run_test_on_node(CollectingPid, FromId, ToId) ->
  %% launch processes - list is in format {Name, pid()}
  PidTuples = [{Id, spawn(?MODULE, process_loop, [])} || Id <- lists:seq(FromId, ToId)],
  WorkersNum = 24,
  ChunkLen = round(length(PidTuples) / WorkersNum),
  ChunkedPidTuples = chunks(PidTuples, ChunkLen),
  {ToId, ToPid} = lists:last(PidTuples),
  ProcId = integer_to_binary(ToId),
  ToName = <<"proc-", ProcId/binary>>,

  RegisteringTime1 = run_in_worker(register_pids, WorkersNum, ChunkedPidTuples),
  ToPid = syn:whereis(ToName),
  io:format("Registered: ~p~n", [syn_registry:count()]),

  GroupJoinTime = run_in_worker(join_pids, WorkersNum, ChunkedPidTuples),

  UnregisteringTime = run_in_worker(unregister_pids, WorkersNum, ChunkedPidTuples),
  io:format("Registered: ~p~n", [syn_registry:count()]),
  undefined = syn:whereis(ToName),

  RegisteringTime2 = run_in_worker(register_pids, WorkersNum, ChunkedPidTuples),
  io:format("Registered: ~p~n", [syn_registry:count()]),
  ToPid = syn:whereis(ToName),

  %% kill all
  lists:foreach(fun({_Name, Pid}) ->
    exit(Pid, kill)
  end, PidTuples),

  %% check all unregistered
  timer:tc(?MODULE, wait_for_unregistered, [ToName]),

  %% return
  CollectingPid ! {node(), [
    {registering_time_1, RegisteringTime1},
    {join_time_1, GroupJoinTime},
    {unregistering_time_1, UnregisteringTime},
    {registering_time_2, RegisteringTime2}
  ]}.

%% ===================================================================
%% Internal
%% ===================================================================
collection_loop([], Results) -> Results;
collection_loop(Nodes, Results) ->
  receive
    {Node, Result} ->
      collection_loop(lists:delete(Node, Nodes), [{Node, Result} | Results])
  after ?MAX_RETRIEVE_WAITING_TIME ->
    io:format("COULD NOT COMPLETE TEST IN ~p seconds", [?MAX_RETRIEVE_WAITING_TIME])
  end.

process_loop() ->
  receive
    _ -> ok
  end.

register_pids([]) -> ok;
register_pids([{Id, Pid} | TPidTuples]) ->
  ProcId = integer_to_binary(Id),
  ProcName = <<"proc-", ProcId/binary>>,
  ok = syn:register(ProcName, Pid),
  register_pids(TPidTuples).

join_pids([]) -> ok;
join_pids([{_Id, Pid} | TPidTuples]) ->
  GroupId = integer_to_binary(rand:uniform(999)),
  GroupName = <<"group-", GroupId/binary>>,
  ok = syn:join(GroupName, Pid),
  join_pids(TPidTuples).

wait_for_unregistered(ProcName) ->
  case syn:whereis(ProcName) of
    undefined ->
      ok;
    _ ->
      timer:sleep(50),
      wait_for_unregistered(ProcName)
  end.

unregister_pids([]) -> ok;
unregister_pids([{Name, _Pid} | TPidTuples]) ->
  ProcId = integer_to_binary(Name),
  ProcName = <<"proc-", ProcId/binary>>,
  ok = syn:unregister(ProcName),
  unregister_pids(TPidTuples).

chunks([], _) -> [];
chunks(List, Len) when Len > length(List) ->
  [List];
chunks(List, Len) ->
  {H, T} = lists:split(Len, List),
  [H | chunks(T, Len)].