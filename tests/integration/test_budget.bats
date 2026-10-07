#!/usr/bin/env bats

# Name: tests/integration/test_budget.bats
# Author: Nikita Neverov (BMTLab)
# License: MIT
#
# Description:
#   cdl runs on every change of directory,
#   so the external commands it starts are a budget:
#   none while the file is sourced,
#   ls twice and awk once on the first listing of a session
#   (the probe that finds out what ls can do, then the listing),
#   ls once and awk once on every listing after it,
#   tput only when the shell does not set COLUMNS,
#   and never git or hostname: the header reads the branch from the files,
#   and links take the host from the shell.
#
#   Each test follows the Arrange-Act-Assert pattern.

bats_require_minimum_version 1.11.0

load '../support/test_helper'

function setup() {
  sandbox_setup
  if ! gnu_compatible_ls >/dev/null; then
    skip 'no GNU-compatible ls on this machine'
  fi
  LISTED_DIR="$(make_dir 'listed')"
  make_entries "${LISTED_DIR}" 'src/' 'notes.md'
}

# region Budget

@test "sourcing cdl.sh starts no external command" {
  # Arrange:
  # every feature that acts at sourcing is on.
  fake_logging_tools
  export CDL_REPLACE_CD=1

  # Act
  run --separate-stderr in_shell 'true'

  # Assert
  assert_success
  assert_equal "$(logged_runs ls gls awk mawk gawk tput)" '0' 'commands started'
}

@test "the first listing of a session runs ls twice and awk once" {
  # Arrange
  fake_logging_tools

  # Act
  run --separate-stderr in_shell 'cdl "$1" >/dev/null' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_equal "$(logged_runs ls gls)" '2' 'runs of ls'
  assert_equal "$(logged_runs awk mawk gawk)" '1' 'runs of awk'
}

@test "every later listing runs ls once and awk once" {
  # Arrange
  fake_logging_tools

  # Act:
  # one listing to settle the probe, then three more.
  run --separate-stderr in_shell \
    'cdl "$1" && cdl "$1" && cdl_list && cdl_list' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_equal "$(logged_runs ls gls)" '5' 'runs of ls'
  assert_equal "$(logged_runs awk mawk gawk)" '4' 'runs of awk'
}

@test "a file named by a URI starts no more commands than a directory" {
  # Arrange
  fake_logging_tools
  make_entries "${LISTED_DIR}" 'my notes.md'

  # Act
  run --separate-stderr in_shell 'cdl "$1" >/dev/null' "file://${LISTED_DIR}/my%20notes.md"

  # Assert
  assert_success
  assert_equal "$(logged_runs ls gls)" '2' 'runs of ls'
  assert_equal "$(logged_runs awk mawk gawk)" '1' 'runs of awk'
}

@test "the header reads the git branch without running git" {
  # Arrange
  fake_logging_tools
  mkdir -p "${LISTED_DIR}/.git"
  printf 'ref: refs/heads/main\n' >"${LISTED_DIR}/.git/HEAD"

  # Act
  run --separate-stderr in_shell 'CDL_HEADER=always cdl "$1"' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_output_contains ' · main · '
  assert_equal "$(logged_runs git)" '0' 'runs of git'
  assert_equal "$(logged_runs ls gls)" '2' 'runs of ls'
  assert_equal "$(logged_runs awk mawk gawk)" '1' 'runs of awk'
}

@test "links take the host from the shell without running hostname" {
  # Arrange
  fake_logging_tools

  # Act
  run --separate-stderr in_shell 'CDL_LINKS=always cdl "$1"' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_output_contains $'\033]8;;file://'
  assert_equal "$(logged_runs hostname)" '0' 'runs of hostname'
  assert_equal "$(logged_runs ls gls)" '2' 'runs of ls'
  assert_equal "$(logged_runs awk mawk gawk)" '1' 'runs of awk'
}

@test "tput runs only when the shell does not set COLUMNS" {
  # Arrange
  fake_logging_tools

  # Act
  run --separate-stderr in_shell \
    'cdl "$1" && unset COLUMNS && cdl "$1"' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_equal "$(logged_runs tput)" '1' 'runs of tput'
}

# endregion

### End
