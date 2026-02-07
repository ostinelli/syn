PROJECT_DIR:=$(strip $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST)))))

all:
	@rebar3 compile

compile_test:
	@rebar3 as test compile

clean:
	@rebar3 clean
	@find $(PROJECT_DIR)/. -name "erl_crash\.dump" | xargs rm -f
	@find $(PROJECT_DIR)/. -name "*\.beam" | xargs rm -f
	@find $(PROJECT_DIR)/. -name "*\.so" | xargs rm -f

dialyzer:
	@rebar3 dialyzer

run: all
ifdef node
	@# 'make test node=syn2@127.0.0.1
	@erl -pa `rebar3 path` \
	-name $(sname)@127.0.0.1 \
	-eval 'syn:start().'
else
	@erl -pa `rebar3 path` \
	-name syn@127.0.0.1 \
	-eval 'syn:start().'
endif

test: compile_test
ifdef suite
	@# 'make test suite=syn_registry_SUITE'
	erl -noshell -sname ct_master \
	-pa `rebar3 as test path` \
	-eval 'Result = ct:run_test([{dir, "$(PROJECT_DIR)/test"}, {logdir, "$(PROJECT_DIR)/test/results"}, {suite, $(suite)}]), erlang:halt(case Result of {_,0,{0,0}} -> 0; error -> 1; _ -> 1 end).'
else
	erl -noshell -sname ct_master \
	-pa `rebar3 as test path` \
	-eval 'Result = ct:run_test([{dir, "$(PROJECT_DIR)/test"}, {logdir, "$(PROJECT_DIR)/test/results"}]), erlang:halt(case Result of {_,0,{0,0}} -> 0; error -> 1; _ -> 1 end).'
endif

bench: compile_test
	@erl -pa `rebar3 as test path` \
	-pa `rebar3 as test path`/../test \
	-name syn_bench_master@127.0.0.1 \
	-noshell \
	+P 5000000 \
	-eval 'syn_benchmark:start().'
