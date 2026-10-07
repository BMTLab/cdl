#!/usr/bin/env bats

# Name: tests/integration/test_replace_cd.bats
# Author: Nikita Neverov (BMTLab)
# License: MIT
#
# Description:
#   CDL_REPLACE_CD=1, set before cdl.sh is sourced, makes cd run cdl:
#   on a terminal, with the options, files and listing of cdl,
#   and wherever an option only cdl knows asks for it.
#   Elsewhere, as in a command substitution, cd stays the shell's own,
#   and so do the options cdl does not know and the two-word cd of zsh.
#
#   Each test follows the Arrange-Act-Assert pattern.

bats_require_minimum_version 1.11.0

load '../support/test_helper'

function setup() {
  sandbox_setup
  if ! gnu_compatible_ls >/dev/null; then
    skip 'no GNU-compatible ls on this machine'
  fi

  export CDL_REPLACE_CD=1 CDL_COLOR=never CDL_HEADER=never
  NOTES_DIR="$(make_dir 'notes')"
  make_entries "${NOTES_DIR}" 'todo.txt'
  export CDL_TEST_DIR="${NOTES_DIR}"
}

#######################################
# Skip the test unless the shell under test is zsh.
#######################################
function only_in_zsh() {
  if [[ ${CDL_SHELL_KIND} != 'zsh' ]]; then
    skip 'a form of the cd of zsh'
  fi
}

# region cd as cdl

@test "on a terminal, cd enters the directory and lists it, as cdl does" {
  # Arrange: no fixtures needed.

  # Act
  run --separate-stderr in_terminal 'cd "$CDL_TEST_DIR" && printf "%s\n" "$PWD"'

  # Assert
  assert_success
  assert_output "$(listing_row 0 'todo.txt')"$'\n'"${NOTES_DIR}"
}

@test "on a terminal, cd takes a file, enters its directory and marks it" {
  # Arrange: no fixtures needed.

  # Act
  run --separate-stderr in_terminal \
    'cd "$CDL_TEST_DIR/todo.txt" && printf "%s\n" "$PWD"'

  # Assert
  assert_success
  assert_output "$(marked_row 0 'todo.txt')"$'\n'"${NOTES_DIR}"
}

@test "an option only cdl knows takes cd to cdl, even into a pipe" {
  # Arrange
  local -r cdl_version="$(in_shell 'cdl --version')"

  # Act
  run --separate-stderr in_shell 'cd --version | cat'

  # Assert
  assert_success
  assert_output "${cdl_version}"
}

@test "without CDL_REPLACE_CD, cd on a terminal is the shell's own and lists nothing" {
  # Arrange
  unset CDL_REPLACE_CD

  # Act
  run --separate-stderr in_terminal 'cd "$CDL_TEST_DIR" && printf "%s\n" "$PWD"'

  # Assert
  assert_success
  assert_output "${NOTES_DIR}"
}

@test "CDL_REPLACE_CD=0 in a running shell gives cd back to the shell" {
  # Arrange: cdl.sh replaces cd; the snippet takes it back.

  # Act
  run --separate-stderr in_terminal \
    'CDL_REPLACE_CD=0; cd "$CDL_TEST_DIR" && printf "%s\n" "$PWD"'

  # Assert
  assert_success
  assert_output "${NOTES_DIR}"
}

# endregion

# region The shell's own cd

@test "off a terminal, cd is the shell's own, so a command substitution gets the bare path" {
  # Arrange: no fixtures needed.

  # Act
  run --separate-stderr in_shell 'path="$(cd "$1" && pwd)"; printf "[%s]\n" "${path}"' \
    "${NOTES_DIR}"

  # Assert
  assert_success
  assert_output "[${NOTES_DIR}]"
}

@test "an option only the shell's cd knows goes to it, and a terminal still gets the listing" {
  # Arrange:
  # -LP is no option of cdl; bash and zsh take it, and the last letter wins,
  # so the path comes out physical.
  local -r physical_dir="$(builtin cd -P "${NOTES_DIR}" && pwd)"

  # Act
  run --separate-stderr in_terminal 'cd -LP "$CDL_TEST_DIR" && printf "%s\n" "$PWD"'

  # Assert
  assert_success
  assert_output "$(listing_row 0 'todo.txt')"$'\n'"${physical_dir}"
}

@test "in zsh, cd -0 still takes a place in the directory stack, and lists it" {
  # Arrange
  only_in_zsh

  # Act:
  # the stack holds the notes, then HOME, where the shell started;
  # -0 counts from the right, so it names HOME.
  run --separate-stderr in_terminal \
    'pushd -q "$CDL_TEST_DIR" && cd -0 && printf "pwd=%s\n" "$PWD"'

  # Assert
  assert_success
  assert_output_contains 'notes'
  assert_output_contains "pwd=${HOME}"
}

@test "in zsh, cd old new still puts new in place of old in the path" {
  # Arrange
  only_in_zsh
  make_entries "$(make_dir 'alpha')" 'docs/'
  make_entries "$(make_dir 'beta')" 'docs/'
  export CDL_TEST_DIR="${HOME}/alpha/docs"

  # Act
  run --separate-stderr in_terminal \
    'builtin cd "$CDL_TEST_DIR" && cd alpha beta && printf "pwd=%s\n" "$PWD"'

  # Assert
  assert_success
  assert_output_contains "pwd=${HOME}/beta/docs"
}

# endregion

### End
