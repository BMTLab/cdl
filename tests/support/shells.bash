#!/usr/bin/env bash

# Name: tests/support/shells.bash
# Author: Nikita Neverov (BMTLab)
# License: MIT
#
# Description:
#   Run cdl inside the shell under test (bash or zsh),
#   always in a fresh process with no rc files,
#   so every test starts from the same clean shell.
#
#   Snippets run in bash and in zsh alike,
#   so they avoid names that zsh reserves,
#   such as `status`, `path` and `argv`.
#
#   Loaded by tests/support/test_helper.bash.

# region Runners

#######################################
# Run a snippet in the shell under test, with cdl.sh sourced.
#
# The snippet receives the remaining arguments as "$@",
# so paths travel as data and never need quoting inside it.
# stdin is /dev/null:
# cdl must never mistake the runner's stdin for a piped path.
#
# Arguments:
#   1: Snippet to run.
#   $@: Arguments for the snippet.
#
# Outputs:
#   Whatever the snippet prints.
#
# Returns:
#   The snippet's exit status.
#######################################
function in_shell() {
  in_shell_with_stdin "$@" </dev/null
}

#######################################
# Run a snippet like in_shell, but on the caller's stdin.
#
# Arguments:
#   1: Snippet to run.
#   $@: Arguments for the snippet.
#
# Inputs:
#   stdin is passed through to the snippet.
#######################################
function in_shell_with_stdin() {
  local -r snippet="$1"
  shift

  # shellcheck disable=SC2016 # expanded by the shell under test
  in_bare_shell 'source "$CDL_SCRIPT" || exit; '"${snippet}" "$@"
}

#######################################
# Run a snippet in the shell under test, without sourcing cdl.sh.
#
# For tests about sourcing itself.
#
# Arguments:
#   1: Snippet to run.
#   $@: Arguments for the snippet.
#
# Inputs:
#   stdin is passed through to the snippet.
#######################################
function in_bare_shell() {
  local -r snippet="$1"
  shift

  if [[ ${CDL_SHELL_KIND} == 'zsh' ]]; then
    "${CDL_SHELL_PATH}" -f -c "${snippet}" cdl-test "$@"
  else
    "${CDL_SHELL_PATH}" --noprofile --norc -c "${snippet}" cdl-test "$@"
  fi
}

#######################################
# Run a snippet with stdin and stdout on a pseudo-terminal.
#
# cdl colors only terminals, and bats captures output through pipes,
# so color tests need a real pty in between:
# util-linux script on Linux, BSD script on macOS.
# Data reaches the snippet through exported variables,
# because util-linux script takes a single command string.
#
# Arguments:
#   1: Snippet to run (cdl.sh is sourced first).
#
# Outputs:
#   What the snippet printed, with the pty's CR LF turned into LF.
#
# Returns:
#   The snippet's exit status.
#######################################
function in_terminal() {
  local -r snippet="$1"
  local -r script_file="${BATS_TEST_TMPDIR}/terminal-snippet"

  # shellcheck disable=SC2016 # expanded by the shell under test
  printf 'source "$CDL_SCRIPT" || exit\n%s\n' "${snippet}" >"${script_file}"

  local -a command=("${CDL_SHELL_PATH}" --noprofile --norc "${script_file}")
  if [[ ${CDL_SHELL_KIND} == 'zsh' ]]; then
    command=("${CDL_SHELL_PATH}" -f "${script_file}")
  fi

  local transcript rc=0
  if [[ $(uname -s) == 'Darwin' ]]; then
    transcript="$(script -q /dev/null "${command[@]}" </dev/null)" || rc=$?
  else
    # The command string goes through sh, so each word is quoted.
    local quoted
    printf -v quoted '%q ' "${command[@]}"
    transcript="$(script -qec "${quoted}" /dev/null </dev/null)" || rc=$?
  fi

  printf '%s\n' "${transcript//$'\r'/}"
  return "${rc}"
}

# endregion

# region Shortcuts

#######################################
# Run cdl, then print the directory the shell ended up in.
#
# The listing is discarded; errors still reach stderr.
#
# Arguments:
#   $@: Arguments for cdl.
#
# Outputs:
#   The final $PWD to stdout.
#
# Returns:
#   cdl's return code.
#######################################
function cdl_then_pwd() {
  in_shell 'cdl "$@" >/dev/null; rc=$?; printf "%s\n" "$PWD"; exit "$rc"' "$@"
}

#######################################
# Lay out canned `ls -l` lines with the formatter of cdl.sh.
#
# Arguments:
#   1: Terminal width in columns.
#   2: Most rows of the grid (optional; default: no limit).
#   3: Most columns of the grid (optional; default: as many as fit).
#   4: 1 to style the header and the notes (optional; default: 0).
#   5: Directory for a header line (optional; default: no header).
#   6: Git branch for the header (optional; default: none).
#   7: Name of the entry to mark (optional; default: none).
#   8: Directory the names link into (optional; default: no links).
#
# Inputs:
#   `ls -l` lines on stdin.
#
# Outputs:
#   The formatted listing to stdout.
#######################################
function format_listing() {
  in_shell_with_stdin '__cdl_format_listing "$@"' "$@"
}

# endregion

### End
