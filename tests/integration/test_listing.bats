#!/usr/bin/env bats

# Name: tests/integration/test_listing.bats
# Author: Nikita Neverov (BMTLab)
# License: MIT
#
# Description:
#   The listing cdl prints for real directories,
#   through the ls found on this machine:
#   GNU ls, uutils ls or gls for the compact listing.
#   Machines with only a BSD ls skip these tests;
#   the BSD path is covered by test_ls_flavors.bats.
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
}

# region Content

@test "directories come before files" {
  # Arrange
  make_entries "${LISTED_DIR}" 'a-file' 'z-dir/' 'b-file' 'c-dir/'

  # Act
  run --separate-stderr in_shell 'COLUMNS=60 cdl "$1"' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_equal "$(strip_escapes <<<"${output}" | awk '{ print $NF }')" \
    "$(printf '%s\n' c-dir z-dir a-file b-file)" 'order of names'
}

@test "names sort by bytes, uppercase first, whatever the locale" {
  # Arrange
  make_entries "${LISTED_DIR}" 'beta' 'Alpha' 'alpha' 'Beta' 'Ёлка' 'ёж'

  # Act
  run --separate-stderr in_shell 'COLUMNS=60 cdl "$1"' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_equal "$(awk '{ print $NF }' <<<"${output}")" \
    "$(printf '%s\n' Alpha Beta alpha beta Ёлка ёж)" 'order of names'
}

@test "hidden entries are listed, but not . and .." {
  # Arrange
  make_entries "${LISTED_DIR}" '.hidden' 'visible'

  # Act
  run --separate-stderr in_shell 'COLUMNS=60 cdl "$1"' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_output "$(
    listing_row '0' '.hidden'
    printf '\n'
    listing_row '0' 'visible'
  )"
}

@test "QUOTING_STYLE in the environment leaves the names as they are" {
  # Arrange
  make_entries "${LISTED_DIR}" 'two words'

  # Act
  run --separate-stderr in_shell 'QUOTING_STYLE=shell-escape cdl "$1"' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_output_contains "${FIXTURE_DATE}  two words"
}

@test "a symlink is shown with its target" {
  # Arrange
  make_entries "${LISTED_DIR}" 'target.txt' 'link -> target.txt'

  # Act
  run --separate-stderr in_shell 'COLUMNS=60 cdl "$1"' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_output_contains 'link -> target.txt'
}

@test "a name with runs of spaces is shown verbatim" {
  # Arrange
  make_entries "${LISTED_DIR}" 'two  spaces   inside'

  # Act
  run --separate-stderr in_shell 'cdl "$1"' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_output "$(listing_row '0' 'two  spaces   inside')"
}

@test "an empty directory prints nothing" {
  # Arrange: the listed directory starts empty.

  # Act
  run --separate-stderr in_shell 'cdl "$1"' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_output ''
  assert_no_stderr
}

@test "a device file shows its major and minor numbers as the size" {
  # Arrange: /dev/null exists on every supported system.

  # Act
  run --separate-stderr in_shell 'COLUMNS=60 cdl /dev'

  # Assert
  assert_success
  local -r device_row='^ *[0-9]+, *[0-9]+  [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}  null$'
  local -r null_row="$(grep ' null$' <<<"${output}")"
  if [[ ! ${null_row} =~ ${device_row} ]]; then
    __assert_fail "unexpected /dev/null row: ${null_row}"
  fi
}

# endregion

# region Layout

# bats test_tags=smoke
@test "a wide terminal gets aligned columns that fit its width" {
  # Arrange
  make_entries "${LISTED_DIR}" 'Документы/' 'src/' 'notes.md' '日本語.txt' 'README'

  # Act
  run --separate-stderr in_shell 'COLUMNS=120 cdl "$1"' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_columns_aligned "${output}"
  assert_fits_width "${output}" 120
}

@test "a narrow terminal gets one column" {
  # Arrange
  make_entries "${LISTED_DIR}" 'src/' 'notes.md' 'README' 'Makefile'

  # Act
  run --separate-stderr in_shell 'COLUMNS=50 cdl "$1"' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_one_column "${output}"
}

@test "a piped path gets the terminal width too" {
  # Arrange:
  # bash runs a piped cdl in a subshell, where tput cannot see
  # the terminal; the width must still come from COLUMNS.
  make_entries "${LISTED_DIR}" 'src/' 'notes.md' 'README' 'Makefile'

  # Act
  run --separate-stderr in_shell \
    'printf "%s\n" "$1" | COLUMNS=120 cdl' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_columns_aligned "${output}"
}

#######################################
# Check that a COLUMNS cdl cannot use falls back to 80 columns.
#
# Without TERM, tput fails too, which leaves the last resort:
# rows that would sit side by side in 120 columns stay in one.
#
# Arguments:
#   1: The unusable value of COLUMNS.
#######################################
function unusable_columns_fall_back_to_80() {
  local -r columns="$1"

  # Arrange
  make_entries "${LISTED_DIR}" 'a-name-of-some-length.txt' 'another-name-of-length.txt'

  # Act
  run --separate-stderr in_shell \
    'unset TERM; COLUMNS="$2" cdl "$1"' "${LISTED_DIR}" "${columns}"

  # Assert
  assert_success
  assert_one_column "${output}"
  assert_no_stderr
}

for __columns in 'abc' '0' '080' '-1'; do
  bats_test_function \
    --description "COLUMNS='${__columns}' falls back to 80 columns" \
    -- unusable_columns_fall_back_to_80 "${__columns}"
