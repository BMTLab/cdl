#!/usr/bin/env bats

# Name: tests/integration/test_navigation.bats
# Author: Nikita Neverov (BMTLab)
# License: MIT
#
# Description:
#   How cdl picks the target directory, enters it,
#   and what it reports when it cannot.
#   The pipe as a source of the target lives in test_stdin.bats,
#   files, URIs and a leading ~ in test_paths.bats.
#
#   Each test follows the Arrange-Act-Assert pattern.

bats_require_minimum_version 1.11.0

load '../support/test_helper'

function setup() {
  sandbox_setup
}

# region Target selection

# bats test_tags=smoke
@test "cdl changes into the directory given as its operand" {
  # Arrange
  local -r target="$(make_dir 'projects/app')"

  # Act
  run --separate-stderr cdl_then_pwd "${target}"

  # Assert
  assert_success
  assert_output "${target}"
}

@test "cdl without an operand goes to HOME, like cd" {
  # Arrange
  local -r elsewhere="$(make_dir 'elsewhere')"

  # Act
  run --separate-stderr in_shell \
    'cd "$1" && cdl >/dev/null && printf "%s\n" "$PWD"' "${elsewhere}"

  # Assert
  assert_success
  assert_output "${HOME}"
}

# bats test_tags=smoke
@test "cdl - returns to the previous directory" {
  # Arrange
  local -r first="$(make_dir 'first')"
  local -r second="$(make_dir 'second')"

  # Act
  run --separate-stderr in_shell \
    'cd "$1" && cd "$2" && cdl - >/dev/null && printf "%s\n" "$PWD"' \
    "${first}" "${second}"

  # Assert
  assert_success
  assert_output "${first}"
}

@test "-- alone goes to HOME, like no operand at all" {
  # Arrange
  local -r elsewhere="$(make_dir 'elsewhere')"

  # Act
  run --separate-stderr in_shell \
    'cd "$1" && cdl -- >/dev/null && printf "%s\n" "$PWD"' "${elsewhere}"

  # Assert
  assert_success
  assert_output "${HOME}"
}

@test "without HOME, cdl goes to the root directory" {
  # Arrange: no fixtures needed.

  # Act
  run --separate-stderr in_shell \
    'unset HOME; cdl >/dev/null; printf "%s\n" "$PWD"'

  # Assert
  assert_success
  assert_output '/'
}

@test "-- makes the next word a directory even when it starts with a dash" {
  # Arrange
  local -r target="$(make_dir '-dashed dir')"

  # Act
  run --separate-stderr in_shell \
    'cd "$1" && cdl -- "-dashed dir" >/dev/null && printf "%s\n" "$PWD"' \
    "${HOME}"

  # Assert
  assert_success
  assert_output "${target}"
}

@test "a CDPATH match is entered without echoing its path" {
  # Arrange:
  # cd prints the directory it found through CDPATH;
  # the listing must be all that cdl prints.
  require_gnu_compatible_ls
  local -r base="$(make_dir 'base')"
  make_entries "$(make_dir 'base/target')" 'only-file'

  # Act
  run --separate-stderr in_shell 'CDPATH="$1" cdl target' "${base}"

  # Assert
  assert_success
  assert_output "$(listing_row '0' 'only-file')"
}

@test "cdl enters the directory itself, bypassing a user cd function" {
  # Arrange
  local -r target="$(make_dir 'target')"

  # Act
  run --separate-stderr in_shell \
    'function cd() { echo "user cd called"; }
     cdl "$1" >/dev/null && printf "%s\n" "$PWD"' "${target}"

  # Assert
  assert_success
  assert_output "${target}"
}

# endregion

# region Usage errors

@test "-h prints the usage and stays in the current directory" {
  # Arrange: no fixtures needed.

  # Act
  run --separate-stderr in_shell 'cdl -h && printf "PWD=%s\n" "$PWD"'

  # Assert
  assert_success
  assert_output_contains 'Usage: cdl'
  assert_output_contains "PWD=${HOME}"
}

@test "-h wins over the words that follow it" {
  # Arrange: no fixtures needed.

  # Act
  run --separate-stderr in_shell \
    'cdl -h somewhere else && printf "PWD=%s\n" "$PWD"'

  # Assert
  assert_success
  assert_output_contains 'Usage: cdl'
  assert_output_contains "PWD=${HOME}"
}

@test "an empty operand fails with CDL_ERR_USAGE instead of going HOME" {
  # Arrange:
  # an empty substitution, such as "$(xclip -o)" with an empty clipboard.
  local -r elsewhere="$(make_dir 'elsewhere')"

  # Act
  run --separate-stderr in_shell \
    'cd "$1" && cdl ""; rc=$?; printf "%s\n" "$PWD"; exit "$rc"' "${elsewhere}"

  # Assert
  assert_failure 10
  assert_output "${elsewhere}"
  assert_stderr_contains 'cdl: Empty directory name'
}

# bats test_tags=smoke
@test "an unknown option fails with CDL_ERR_USAGE and stays put" {
  # Arrange: no fixtures needed.

  # Act
  run --separate-stderr cdl_then_pwd -x

  # Assert
  assert_failure 10
  assert_output "${HOME}"
  assert_stderr_contains "cdl: Unknown option: '-x'"
}

