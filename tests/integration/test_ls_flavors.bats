#!/usr/bin/env bats

# Name: tests/integration/test_ls_flavors.bats
# Author: Nikita Neverov (BMTLab)
# License: MIT
#
# Description:
#   Which ls cdl runs and how it treats each flavor:
#   gls before ls, the compact listing for GNU-compatible ls,
#   the plain listing for BSD ls, one probe per shell session.
#
#   Each test follows the Arrange-Act-Assert pattern.

bats_require_minimum_version 1.11.0

load '../support/test_helper'

function setup() {
  sandbox_setup
  LISTED_DIR="$(make_dir 'listed')"
  make_entries "${LISTED_DIR}" 'entry'
}

# region Choosing ls

@test "gls is preferred over ls when both are installed" {
  # Arrange
  fake_recording_gls

  # Act
  run --separate-stderr in_shell 'cdl "$1"' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_output "$(listing_row '0' 'entry')"
  if [[ ! -s ${GLS_LOG} ]]; then
    __assert_fail 'gls was never called'
  fi
}

@test "ls is probed once per shell session, not once per listing" {
  # Arrange
  fake_probe_counting_ls

  # Act
  run --separate-stderr in_shell \
    'cdl "$1" && cdl "$1" && cdl_list && cdl_list' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_equal "$(wc -l <"${LS_PROBE_LOG}" | tr -d ' ')" '1' 'number of probes'
}

@test "sourcing cdl.sh again probes ls again" {
  # Arrange:
  # e.g. after installing gls, a reload of ~/.bashrc must notice it.
  fake_probe_counting_ls

  # Act
  run --separate-stderr in_shell \
    'cdl_list && source "$CDL_SCRIPT" && cdl_list' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_equal "$(wc -l <"${LS_PROBE_LOG}" | tr -d ' ')" '2' 'number of probes'
}

# endregion

# region BSD ls

@test "a BSD ls listing is passed through untouched" {
  # Arrange
  fake_bsd_ls 'with-color'

  # Act
  run --separate-stderr in_shell 'cdl "$1"' "${LISTED_DIR}"

  # Assert:
  # no terminal, so no -G either.
  assert_success
  assert_output 'bsd-ls -Alh'
}

@test "a BSD ls on a terminal is asked for colors with -G" {
  # Arrange
  fake_bsd_ls 'with-color'
  export CDL_TEST_DIR="${LISTED_DIR}"

  # Act
  run --separate-stderr in_terminal 'cdl "$CDL_TEST_DIR"'

  # Assert
  assert_success
  assert_output 'bsd-ls -Alh -G'
}

@test "a BSD ls without color support still lists on a terminal" {
  # Arrange:
  # OpenBSD and NetBSD reject -G.
  fake_bsd_ls 'without-color'
  export CDL_TEST_DIR="${LISTED_DIR}"

  # Act
  run --separate-stderr in_terminal 'cdl "$CDL_TEST_DIR"'

  # Assert
  assert_success
  assert_output 'bsd-ls -Alh'
}

@test "a failing BSD ls is reported with CDL_ERR_LIST" {
  # Arrange
  fake_bsd_ls 'with-color' 1

  # Act
  run --separate-stderr cdl_then_pwd "${LISTED_DIR}"

  # Assert:
  # the directory is entered all the same.
  assert_failure 40
  assert_output "${LISTED_DIR}"
}

@test "NO_COLOR keeps -G away from a BSD ls on a terminal" {
  # Arrange
  fake_bsd_ls 'with-color'
  export CDL_TEST_DIR="${LISTED_DIR}"
  export NO_COLOR=1

  # Act
  run --separate-stderr in_terminal 'cdl "$CDL_TEST_DIR"'

  # Assert
  assert_success
  assert_output 'bsd-ls -Alh'
}

# endregion

### End
