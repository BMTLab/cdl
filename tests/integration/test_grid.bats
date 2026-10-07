#!/usr/bin/env bats

# Name: tests/integration/test_grid.bats
# Author: Nikita Neverov (BMTLab)
# License: MIT
#
# Description:
#   How many entries the listing shows and in how many columns:
#   a terminal cuts a long listing at its height and says what it left out,
#   a file or a pipe gets everything,
#   and -a, -1, CDL_MAX_ROWS and CDL_MAX_COLUMNS change both.
#   A flag wins over a setting.
#
#   Thirty entries of 36 cells sit in one column at 60 columns.
#   A terminal puts a header above them,
#   so a test counts the rows of entries apart from the lines.
#
#   Each test follows the Arrange-Act-Assert pattern.

bats_require_minimum_version 1.11.0

load '../support/test_helper'

function setup() {
  sandbox_setup
  if ! gnu_compatible_ls >/dev/null; then
    skip 'no GNU-compatible ls on this machine'
  fi

  # Thirty entries: more than a short terminal shows.
  LISTED_DIR="$(make_dir 'listed')"
  local -a names=()
  local -i number
  for ((number = 10; number < 40; number++)); do
    names+=("entry-${number}")
  done
  make_entries "${LISTED_DIR}" "${names[@]}"
  export CDL_TEST_DIR="${LISTED_DIR}"
}

#######################################
# Count the rows of entries in a listing.
#
# Arguments:
#   1: The listing.
#
# Outputs:
#   The number of lines that hold an entry to stdout.
#######################################
function entry_rows() {
  grep -c -- "${FIXTURE_DATE}" <<<"$1" || true
}

# region Cut at the terminal height

@test "a long listing on a terminal leaves the command and the next prompt on screen" {
  # Arrange:
  # ten lines keep three free and one for the header,
  # which leaves six rows in one column.
  export LINES=10 COLUMNS=60

  # Act
  run --separate-stderr in_terminal 'cdl "${CDL_TEST_DIR}"'

  # Assert:
  # the header, six rows and the note take eight lines.
  assert_success
  assert_equal "${#lines[@]}" '8' 'lines'
  assert_equal "$(entry_rows "${output}")" '6' 'rows of entries'
  assert_equal "$(strip_escapes <<<"${lines[7]}")" '… 24 more; -a shows all' 'the last line'
}

@test "without a header, the cut keeps one more row" {
  # Arrange
  export LINES=10 COLUMNS=60 CDL_HEADER='never'

  # Act
  run --separate-stderr in_terminal 'cdl "${CDL_TEST_DIR}"'

  # Assert
  assert_success
  assert_equal "${#lines[@]}" '8' 'lines'
  assert_equal "$(entry_rows "${output}")" '7' 'rows of entries'
  assert_equal "$(strip_escapes <<<"${lines[7]}")" '… 23 more; -a shows all' 'the last line'
}

@test "a terminal too short for the listing still shows five rows" {
  # Arrange
  export LINES=3 COLUMNS=60

  # Act
  run --separate-stderr in_terminal 'cdl "${CDL_TEST_DIR}"'

  # Assert:
  # the header, five rows and the note.
  assert_success
  assert_equal "${#lines[@]}" '7' 'lines'
  assert_equal "$(entry_rows "${output}")" '5' 'rows of entries'
  assert_equal "$(strip_escapes <<<"${lines[6]}")" '… 25 more; -a shows all' 'the last line'
}

@test "-a shows every entry on a terminal, from cdl and from cdl_list" {
  # Arrange
  export LINES=10 COLUMNS=60

  # Act:
  # both listings go to the terminal itself, so a cut would show.
  run --separate-stderr in_terminal \
    'cd "${CDL_TEST_DIR}" && cdl -a . && echo -- && cdl_list --all'

  # Assert:
  # thirty rows from each, and no note about a cut.
  assert_success
  assert_equal "$(entry_rows "${output}")" '60' 'rows of entries'
  refute_output_contains 'more; -a shows all'
}

@test "a listing sent to a pipe is never cut" {
  # Arrange
  export LINES=10 COLUMNS=60

  # Act
  run --separate-stderr in_shell 'cdl "$1"' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_equal "${#lines[@]}" '30' 'lines'
}

@test "CDL_MAX_ROWS cuts a listing, even in a pipe" {
  # Arrange
  export COLUMNS=60 CDL_MAX_ROWS=4

  # Act
  run --separate-stderr in_shell 'cdl "$1"' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_equal "${#lines[@]}" '5' 'lines'
  assert_equal "${lines[4]}" '… 26 more; -a shows all' 'the last line'
}

@test "CDL_MAX_ROWS=0 never cuts, even on a terminal" {
  # Arrange
  export LINES=10 COLUMNS=60 CDL_MAX_ROWS=0

  # Act
  run --separate-stderr in_terminal 'cdl "${CDL_TEST_DIR}"'

  # Assert
  assert_success
  assert_equal "$(entry_rows "${output}")" '30' 'rows of entries'
  refute_output_contains 'more; -a shows all'
}

@test "-a wins over CDL_MAX_ROWS" {
  # Arrange
  export COLUMNS=60 CDL_MAX_ROWS=4

  # Act
  run --separate-stderr in_shell 'cdl -a "$1"' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_equal "${#lines[@]}" '30' 'lines'
}

# endregion

# region Columns

@test "-1 puts one entry per row, from cdl and from cdl_list" {
  # Arrange
  export COLUMNS=200

  # Act
  run --separate-stderr in_shell \
    'cd "$1" && cdl -1 . | wc -l && cdl_list --one-column | wc -l' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_equal "$(tr -d ' ' <<<"${output}")" $'30\n30' 'rows'
}

@test "CDL_MAX_COLUMNS caps the columns" {
  # Arrange:
  # 200 columns would take five of these entries side by side.
  export COLUMNS=200 CDL_MAX_COLUMNS=2

  # Act
  run --separate-stderr in_shell 'cdl "$1"' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_equal "$(grid_columns "${output}")" '2' 'columns'
  assert_columns_aligned "${output}"
}

@test "-1 wins over CDL_MAX_COLUMNS" {
  # Arrange
  export COLUMNS=200 CDL_MAX_COLUMNS=3

  # Act
  run --separate-stderr in_shell 'cdl -1 "$1"' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_one_column "${output}"
}

# endregion

### End
