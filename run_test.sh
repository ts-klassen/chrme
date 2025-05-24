#!/bin/bash

if [ ! -x /usr/bin/google-chrome ]; then
  echo "Error: /usr/bin/google-chrome not found or not executable" >&2
  exit 1
fi

rebar3 eunit &&
rebar3 ct --verbose &&
rebar3 cover &&
rebar3 edoc &&
echo ALL_TEST_PASS