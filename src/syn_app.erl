-module(syn_app).
-behaviour(application).

%% API
-export([start/2, stop/1]).


%% ===================================================================
%% API
%% ===================================================================
-spec start(
    StartType :: normal | {takeover, node()} | {failover, node()},
    StartArgs :: any()
) -> {ok, pid()} | {ok, pid(), State :: any()} | {error, any()}.
start(_StartType, _StartArgs) ->
    %% start sup
    syn_sup:start_link().

-spec stop(State :: any()) -> ok.
stop(_State) ->
    ok.
