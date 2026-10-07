#!/usr/bin/env bats

# Name: tests/integration/test_settings.bats
# Author: Nikita Neverov (BMTLab)
# License: MIT
#
# Description:
#   The settings of cdl, which come from environment variables,
#   and the options of cdl that are not about the listing:
#   --version, and -L and -P for cd.
#   A setting is checked before cdl moves,
#   so a typo in an rc file shows at once and changes nothing.
#
#   Each test follows the Arrange-Act-Assert pattern.

bats_require_minimum_version 1.11.0

load '../support/test_helper'

function setup() {
  sandbox_setup
  LISTED_DIR="$(make_dir 'listed')"
  make_entries "${LISTED_DIR}" '.hidden' 'src/' 'visible'
}

# region Version

@test "cdl --version prints the version in the header of cdl.sh" {
  # Arrange
  local -r version="$(sed -n 's/^# Version: *//p' "${CDL_SCRIPT}")"

  # Act
  run --separate-stderr in_shell 'cdl --version && cdl -V'

  # Assert
  assert_success
  assert_output "cdl ${version}"$'\n'"cdl ${version}"
}

# endregion

# region Invalid values

#######################################
# Check that an invalid setting fails before cdl moves.
#
# Arguments:
#   1: Variable.
#   2: Invalid value.
#   3: What the error says the value is not.
#######################################
function invalid_setting_fails_before_moving() {
  local -r variable="$1"
  local -r value="$2"
  local -r expectation="$3"

  # Arrange: the sandbox starts in HOME.

  # Act
  run --separate-stderr in_shell \
    'export "$1=$2"; cdl "$3"; rc=$?; printf "%s\n" "$PWD"; exit "$rc"' \
    "${variable}" "${value}" "${LISTED_DIR}"

  # Assert
  assert_failure 20
  assert_output "${HOME}"
  assert_stderr_contains "cdl: ${variable}: ${expectation}: '${value}'"
}

# Samples: "variable|value|expectation".
__INVALID_SETTINGS=(
  'CDL_COLOR|blue|not auto, always or never'
  'CDL_COLOR|ALWAYS|not auto, always or never'
  'CDL_HIDDEN|yes|not 0 or 1'
  'CDL_HIDDEN|2|not 0 or 1'
  'CDL_WIDTH|abc|not a positive number'
  'CDL_WIDTH|0|not a positive number'
  'CDL_WIDTH|080|not a positive number'
  'CDL_MAX_ROWS|-1|not a number'
  'CDL_MAX_ROWS|many|not a number'
  'CDL_MAX_COLUMNS|x|not a number'
  'CDL_HEADER|yes|not auto, always or never'
  'CDL_GIT|true|not 0 or 1'
  'CDL_LINKS|on|not auto, always or never'
  'CDL_REPLACE_CD|yes|not 0 or 1'
)

for __sample in "${__INVALID_SETTINGS[@]}"; do
  IFS='|' read -r __variable __value __expectation <<<"${__sample}"
  bats_test_function \
    --description "${__variable}='${__value}' fails with CDL_ERR_SETTING before cdl moves" \
    -- invalid_setting_fails_before_moving "${__variable}" "${__value}" "${__expectation}"
done

@test "an empty setting counts as unset" {
  # Arrange: no fixtures needed.

  # Act
  run --separate-stderr in_shell \
    'CDL_COLOR= CDL_HIDDEN= CDL_WIDTH= CDL_MAX_ROWS= CDL_MAX_COLUMNS= CDL_HEADER= CDL_GIT= CDL_LINKS= CDL_REPLACE_CD= cdl "$1"' \
    "${LISTED_DIR}"

  # Assert:
  # the defaults: hidden entries listed, no error.
  assert_success
  assert_output_contains '.hidden'
  assert_no_stderr
}

@test "-h and -V answer even when a setting is invalid" {
  # Arrange:
  # the help must stay reachable to fix the setting.
  export CDL_COLOR='blue'

  # Act
  run --separate-stderr in_shell 'cdl -h >/dev/null && cdl -V'

  # Assert
  assert_success
  assert_output_contains 'cdl '
}

@test "-V wins over the words that follow it" {
  # Arrange: no fixtures needed.

  # Act
  run --separate-stderr in_shell 'cdl -V somewhere else && printf "PWD=%s\n" "$PWD"'

  # Assert
  assert_success
  assert_output_contains "PWD=${HOME}"
}

