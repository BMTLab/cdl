#!/usr/bin/env bash

# Name: tools/release-notes.sh
# Author: Nikita Neverov (BMTLab)
# License: MIT
#
# Description:
#   Print the CHANGELOG section of a version, without its heading:
#   the body of the GitHub release for that version.
#   The CHANGELOG stays the one place where release notes are written.
#
# Usage:
#   tools/release-notes.sh [VERSION]
#
#   tools/release-notes.sh          # the version in the header of cdl.sh
#   tools/release-notes.sh 2.0.0
#
# Exit Codes:
#   0: Success.
#   30: NOTES_ERR_MISSING
#      CHANGELOG.md has no section, or an empty one, for the version.

set -o errexit -o nounset -o pipefail

readonly NOTES_ERR_MISSING=30

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly PROJECT_ROOT

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
  if [[ -z ${version} ]]; then
    version="$(sed -n 's/^# Version: *//p' "${PROJECT_ROOT}/cdl.sh")"
  fi

  if ! section_of "${version}"; then
    printf 'release-notes: no notes for %s in CHANGELOG.md\n' "${version}" >&2
    return "${NOTES_ERR_MISSING}"
  fi
}

main "$@"

### End
