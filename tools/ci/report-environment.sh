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

set -o errexit -o nounset -o pipefail

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
  report="$(
    printf '| Tool | Version |\n|------|---------|\n'
    row 'OS' "$(uname -sr)"
    local shell
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
  if [[ -n ${GITHUB_STEP_SUMMARY-} ]]; then
    printf '### Environment\n\n%s\n\n' "${report}" >>"${GITHUB_STEP_SUMMARY}"
  fi
}

main "$@"

### End
