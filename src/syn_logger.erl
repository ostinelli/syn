-module(syn_logger).

-export([syn_gen_scope/1,
         terminate/1,
         callback_error/1]).

syn_gen_scope(#{msg := discover, from := From}) ->
    {"Received DISCOVER request from node ~s", [From]};
syn_gen_scope(#{msg := {ack_sync, Data}, from := From}) ->
    {"Received ACK SYNC (~w entries) from node ~s", [length(Data), From]};
syn_gen_scope(#{msg := {down, Reason}, from := From}) ->
    {"Scope Process is DOWN on node node ~s: ~p", [From, Reason]};
syn_gen_scope(#{msg := nodeup, from := From}) ->
    {"Node ~s has joined the cluster, sending discover message", [From]};
syn_gen_scope(#{msg := after_init}) ->
    {"Discover the cluster", []}.

terminate(#{msg := {terminate, Reason}}) ->
    {"Terminating with reason: ~p", [Reason]}.

callback_error(#{class := Class,
                    reason := Reason,
                    mfa := {_, Func, _},
                    stacktrace := Stacktrace}) ->
    {"Error ~p:~p in custom handler ~p: ~p", [Class, Reason, Func, Stacktrace]};
callback_error(#{class := Class,
                    reason := Reason,
                    fa := {Func, _},
                    stacktrace := Stacktrace}) ->
    {"Error ~p:~p in custom handler ~p: ~p", [Class, Reason, Func, Stacktrace]}.
