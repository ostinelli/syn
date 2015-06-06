-module(syn).

%% API
-export([start/0, stop/0]).


%% ===================================================================
%% API
%% ===================================================================
-spec start() -> ok.
start() ->
    {ok, _} = application:ensure_all_started(mnesia),
    {ok, _} = application:ensure_all_started(syn),
    ok.

-spec stop() -> ok.
stop() ->
    ok = application:stop(syn).
