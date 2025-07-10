-module(syn_logger).

-export([syn_gen_scope/1,
         terminate/1,
         callback_error/1,
         unknown_message/1,
         scope/1]).

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

unknown_message(#{kind := down, pid := Pid, reason := Reason}) ->
    {"Received a DOWN message from and unknown process ~p with reason: ~p",
     [Pid, Reason]};
unknown_message(#{kind := call, from := From, msg := Msg}) ->
    {"Received from ~p an unknown call message: ~p", [From, Msg]};
unknown_message(#{kind := Kind, msg := Msg}) ->
    {"Received an unknown ~p message: ~p", [Kind, Msg]}.

scope(#{action := added, new := Scope}) ->
    {"Added node to scope <~s>", [Scope]}.
