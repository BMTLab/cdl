#!/usr/bin/env bash

# Name: tests/support/fixtures.bash
# Author: Nikita Neverov (BMTLab)
# License: MIT
#
# Description:
#   Test data:
#     - real directory trees for end-to-end tests,
#       described in a tiny syntax and stamped with one fixed time;
#     - canned `ls -l` lines and the rows cdl prints for them,
#       for testing the formatter in isolation.
#
#   Loaded by tests/support/test_helper.bash.

# region Fixed time

# Every fixture carries this modification time,
# so listings are the same on every run and every machine.
# shellcheck disable=SC2034 # used by the tests
FIXTURE_STAMP='202601020304'
FIXTURE_DATE='2026-01-02 03:04'

# endregion

# region Directory trees

#######################################
# Create a directory under HOME and print its path.
#
# Arguments:
#   1: Path relative to HOME; missing parents are created.
#
# Outputs:
#   The absolute path to stdout.
#######################################
function make_dir() {
  local -r dir="${HOME}/$1"

  mkdir -p -- "${dir}"
  printf '%s\n' "${dir}"
}

#######################################
# Fill a directory with entries described in a tiny syntax.
#
# Entry specs:
#   'name/'           a directory;
#   'name'            an empty file;
#   'name*'           an empty executable file;
#   'name -> target'  a symbolic link to target.
#
# Arguments:
#   1: Directory to fill.
#   $@: Entry specs.
#######################################
function make_entries() {
  local -r dir="$1"
  shift

  local spec
  for spec in "$@"; do
    case ${spec} in
      *' -> '*) ln -s -- "${spec#* -> }" "${dir}/${spec%% -> *}" ;;
      */) mkdir -p -- "${dir}/${spec%/}" ;;
      *'*') __fixtures_make_executable "${dir}/${spec%'*'}" ;;
      *) : >"${dir}/${spec}" ;;
    esac
  done

  __fixtures_stamp "${dir}"
}

#######################################
# Create an empty executable file.
#
# Arguments:
#   1: File path.
#######################################
function __fixtures_make_executable() {
  local -r file="$1"

  : >"${file}"
  chmod +x "${file}"
}

#######################################
# Give every entry of a directory the fixed modification time.
#
# Arguments:
#   1: Directory.
#######################################
function __fixtures_stamp() {
  local -r dir="$1"
  local entry

  for entry in "${dir}"/* "${dir}"/.[!.]*; do
    if [[ -e ${entry} || -L ${entry} ]]; then
      touch -h -t "${FIXTURE_STAMP}" -- "${entry}"
    fi
  done
}

# endregion

# region Canned ls -l lines

#######################################
# Print one `ls -l` line in the shape cdl asks ls for:
# sizes in bytes, which the formatter writes like `ls -h`.
#
# Arguments:
#   1: Mode ('drwxr-xr-x', '-rw-r--r--', 'crw-rw-rw-', ...).
#   2: Size field in bytes ('4096', '12'), or '1, 3' for a device.
#   3: Name field (may carry escapes and ' -> target').
#
# Outputs:
#   The line to stdout.
#######################################
function ls_line() {
  local -r mode="$1"
  local -r size="$2"
  local -r name="$3"

  printf '%s 1 user group %s %s %s\n' "${mode}" "${size}" "${FIXTURE_DATE}" "${name}"
}

#######################################
# Print the `ls -l` line of a directory.
#
# Arguments:
#   1: Name field.
#######################################
function ls_dir() {
  ls_line 'drwxr-xr-x' 4096 "$1"
}

#######################################
# Print the `ls -l` line of a regular file.
#
# Arguments:
#   1: Name field.
#   2: Size in bytes (optional; default: 12).
#######################################
function ls_file() {
  ls_line '-rw-r--r--' "${2:-12}" "$1"
}

#######################################
# Print the row the compact listing shows for an entry.
#
# Arguments:
#   1: Size as the listing writes it ('4.0K', '12', '1, 3').
#   2: Name field.
#
# Outputs:
#   The row to stdout, without a newline.
#######################################
function listing_row() {
  local -r size="$1"
  local -r name="$2"

  printf '%8s  %s  %s' "${size}" "${FIXTURE_DATE}" "${name}"
}

#######################################
# Print the row the compact listing shows for a marked entry:
# the mark takes the place of the space before the name.
#
# Arguments:
#   1: Size as the listing writes it.
#   2: Name field.
#
# Outputs:
#   The row to stdout, without a newline.
#######################################
function marked_row() {
  local -r size="$1"
  local -r name="$2"

  printf '%8s  %s ❯%s' "${size}" "${FIXTURE_DATE}" "${name}"
}

#######################################
# Wrap text in a hyperlink (OSC 8), as cdl writes them.
#
# Arguments:
#   1: URI.
#   2: Text.
#######################################
function hyperlink() {
  local -r start=$'\033]8;;'
  local -r end=$'\033\\'

  printf '%s%s%s%s%s%s' "${start}" "$1" "${end}" "$2" "${start}" "${end}"
}

#######################################
# Wrap text in an SGR color, as `ls --color` does.
#
# Arguments:
#   1: SGR parameters ('01;34' for bold blue).
#   2: Text.
#######################################
function paint() {
  printf '\033[%sm%s\033[0m' "$1" "$2"
}

# endregion

### End
