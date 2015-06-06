-module(syn_sup).
-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 10000, Type, [I]}).


%% ===================================================================
%% API
%% ===================================================================
-spec start_link() -> {ok, pid()} | {already_started, pid()} | shutdown.
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Callbacks
%% ===================================================================
-spec init([]) ->
    {ok, {{supervisor:strategy(), non_neg_integer(), non_neg_integer()}, [supervisor:child_spec()]}}.
init([]) ->
    Children = [
    ],
    {ok, {{one_for_one, 10, 10}, Children}}.