@test "an option after the directory fails and says options go first" {
  # Arrange
  local -r target="$(make_dir 'target')"

  # Act
  run --separate-stderr cdl_then_pwd "${target}" -P

  # Assert
  assert_failure 10
  assert_output "${HOME}"
  assert_stderr_contains "cdl: Options go before the directory: '-P'"
}

@test "a second operand fails with CDL_ERR_USAGE instead of being ignored" {
  # Arrange:
  # an unquoted path with a space arrives as two words.
  make_dir 'my' >/dev/null
  make_dir 'my documents' >/dev/null

  # Act
  run --separate-stderr cdl_then_pwd 'my' 'documents'

  # Assert
  assert_failure 10
  assert_output "${HOME}"
  assert_stderr_contains 'cdl: Too many arguments: expected one directory, got 2'
}

# endregion

# region Directory errors

#######################################
# Check that cdl stays put, names why it cannot enter a target,
# and returns the code of that reason.
#
# Arguments:
#   1: Target, relative to HOME.
#   2: The code expected.
#   3: A part of the reason expected.
#######################################
function a_target_cdl_cannot_enter_fails_with_its_reason() {
  local -r target="$1"
  local -ir code="$2"
  local -r reason="$3"

  # Arrange:
  # a file, a broken symlink, a symlink loop,
  # and a directory that may not be entered, with another in it.
  if [[ ${target} == locked* ]] && ((EUID == 0)); then
    skip 'root enters any directory'
  fi
  make_entries "${HOME}" 'notes.md' 'gone -> nowhere' 'loop -> loop'
  make_dir 'locked/inner' >/dev/null
  chmod 000 "${HOME}/locked"

  # Act
  run --separate-stderr cdl_then_pwd "${target}"
  chmod 755 "${HOME}/locked"

  # Assert
  assert_failure "${code}"
  assert_output "${HOME}"
  assert_stderr_contains "${reason}"
}

# Samples: "target|code|a part of the reason", one per row
# of the table above __cdl_diagnose_chdir_failure in cdl.sh.
__UNENTERABLE_TARGETS=(
  "missing|31|cdl: No such file or directory: 'missing'"
  "missing/deeper|31|cdl: No such file or directory: 'missing/deeper'"
  "gone/inner|31|('gone' is a broken symlink)"
  "loop/inner|31|('loop' is a broken symlink)"
  "notes.md/|33|cdl: Not a directory: 'notes.md/'"
  "notes.md/drafts|33|('notes.md' is a file)"
  "locked|32|cdl: Permission denied: 'locked'"
  "locked/inner|32|('locked' may not be entered)"
)

for __sample in "${__UNENTERABLE_TARGETS[@]}"; do
  IFS='|' read -r __target __code __reason <<<"${__sample}"
  bats_test_function \
    --description "'${__target}' fails with code ${__code}: ${__reason#cdl: }" \
    -- a_target_cdl_cannot_enter_fails_with_its_reason "${__target}" "${__code}" "${__reason}"
done

@test "cdl - without a previous directory fails with CDL_ERR_NOT_FOUND" {
  # Arrange: sandbox_setup unsets OLDPWD.
  if [[ ${CDL_SHELL_KIND} == 'zsh' ]]; then
    skip 'zsh keeps its own record of the previous directory'
  fi

  # Act
  run --separate-stderr cdl_then_pwd -

  # Assert
  assert_failure 31
  assert_stderr_contains 'cdl: No previous directory: OLDPWD is not set'
}

#######################################
# Check what cdl - says when OLDPWD names no directory to go back to.
#
# Arguments:
#   1: What OLDPWD names: 'file' or 'gone'.
#   2: The code expected.
#   3: The reason expected, before the quoted path.
#######################################
function cdl_back_to_no_directory_fails_with_its_reason() {
  local -r kind="$1"
  local -ir code="$2"
  local -r reason="$3"

  # Arrange
  if [[ ${CDL_SHELL_KIND} == 'zsh' ]]; then
    skip 'zsh keeps its own record of the previous directory'
  fi
  make_entries "${HOME}" 'file'

  # Act
  run --separate-stderr in_shell \
    'OLDPWD="$1"; cdl - >/dev/null; rc=$?; printf "%s\n" "$PWD"; exit "$rc"' "${HOME}/${kind}"

  # Assert
  assert_failure "${code}"
  assert_output "${HOME}"
  assert_stderr_contains "cdl: ${reason}: '${HOME}/${kind}'"
}

bats_test_function \
  --description 'cdl - to an OLDPWD that names a file fails with CDL_ERR_NOT_DIRECTORY' \
  -- cdl_back_to_no_directory_fails_with_its_reason 'file' 33 'Not a directory'
bats_test_function \
  --description 'cdl - to an OLDPWD that is gone fails with CDL_ERR_NOT_FOUND' \
  -- cdl_back_to_no_directory_fails_with_its_reason 'gone' 31 'No such file or directory'

@test "an unreadable directory is entered, then reported with CDL_ERR_LIST" {
  # Arrange:
  # search permission without read permission:
  # cd works, listing does not.
  if ((EUID == 0)); then
    skip 'root reads any directory'
  fi
  local -r blind="$(make_dir 'blind')"
  chmod 100 "${blind}"

  # Act
  run --separate-stderr cdl_then_pwd "${blind}"
  chmod 755 "${blind}"

  # Assert
  assert_failure 40
  assert_output "${blind}"
}

# endregion

### End
