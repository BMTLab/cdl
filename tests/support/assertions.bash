#!/usr/bin/env bash

# Name: tests/support/assertions.bash
# Author: Nikita Neverov (BMTLab)
# License: MIT
#
# Description:
#   Assertions over the `status`, `output` and `stderr`
#   that bats' `run --separate-stderr` leaves behind.
#   On failure each one prints what it expected,
#   what it got, and the whole run,
#   so a red test explains itself without a rerun.
#
#   Loaded by tests/support/test_helper.bash.

# region Status

#######################################
# Assert the last run succeeded.
#######################################
function assert_success() {
  if ((status != 0)); then
    __assert_fail "expected success, got status ${status}"
  fi
}

#######################################
# Assert the last run failed with the given status.
#
# Arguments:
#   1: Expected status.
#######################################
function assert_failure() {
  local -ir expected="$1"

  if ((status != expected)); then
    __assert_fail "expected status ${expected}, got ${status}"
  fi
}

# endregion

# region Output

#######################################
# Assert stdout of the last run equals the expected text.
#
# Arguments:
#   1: Expected output.
#######################################
function assert_output() {
  local -r expected="$1"

  if [[ ${output} != "${expected}" ]]; then
    __assert_fail 'output differs' "${expected}" "${output}"
  fi
}

#######################################
# Assert stdout of the last run contains a fragment.
#
# Arguments:
#   1: Expected fragment.
#######################################
function assert_output_contains() {
  local -r fragment="$1"

  if [[ ${output} != *"${fragment}"* ]]; then
    __assert_fail "output lacks: ${fragment}"
  fi
}

#######################################
# Assert stdout of the last run does not contain a fragment.
#
# Arguments:
#   1: Unwanted fragment.
#######################################
function refute_output_contains() {
  local -r fragment="$1"

  if [[ ${output} == *"${fragment}"* ]]; then
    __assert_fail "output must not contain: ${fragment}"
  fi
}

#######################################
# Assert stderr of the last run contains a fragment.
#
# Arguments:
#   1: Expected fragment.
#######################################
function assert_stderr_contains() {
  local -r fragment="$1"

  if [[ ${stderr-} != *"${fragment}"* ]]; then
    __assert_fail "stderr lacks: ${fragment}"
  fi
}

#######################################
# Assert the last run printed nothing on stderr.
#######################################
function assert_no_stderr() {
  if [[ -n ${stderr-} ]]; then
    __assert_fail 'expected an empty stderr'
  fi
}

#######################################
# Assert two values are equal.
#
# Arguments:
#   1: Actual value.
#   2: Expected value.
#   3: What the value is, for the failure message.
#######################################
function assert_equal() {
  local -r actual="$1"
  local -r expected="$2"
  local -r subject="$3"

  if [[ ${actual} != "${expected}" ]]; then
    __assert_fail "${subject} differs" "${expected}" "${actual}"
  fi
}

# endregion

# region Failure report

#######################################
# Report a failed assertion and fail the test.
#
# Arguments:
#   1: What went wrong.
#   2: Expected text (optional).
#   3: Actual text (optional).
#
# Outputs:
#   The report to stderr, which bats shows for failed tests.
#
# Returns:
#   1, always.
#######################################
function __assert_fail() {
  local -r message="$1"

  {
    printf -- '-- %s --\n' "${message}"
    if (($# == 3)); then
      diff -u --label expected --label actual \
        <(printf '%s\n' "$2") <(printf '%s\n' "$3") || true
    fi
    printf 'status: %s\n' "${status-}"
    printf 'output:\n%s\n' "${output-}"
    printf 'stderr:\n%s\n' "${stderr-}"
    printf -- '--\n'
  } >&2

  return 1
}

# endregion

### End
