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
	@erl -pa `rebar3 path` \
	-name syn@127.0.0.1 \
	-eval 'syn:start().'

node: all
	@# 'make node sname=syn1'
	@erl -pa `rebar3 path` \
	-name $(sname)@127.0.0.1 \
	-eval 'syn:start().'

test: compile_test
ifdef suite
	@# 'make test suite=syn_registry_SUITE'
	ct_run -dir $(PROJECT_DIR)/test -logdir $(PROJECT_DIR)/test/results \
	-suite $(suite) \
	-pa `rebar3 as test path`
else
	ct_run -dir $(PROJECT_DIR)/test -logdir $(PROJECT_DIR)/test/results \
	-pa `rebar3 as test path`
endif

bench: compile_test
	@erl -pa `rebar3 as test path` \
	-pa `rebar3 as test path`/../test \
	-name syn_bench_master@127.0.0.1 \
	-noshell \
	+P 5000000 \
	-eval 'syn_benchmark:start().'

travis:
	@$(PROJECT_DIR)/rebar3 as test compile
	ct_run -dir $(PROJECT_DIR)/test -logdir $(PROJECT_DIR)/test/results \
	-pa `$(PROJECT_DIR)/rebar3 as test path`
