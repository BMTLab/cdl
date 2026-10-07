#!/usr/bin/env bats

# Name: tests/integration/test_stdin.bats
# Author: Nikita Neverov (BMTLab)
# License: MIT
#
# Description:
#   A path piped into cdl, and the stdin cdl must leave alone.
#   bash and zsh differ by design here:
#   bash runs the last command of a pipeline in a subshell,
#   zsh runs it in the current shell.
#
#   Each test follows the Arrange-Act-Assert pattern.

bats_require_minimum_version 1.11.0

load '../support/test_helper'

function setup() {
  sandbox_setup
}

# region Reading a pipe

@test "a piped path is listed" {
  # Arrange
  require_gnu_compatible_ls
  local -r target="$(make_dir 'target')"
  make_entries "${target}" 'piped-entry'

  # Act
  run --separate-stderr in_shell 'printf "%s\n" "$1" | cdl' "${target}"

  # Assert
  assert_success
  assert_output "$(listing_row '0' 'piped-entry')"
}

@test "a piped path changes the directory in zsh but not in bash" {
  # Arrange
  local -r target="$(make_dir 'target')"
  local expected="${HOME}"
  if [[ ${CDL_SHELL_KIND} == 'zsh' ]]; then
    expected="${target}"
  fi

  # Act
  run --separate-stderr in_shell \
    'printf "%s\n" "$1" | cdl >/dev/null; printf "%s\n" "$PWD"' "${target}"

  # Assert
  assert_success
  assert_output "${expected}"
}

@test "the first non-blank line of the pipe is used, trimmed" {
  # Arrange
  require_gnu_compatible_ls
  local -r target="$(make_dir 'target')"
  make_entries "${target}" 'chosen'

  # Act
  run --separate-stderr in_shell \
    'printf "\n   \n  \t%s  \nignored\n" "$1" | cdl' "${target}"

  # Assert
  assert_success
  assert_output "$(listing_row '0' 'chosen')"
}

@test "an operand wins over a piped path" {
  # Arrange
  require_gnu_compatible_ls
  local -r operand="$(make_dir 'operand')"
  local -r piped="$(make_dir 'piped')"
  make_entries "${operand}" 'from-operand'
  make_entries "${piped}" 'from-pipe'

  # Act
  run --separate-stderr in_shell \
    'printf "%s\n" "$2" | cdl "$1"' "${operand}" "${piped}"

  # Assert
  assert_success
  assert_output "$(listing_row '0' 'from-operand')"
}

@test "an empty pipe falls back to HOME" {
  # Arrange
  make_entries "${HOME}" 'home-entry'

  # Act
  run --separate-stderr in_shell \
    'cd / && printf "" | cdl'

  # Assert
  assert_success
  assert_output_contains 'home-entry'
}

# endregion

# region Stdin that is not a pipe

@test "stdin redirected from a file is not read as a path" {
  # Arrange
  local -r decoy="$(make_dir 'decoy')"
  printf '%s\n' "${decoy}" >"${BATS_TEST_TMPDIR}/paths.txt"

  # Act
  run --separate-stderr in_shell \
    'cdl <"$1" >/dev/null; printf "%s\n" "$PWD"' "${BATS_TEST_TMPDIR}/paths.txt"

  # Assert
  assert_success
  assert_output "${HOME}"
}

@test "cdl inside a while-read loop over a file leaves the loop its lines" {
  # Arrange
  printf '%s\n' one two three >"${BATS_TEST_TMPDIR}/lines.txt"

  # Act
  run --separate-stderr in_shell \
    'while IFS= read -r line; do cdl >/dev/null; printf "%s\n" "$line"; done <"$1"' \
    "${BATS_TEST_TMPDIR}/lines.txt"

  # Assert
  assert_success
  assert_output "$(printf '%s\n' one two three)"
}

# endregion

### End