@test "an invalid setting stops cdl_list too" {
  # Arrange: no fixtures needed.

  # Act
  run --separate-stderr in_shell 'CDL_HIDDEN=maybe cdl_list'

  # Assert
  assert_failure 20
  assert_output ''
  assert_stderr_contains "cdl: CDL_HIDDEN: not 0 or 1: 'maybe'"
}

# endregion

# region Colors

@test "CDL_COLOR=always colors a listing that goes to a pipe" {
  # Arrange: no terminal, so auto would print plain text.

  # Act
  run --separate-stderr in_shell 'CDL_COLOR=always cdl "$1"' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_output_contains $'\033[01;34msrc'
}

@test "CDL_COLOR=always wins over NO_COLOR, as no-color.org asks" {
  # Arrange
  export NO_COLOR=1

  # Act
  run --separate-stderr in_shell 'CDL_COLOR=always cdl "$1"' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_output_contains $'\033[01;34msrc'
}

@test "CDL_COLOR=never keeps a terminal plain" {
  # Arrange
  export CDL_TEST_DIR="${LISTED_DIR}"
  export CDL_COLOR='never'

  # Act
  run --separate-stderr in_terminal 'cdl "${CDL_TEST_DIR}"'

  # Assert
  assert_success
  assert_output_contains 'src'
  refute_output_contains $'\033'
}

# endregion

# region Hidden entries

@test "CDL_HIDDEN=0 leaves hidden entries out" {
  # Arrange: the listed directory holds .hidden, src and visible.

  # Act
  run --separate-stderr in_shell 'CDL_HIDDEN=0 cdl "$1"' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_output_contains 'visible'
  refute_output_contains '.hidden'
}

@test "CDL_HIDDEN=0 asks a BSD ls for no hidden entries either" {
  # Arrange
  fake_bsd_ls 'with-color'

  # Act
  run --separate-stderr in_shell 'CDL_HIDDEN=0 cdl "$1"' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_output 'bsd-ls -lh'
}

# endregion

# region Width

@test "CDL_WIDTH wins over COLUMNS" {
  # Arrange:
  # these rows sit side by side in 130 columns, but not in 80.
  make_entries "${LISTED_DIR}" 'a-name-of-some-length.txt' 'another-name-of-length.txt'

  # Act
  run --separate-stderr in_shell \
    'COLUMNS=80 CDL_WIDTH=130 CDL_HIDDEN=0 cdl "$1"' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_columns_aligned "${output}"
}

# endregion

# region Symbolic links

@test "cdl -P enters the directory a symlink resolves to" {
  # Arrange
  make_dir 'real' >/dev/null
  make_entries "${HOME}" 'link -> real'

  # Act
  run --separate-stderr cdl_then_pwd -P "${HOME}/link"

  # Assert
  assert_success
  assert_output "${HOME}/real"
}

@test "the last of -L and -P wins, in bash and zsh alike" {
  # Arrange
  make_dir 'real' >/dev/null
  make_entries "${HOME}" 'link -> real'

  # Act
  run --separate-stderr in_shell \
    'cdl -L -P "$1" >/dev/null && printf "%s\n" "$PWD" && cdl -P -L "$1" >/dev/null && printf "%s\n" "$PWD"' \
    "${HOME}/link"

  # Assert
  assert_success
  assert_output "${HOME}/real"$'\n'"${HOME}/link"
}

@test "cdl -L, like plain cdl, keeps the symlink in the path" {
  # Arrange
  make_dir 'real' >/dev/null
  make_entries "${HOME}" 'link -> real'

  # Act
  run --separate-stderr in_shell \
    'cdl -L "$1" >/dev/null && printf "%s\n" "$PWD" && cdl "$1" >/dev/null && printf "%s\n" "$PWD"' \
    "${HOME}/link"

  # Assert
  assert_success
  assert_output "${HOME}/link"$'\n'"${HOME}/link"
}

# endregion

# region cdl_list

@test "cdl_list refuses an option it does not know" {
  # Arrange: no fixtures needed.

  # Act
  run --separate-stderr in_shell 'cdl_list -x'

  # Assert
  assert_failure 10
  assert_stderr_contains "cdl: Unknown option: '-x'"
}

@test "cdl_list refuses a directory: it lists where the shell is" {
  # Arrange: no fixtures needed.

  # Act
  run --separate-stderr in_shell 'cdl_list "$1"' "${LISTED_DIR}"

  # Assert
  assert_failure 10
  assert_stderr_contains "cdl: Unexpected argument: '${LISTED_DIR}'"
}

# endregion

### End
