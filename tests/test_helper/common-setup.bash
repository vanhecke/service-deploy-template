#!/usr/bin/env bash

_common_setup() {
    export BATS_LIB_PATH="${BATS_TEST_DIRNAME}/test_helper:${BATS_LIB_PATH:-/usr/lib}"
    bats_load_library bats-support
    bats_load_library bats-assert
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export PROJECT_ROOT
    export NO_COLOR=1
}
