#!/usr/bin/env bash

# Name: tools/ci/report-environment.sh
# Author: Nikita Neverov (BMTLab)
# License: MIT
#
# Description:
#   Report the tools a CI job runs cdl with:
#   the shells under test, the ls and awk it will pick, and the test tools.
#   A failure in one matrix leg reads differently
#   once you know it ran uutils ls with mawk under bash 3.2.
#
#   The report is a Markdown table on stdout,
#   and the run summary when GITHUB_STEP_SUMMARY is set.
#
# Usage:
#   tools/ci/report-environment.sh [SHELL...]
#
#   tools/ci/report-environment.sh bash zsh
#   tools/ci/report-environment.sh /bin/bash zsh
#
# Exit Codes:
#   0: Success.
#   99: REPORT_ENVIRONMENT_ERR_INTERNAL
#      A bug: a command failed where no code planned it.

readonly REPORT_ENVIRONMENT_ERR_INTERNAL=99

#######################################
# End a run that failed where no code planned it: the ERR trap calls it.
# It passes on unchanged a code that main returns, the 141 of a closed pipe,
# and every code of the block of this tool, which a helper has reported.
#
# Arguments:
#   1: The status of the failed command.
#   2: Its line.
#   3: The command.
#######################################
function __internal_error() {
  # In the guard, FUNCNAME holds only this function and the top level:
  # the command that failed there is main, which returned its code.
  if ((${#FUNCNAME[@]} == 2 || $1 == 141 || $1 / 10 == REPORT_ENVIRONMENT_ERR_INTERNAL / 10)); then
    exit "$1"
  fi

  printf 'report-environment: internal error at line %s (status %s): %s\n' \
    "$2" "$1" "$3" >&2

  exit "${REPORT_ENVIRONMENT_ERR_INTERNAL}"
}

#######################################
# Print the first line of a command's version, or a dash.
#
# Arguments:
#   $@: The command and its version option.
#######################################
function version_of() {
  local line
  line="$("$@" 2>&1 | head -n 1)" || true
  printf '%s\n' "${line:--}"
}

#######################################
# Print the ls that cdl picks: gls before ls.
#######################################
function ls_in_use() {
  if command -v gls >/dev/null; then
    printf 'gls: %s\n' "$(version_of gls --version)"
  elif ls --version >/dev/null 2>&1; then
    version_of ls --version
  else
    printf 'BSD ls\n'
  fi
}

#######################################
# Print the awk that cdl picks: mawk before awk.
#######################################
function awk_in_use() {
  if command -v mawk >/dev/null; then
    printf 'mawk: %s\n' "$(version_of mawk -W version)"
  else
    version_of awk --version
  fi
}

#######################################
# Print one table row.
#
# Arguments:
#   1: Name.
#   2: Value.
#######################################
function row() {
  # shellcheck disable=SC2016 # Markdown backticks, not a command
  printf '| %s | `%s` |\n' "$1" "$2"
}

#######################################
# Entry point: print the report, and append it to the run summary.
#
# Arguments:
#   $@: Shells under test.
#
# Globals:
#   GITHUB_STEP_SUMMARY (read).
#######################################
function main() {
  local report
  local shell

  report="$(
    printf '| Tool | Version |\n|------|---------|\n'
    row 'OS' "$(uname -sr)"
    for shell in "$@"; do
      row "${shell}" "$(version_of "${shell}" --version)"
    done
    row 'ls' "$(ls_in_use)"
    row 'awk' "$(awk_in_use)"
    row 'bats' "$(version_of bats --version)"
    row 'bash of bats' "$(version_of bash --version)"
    row 'python3' "$(version_of python3 --version)"
  )"

  printf '%s\n' "${report}"
  if [[ -n "${GITHUB_STEP_SUMMARY-}" ]]; then
    printf '### Environment\n\n%s\n\n' "${report}" >>"${GITHUB_STEP_SUMMARY}"
  fi
}

# Tests may source this file for its functions; run as a program, it runs main.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -o errexit -o nounset -o pipefail -o errtrace
  # The bash 3.2 of macOS has no inherit_errexit,
  # and install-tools.sh runs on it before Homebrew brings another.
  shopt -s inherit_errexit 2>/dev/null || true
  trap '__internal_error "$?" "${LINENO}" "${BASH_COMMAND}"' ERR
  trap 'exit 130' INT
  trap 'exit 143' TERM

  main "$@"
fi

### End
