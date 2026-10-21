#!/usr/bin/env bats

# Test the command line of bench.sh, and how the guard of a tool ends a bug.

bats_require_minimum_version 1.11.0

load '../support/test_helper'

# region bench.sh

#######################################
# Check that bench.sh refuses a wrong command line with its usage code.
#
# Arguments:
#   $@: The command line.
#######################################
function a_wrong_command_line_of_bench_ends_with_usage() {
  # Arrange: the command line is the input.

  # Act
  run --separate-stderr "${CDL_ROOT}/tools/bench.sh" "$@"

  # Assert
  assert_failure 40
  assert_stderr_contains 'bench: '
}

bats_test_function \
  --description 'bench.sh -n without a number ends with BENCH_ERR_USAGE' \
  -- a_wrong_command_line_of_bench_ends_with_usage -n
bats_test_function \
  --description 'bench.sh -n with a word ends with BENCH_ERR_USAGE' \
  -- a_wrong_command_line_of_bench_ends_with_usage -n many
bats_test_function \
  --description 'bench.sh -d without a directory ends with BENCH_ERR_USAGE' \
  -- a_wrong_command_line_of_bench_ends_with_usage -d
bats_test_function \
  --description 'bench.sh with an unknown option ends with BENCH_ERR_USAGE' \
  -- a_wrong_command_line_of_bench_ends_with_usage --bogus

# endregion bench.sh

# region The guard

@test "a failure that no code planned ends a tool with its internal code" {
  # Arrange:
  # a directory stands where the summary of the run should go,
  # so the write in the body of main fails.

  # Act
  run --separate-stderr env GITHUB_STEP_SUMMARY="${BATS_TEST_TMPDIR}" \
    "${CDL_ROOT}/tools/ci/report-environment.sh" bash

  # Assert
  assert_failure 99
  assert_stderr_contains 'report-environment: internal error at line'
}

# endregion The guard

### End
