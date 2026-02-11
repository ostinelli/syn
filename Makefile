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
	@# make run node=syn2
	@erl -pa `rebar3 path` \
	-name $(node)@127.0.0.1 \
	-eval 'syn:start().'
else
	@erl -pa `rebar3 path` \
	-name syn@127.0.0.1 \
	-eval 'syn:start().'
endif

test: compile_test
ifdef suite
	@# 'make test suite=syn_registry_SUITE'
	ct_run -noinput -dir $(PROJECT_DIR)/test -logdir $(PROJECT_DIR)/test/results \
	-suite $(suite) \
	-pa `rebar3 as test path` \
	-erl_args -config $(PROJECT_DIR)/test/sys
else
	ct_run -noinput -dir $(PROJECT_DIR)/test -logdir $(PROJECT_DIR)/test/results \
	-pa `rebar3 as test path` \
	-erl_args -config $(PROJECT_DIR)/test/sys
endif

killzombies:
	@pkill -9 -f beam 2>/dev/null; true
	@sleep 1
	@epmd -daemon
	@echo "Zombie beam processes killed, epmd restarted."

bench: compile_test
	@erl -pa `rebar3 as test path` \
	-pa `rebar3 as test path`/../test \
	-name syn_bench_master@127.0.0.1 \
	-noshell \
	+P 5000000 \
	-eval 'syn_benchmark:start().'