done

# endregion

# region Sizes

@test "sizes read as GNU ls -h writes them, even through uutils ls" {
  # Arrange:
  # sparse files at the steps of the rounding in every unit,
  # each named by its size.
  local reference_ls
  reference_ls="$(gnu_ls)" || skip 'no GNU ls to compare with'
  local -r dir="$(make_dir 'sizes')"
  local -a sizes=(0 1 1023)
  local -i unit
  for unit in 1024 1048576 1073741824; do
    sizes+=(
      "${unit}" "$((unit + 1))" "$((unit * 5 + unit / 2))"
      "$((unit * 10 - 1))" "$((unit * 10))" "$((unit * 10 + 1))"
      "$((unit * 1023))" "$((unit * 1023 + 1))" "$((unit * 1024 - 1))"
    )
  done
  local size
  for size in "${sizes[@]}"; do
    dd if=/dev/null of="${dir}/${size}" bs=1 seek="${size}" 2>/dev/null
  done
  local -r expected="$(
    LC_ALL=C "${reference_ls}" -lh "${dir}" | awk 'NF > 2 { print $NF, $5 }' | sort
  )"

  # Act
  run --separate-stderr in_shell 'CDL_MAX_COLUMNS=1 cdl "$1"' "${dir}"

  # Assert:
  # each name with its size, as the two listings give them.
  assert_success
  assert_equal "$(awk '{ print $NF, $1 }' <<<"${output}" | sort)" "${expected}" 'sizes'
}

@test "BLOCK_SIZE in the environment leaves the sizes alone" {
  # Arrange:
  # ls reads both variables, and would print 4.9K, or blocks, for these bytes.
  printf '%5000s' '' >"${LISTED_DIR}/five-thousand"

  # Act
  run --separate-stderr in_shell \
    'BLOCK_SIZE=human-readable LS_BLOCK_SIZE=1K cdl "$1"' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_output_contains '4.9K  '
}

# endregion

# region Colors

@test "a listing sent to a pipe or a file has no escape sequences" {
  # Arrange
  make_entries "${LISTED_DIR}" 'src/' 'run.sh*' 'link -> run.sh'

  # Act
  run --separate-stderr in_shell 'cdl "$1"' "${LISTED_DIR}"

  # Assert
  assert_success
  refute_output_contains $'\033'
}

# bats test_tags=smoke
@test "a listing on a terminal is colored" {
  # Arrange
  make_entries "${LISTED_DIR}" 'src/' 'run.sh*'
  export CDL_TEST_DIR="${LISTED_DIR}"

  # Act
  run --separate-stderr in_terminal 'cdl "$CDL_TEST_DIR"'

  # Assert
  assert_success
  assert_output_contains $'\033[01;34msrc'
}

@test "an empty NO_COLOR keeps the colors, as no-color.org asks" {
  # Arrange:
  # only a NO_COLOR that is set and not empty turns colors off.
  make_entries "${LISTED_DIR}" 'src/'
  export CDL_TEST_DIR="${LISTED_DIR}"
  export NO_COLOR=''

  # Act
  run --separate-stderr in_terminal 'cdl "$CDL_TEST_DIR"'

  # Assert
  assert_success
  assert_output_contains $'\033[01;34msrc'
}

@test "NO_COLOR turns colors off, even on a terminal" {
  # Arrange
  make_entries "${LISTED_DIR}" 'src/' 'run.sh*'
  export CDL_TEST_DIR="${LISTED_DIR}"
  export NO_COLOR=1

  # Act
  run --separate-stderr in_terminal 'cdl "$CDL_TEST_DIR"'

  # Assert
  assert_success
  assert_output_contains 'src'
  refute_output_contains $'\033'
}

# endregion

# region Links

@test "a colored terminal gets names linked to their files" {
  # Arrange
  make_entries "${LISTED_DIR}" 'notes.md'
  export CDL_TEST_DIR="${LISTED_DIR}" HOSTNAME='box'

  # Act
  run --separate-stderr in_terminal 'cdl "$CDL_TEST_DIR"'

  # Assert
  assert_success
  assert_output_contains "$(hyperlink "file://box${LISTED_DIR}/notes.md" 'notes.md')"
}

@test "the Linux console gets colors but no links, which it would print as text" {
  # Arrange
  make_entries "${LISTED_DIR}" 'src/'
  export CDL_TEST_DIR="${LISTED_DIR}" TERM='linux'

  # Act
  run --separate-stderr in_terminal 'cdl "$CDL_TEST_DIR"'

  # Assert
  assert_success
  assert_output_contains $'\033[01;34msrc'
  refute_output_contains $'\033]8;;'
}

@test "CDL_LINKS=never keeps a terminal free of links" {
  # Arrange
  make_entries "${LISTED_DIR}" 'src/'
  export CDL_TEST_DIR="${LISTED_DIR}" CDL_LINKS='never'

  # Act
  run --separate-stderr in_terminal 'cdl "$CDL_TEST_DIR"'

  # Assert
  assert_success
  refute_output_contains $'\033]8;;'
}

@test "CDL_LINKS=always links the names in a pipe too" {
  # Arrange
  make_entries "${LISTED_DIR}" 'notes.md'
  export HOSTNAME='box'

  # Act
  run --separate-stderr in_shell 'CDL_LINKS=always cdl "$1"' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_output_contains "$(hyperlink "file://box${LISTED_DIR}/notes.md" 'notes.md')"
}

# endregion

### End
