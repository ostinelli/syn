all:
	@rebar compile

clean:
	@rebar clean
	@find $(PWD)/. -name "erl_crash\.dump" | xargs rm -f

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
	@mkdir -p /tmp/logs; \
	ct_run -sname syn -dir test -logdir /tmp/logs -pa ebin; \
	res=$$?; \
	rm -rf /tmp/logs; \
	if [ $$res != 0 ]; then exit $$res; fi;
