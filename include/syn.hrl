%% records
-record(syn_processes_table, {
    key = undefined :: undefined | any(),
    pid = undefined :: undefined | pid() | atom(),
    node = undefined :: atom()
}).
