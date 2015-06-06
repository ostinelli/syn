-module(syn_test_suite_helper).

%% API
-export([start_slave/1, stop_slave/1]).


%% ===================================================================
%% API
%% ===================================================================
start_slave(NodeShortName) ->
    EbinFilePath = filename:join([filename:dirname(code:lib_dir(syn, ebin)), "ebin"]),
    %% start slave
    {ok, NodeName} = ct_slave:start(NodeShortName, [
        {boot_timeout, 10},
        {monitor_master, true},
        {erl_flags, string:concat("-pa ", EbinFilePath)}
    ]),
    {ok, NodeName}.

stop_slave(NodeName) ->
    ct_slave:stop(NodeName).
