-module(syn_pmap).
-export([pmap/2, pmap/3]).
-export([pmap_worker/3]).
-export([worker_init/3]).

-record(pmap, {
  worker_ref = erlang:make_ref() :: reference(),

  all_workers = [] :: [pid()],
  spare_workers = [] :: [pid()],

  task_idx = 0 :: non_neg_integer(),
  tasks = [] :: [term()],
  results = [] :: [{ok, term()} | {error | throw | exit, term()}],
  workers_alive = 0 :: non_neg_integer()
}).

-spec pmap_worker(fun((In) -> term()), In, reference()) -> no_return().
pmap_worker(F, I, ResultRef) ->
  receive go -> ok end,
  Result = F(I),
  exit({ResultRef, Result}).

-spec pmap(fun((In) -> Out), [In]) -> [Out].
pmap(F, L) when is_function(F, 1) andalso is_list(L) ->
  ResultRef = erlang:make_ref(),
  MonRefs = lists:map(
    fun(I) ->
      P = erlang:spawn(?MODULE, pmap_worker, [F, I, ResultRef]),
      MonRef = erlang:monitor(process, P),
      P ! go,
      MonRef
    end, L),
  Results = lists:map(
    fun(MonRef) ->
      receive
        {'DOWN', MonRef, process, _, {ResultRef, Result}} -> {ok, Result};
        {'DOWN', MonRef, process, _, Abnormal} -> {error, Abnormal}
      end
    end,
    MonRefs),
  lists:map(
    fun
      ({ok, V}) -> V;
      (ChildError) -> error({pmap_child_error, ChildError})
    end,
    Results).

pmap(F, L, WCount) when is_function(F, 1) andalso is_list(L) andalso is_integer(WCount) ->
  LLength = length(L),
  case LLength < WCount of
    true -> pmap(F, L, length(L));
    false ->
      WIdxs = lists:seq(1, WCount),
      Parent = self(),
      WRef = erlang:make_ref(),
      Workers = lists:map(
        fun(_) ->
          _Worker = erlang:spawn_link(?MODULE, worker_init, [Parent, F, WRef])
        end,
        WIdxs),
      Results = pmap_parent_loop(#pmap{
        worker_ref = WRef,
        task_idx = 0,
        all_workers = Workers,
        spare_workers = Workers,
        tasks = L,
        results = [],
        workers_alive = WCount
      }),
      [Result || {_, Result} <- lists:sort(Results)]
  end.

pmap_parent_loop(S = #pmap{
  tasks = [],
  all_workers = Workers
}) ->
  lists:foreach(fun(W) -> erlang:send(W, done) end, Workers),
  pmap_parent_finalize_loop(S);

pmap_parent_loop(S = #pmap{
  task_idx = TaskIdx,
  tasks = [T | Tasks],
  spare_workers = [Worker | Workers]
}) ->
  _ = erlang:send(Worker, {item, TaskIdx, T}),
  pmap_parent_loop(S#pmap{task_idx = TaskIdx + 1, tasks = Tasks, spare_workers = Workers});

pmap_parent_loop(S = #pmap{
  worker_ref = WRef,
  spare_workers = [],
  tasks = [T | Tasks],
  task_idx = TaskIdx,
  results = Results
}) ->
  receive
    {result, WRef, Worker, ResultIdx, Result} ->
      _ = erlang:send(Worker, {item, TaskIdx, T}),
      pmap_parent_loop(S#pmap{
        task_idx = TaskIdx + 1,
        tasks = Tasks,
        results = [{ResultIdx, Result} | Results]
      })
  end.

pmap_parent_finalize_loop(#pmap{
  workers_alive = 0,
  results = Results
}) -> Results;

pmap_parent_finalize_loop(S = #pmap{
  worker_ref = WRef,
  results = Results,
  workers_alive = WorkersAlive
}) when WorkersAlive > 0 ->
  receive
    {done, WRef, _Worker} -> pmap_parent_finalize_loop(S#pmap{workers_alive = WorkersAlive - 1});
    {result, WRef, _Worker, ResultIdx, Result} ->
      pmap_parent_finalize_loop(S#pmap{
        results = [{ResultIdx, Result} | Results]
      })
  end.

worker_init(Parent, F, WRef) ->
  false = erlang:process_flag(trap_exit, true),
  worker_loop(Parent, F, WRef).

worker_loop(Parent, F, WRef) ->
  receive
    {item, Idx, I} ->
      Result = try {ok, F(I)}
               catch Error:Reason -> {Error, Reason} end,
      _ = erlang:send(Parent, {result, WRef, self(), Idx, Result}),
      worker_loop(Parent, F, WRef);
    done ->
      _ = erlang:send(Parent, {done, WRef, self()}),
      exit(normal);
    {'EXIT', Parent, Reason} -> exit({parent_exited, Reason, Parent})
  end.
