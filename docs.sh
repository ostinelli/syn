#!/bin/bash
set -e

# Setup:
#
#     mix escript.install github elixir-lang/ex_doc
#     asdf install erlang 24.0.2
#     asdf local erlang 24.0.2

rebar3 compile
rebar3 as docs edoc
version=3.3.0
ex_doc "syn" $version "_build/default/lib/syn/ebin" \
  --source-ref ${version} \
  --config docs.config $@
