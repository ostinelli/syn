PROJECT_DIR:=$(strip $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST)))))

all:
	@$(PROJECT_DIR)/rebar3 compile

clean:
	@$(PROJECT_DIR)/rebar3 clean
	@find $(PROJECT_DIR)/. -name "erl_crash\.dump" | xargs rm -f

dialyze:
	@$(PROJECT_DIR)/rebar3 dialyzer

run:
	@erl -pa `$(PROJECT_DIR)/rebar3 path` \
	-name syn@127.0.0.1 \
	+K true \
	-mnesia schema_location ram \
	-eval 'syn:start(),syn:init().'

tests: all
	ct_run -dir $(PROJECT_DIR)/test -logdir $(PROJECT_DIR)/test/results \
	-pa `$(PROJECT_DIR)/rebar3 path`

travis: all tests
