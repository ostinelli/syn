PROJECT_DIR:=$(strip $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST)))))

all:
	@rebar compile

clean:
	@rebar clean
	@find $(PROJECT_DIR)/. -name "erl_crash\.dump" | xargs rm -f

deps: clean
	@rebar delete-deps
	@rebar get-deps

dialyze:
	@dialyzer -n -c src/*.erl

run:
	@erl -pa ebin \
	-name syn@127.0.0.1 \
	+K true \
	+P 5000000 \
	+Q 1000000 \
	-mnesia schema_location ram \
	-eval 'syn:start().'

tests: all
	ct_run -dir $(PROJECT_DIR)/test -logdir $(PROJECT_DIR)/test/results \
	-pa $(PROJECT_DIR)/ebin

travis: tests
