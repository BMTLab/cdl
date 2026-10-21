#!/usr/bin/env bash

# Print the CHANGELOG section of a version, without its heading.
#
# Usage: tools/release-notes.sh [VERSION]
#   tools/release-notes.sh          # the version in the header of cdl.sh
#   tools/release-notes.sh 2.0.0
# Effects: none; it reads CHANGELOG.md, and cdl.sh without a VERSION.
# Dependencies: awk, sed.
# Exit codes: 0 success,
#   30 NOTES_ERR_MISSING: CHANGELOG.md has no section, or an empty one,
#     for the version,
#   39 NOTES_ERR_INTERNAL: a bug in this script.
# See: CLAUDE.md, tests/style/test_release.bats.
#
# How it works:
#   The section is the body of the GitHub release of the version,
#   so the CHANGELOG stays the one place where release notes are written.
#
# Version: 1.0.0

readonly NOTES_ERR_MISSING=30
readonly NOTES_ERR_INTERNAL=39

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly PROJECT_ROOT

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
  if ((${#FUNCNAME[@]} == 2 || $1 == 141 || $1 / 10 == NOTES_ERR_INTERNAL / 10)); then
    exit "$1"
  fi

  printf 'release-notes: internal error at line %s (status %s): %s\n' \
    "$2" "$1" "$3" >&2

  exit "${NOTES_ERR_INTERNAL}"
}

#######################################
# Print the section body of a version, trimmed of blank edges.
#
# Arguments:
#   1: Version, e.g. 2.0.0.
#
# Outputs:
#   The section body to stdout.
#
# Returns:
#   0 on success; NOTES_ERR_MISSING if there is nothing to print.
#######################################
function section_of() {
  local -r version="$1"

  awk -v heading="## [${version}]" '
    index($0, heading) == 1 { inside = 1; next }
    inside && (/^## \[/ || /^\[[^]]*\]: /) { exit }
    inside { lines[++count] = $0 }
    END {
      first = 1
      while (first <= count && lines[first] == "") first++
      last = count
      while (last >= first && lines[last] == "") last--
      for (i = first; i <= last; i++) print lines[i]
      exit last < first
    }
  ' "${PROJECT_ROOT}/CHANGELOG.md"
}

#######################################
# Entry point.
#
# Arguments:
#   1: Version (optional; default: the one in cdl.sh).
#######################################
function main() {
  local version="${1-}"
  if [[ -z "${version}" ]]; then
    version="$(sed -n 's/^# Version: *//p' "${PROJECT_ROOT}/cdl.sh")"
  fi

  if ! section_of "${version}"; then
    printf 'release-notes: no notes for %s in CHANGELOG.md\n' "${version}" >&2
    return "${NOTES_ERR_MISSING}"
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
