PROJECT_DIR:=$(strip $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST)))))

.PHONY: all compile_test clean dialyzer run test proper killzombies bench

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

test:
ifdef suite
	@# 'make test suite=syn_registry_SUITE'
	rebar3 ct --sname ct --sys_config $(PROJECT_DIR)/test/sys.config --suite $(PROJECT_DIR)/test/$(suite)
else
	rebar3 ct --sname ct --sys_config $(PROJECT_DIR)/test/sys.config
endif

proper:
ifdef suite
	rebar3 ct --sname ct --sys_config $(PROJECT_DIR)/test/sys.config --dir $(PROJECT_DIR)/test/property \
	--suite $(PROJECT_DIR)/test/property/$(suite)
else
	rebar3 ct --sname ct --sys_config $(PROJECT_DIR)/test/sys.config --dir $(PROJECT_DIR)/test/property
endif

killzombies:
	@# only the nodes started by the tests, and the test runs themselves
	@pkill -9 -f "sname (syn_slave_|syn_protocol_|syn_hidden_|syn_prop_|syn_pg_prop_)" 2>/dev/null; true
	@pkill -9 -f "[r]ebar3 ct --sname ct" 2>/dev/null; true
	@sleep 1
	@epmd -daemon
	@echo "Test nodes killed, epmd running."

bench: compile_test
	@erl -pa `rebar3 as test path` \
	-pa `rebar3 as test path`/../test \
	-name syn_bench_master@127.0.0.1 \
	-noshell \
	+P 5000000 \
	-eval 'syn_benchmark:start().'
