-module(syn).

%% API
-export([start/0, stop/0]).
-export([register/2]).
-export([find_by_key/1, find_by_pid/1]).


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

-spec register(Key :: any(), Pid :: pid()) -> ok | {error, key_taken}.
register(Key, Pid) ->
    syn_backbone:register(Key, Pid).

-spec find_by_key(Key :: any()) -> pid() | undefined.
find_by_key(Key) ->
    syn_backbone:find_by_key(Key).

-spec find_by_pid(Pid :: pid()) -> Key :: any() | undefined.
find_by_pid(Pid) ->
    syn_backbone:find_by_pid(Pid).
