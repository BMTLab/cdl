#!/usr/bin/env bash

# Give the scripts of tools/ci their shared helpers: ci_error and sha256_of.
#
# Usage: sourced by the scripts of tools/ci,
#   after they set CI_SCRIPT_NAME, the title of their error annotations:
#   readonly CI_SCRIPT_NAME='release'
#   source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
# Effects: none; it defines functions, and CI_SCRIPT_NAME when it is unset.
# Dependencies: sha256sum, or shasum on macOS.
# See: .claude/rules/ci.md.
#
# Version: 1.0.0

# The title of the error annotations, unless the sourcing script set one.
: "${CI_SCRIPT_NAME:=ci}"

# region Helpers

#######################################
# Print an error, as a GitHub annotation, and return a code.
#
# The annotation shows on the run page under GitHub Actions
# and reads as a plain message anywhere else.
#
# Arguments:
#   1: Message.
#   2: Return code.
#
# Globals:
#   CI_SCRIPT_NAME (read).
#
# Outputs:
#   The annotation to stderr.
#######################################
function ci_error() {
  local -r message="$1"
  local -ir code="$2"

  printf '::error title=%s::%s\n' "${CI_SCRIPT_NAME}" "${message}" >&2

  return "${code}"
}

#######################################
# Print the SHA-256 digest of a file in hex.
#
# Linux ships sha256sum, macOS ships shasum.
#
# Arguments:
#   1: File.
#
# Outputs:
#   The digest to stdout.
#######################################
function sha256_of() {
  local -r file="$1"
  local line

  if command -v sha256sum >/dev/null; then
    line="$(sha256sum "${file}")"
  else
    line="$(shasum -a 256 "${file}")"
  fi

  printf '%s\n' "${line%% *}"
}

# endregion Helpers

### End
