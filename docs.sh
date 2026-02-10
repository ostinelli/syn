#!/bin/bash
set -e

# Setup:
#     mix escript.install github elixir-lang/ex_doc

rebar3 compile
rebar3 as docs edoc
version=3.4.0

# Resolve ex_doc escript path (installed via: mix escript.install hex ex_doc)
EX_DOC_PATH=$(mix escript 2>&1 | awk '/installed at:/{print $NF}')/ex_doc
if [ ! -x "$EX_DOC_PATH" ]; then
  echo "ex_doc not found. Install with: mix escript.install hex ex_doc"
  exit 1
fi

"$EX_DOC_PATH" "syn" $version "_build/default/lib/syn/ebin" \
  --source-ref ${version} \
  --config docs.config $@
