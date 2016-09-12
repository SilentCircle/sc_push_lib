#!/bin/bash

# Test the fairly complex rebar.config.script
TEST_DIR="$(pwd)/extra_test"
LOGDIR="$TEST_DIR/logs"
# So this has such a funky name because rebar will grab anything
# that ends in "spec" and use it to test with. Unfortunately, this
# makes things break, so... funky name.
TEST_SPEC="$(pwd)/rebar_script_spec_for_test"

mkdir -p $LOGDIR

ct_run \
    -pa $(pwd) \
    -noshell \
    -sname test_rebar_script \
    -logdir "$LOGDIR" \
    -env REBAR_DIR "$(pwd)" \
    -env TEST_DIR "$TEST_DIR" \
    -spec "$TEST_SPEC"

