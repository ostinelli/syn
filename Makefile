PROJECT_DIR:=$(strip $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST)))))

all:
	@./rebar compile

clean:
	@./rebar clean
	@find $(PROJECT_DIR)/. -name "erl_crash\.dump" | xargs rm -f
	@find $(PROJECT_DIR)/. -name "*.beam" | xargs rm -f

dialyze:
	@dialyzer -n -c $(PROJECT_DIR)/src/*.erl

tests: all
	ct_run -dir $(PROJECT_DIR)/test -logdir $(PROJECT_DIR)/test/results \
	-pa $(PROJECT_DIR)/ebin $(PROJECT_DIR)/deps/*/ebin

travis: all tests
