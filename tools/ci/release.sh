#!/usr/bin/env bash

# Name: tools/ci/release.sh
# Author: Nikita Neverov (BMTLab)
# License: MIT
#
# Description:
#   The steps of a release, one command each,
#   for the release workflow and for a dry run on a laptop:
#     - check TAG: the tag names the version in the header of cdl.sh;
#     - notes VERSION FILE: the CHANGELOG section of the version, into FILE;
#     - assets TAG DIR: cdl.sh, a source tarball and their SHA-256 files;
#     - publish TAG DIR FILE: the GitHub release, through gh;
#     - verify DIR: the signed build provenance of cdl.sh, through gh.
#   Under GitHub Actions, `check` also exports VERSION to the next steps.
#
# Usage:
#   tools/ci/release.sh check v2.0.0
#   tools/ci/release.sh notes 2.0.0 release-notes.md
#   tools/ci/release.sh assets v2.0.0 release-assets
#   GH_TOKEN=... tools/ci/release.sh publish v2.0.0 release-assets release-notes.md
#   GH_TOKEN=... tools/ci/release.sh verify release-assets
#
# Exit Codes:
#   0: Success.
#   20: RELEASE_ERR_USAGE
#      Unknown step, or a missing argument.
#   21: RELEASE_ERR_VERSION
#      The tag does not name the version in cdl.sh.
#   22: RELEASE_ERR_NOTES
#      CHANGELOG.md has no notes for the version.
#   23: RELEASE_ERR_ASSETS
#      An asset could not be built.
#   24: RELEASE_ERR_PUBLISH
#      gh could not publish the release.
#   25: RELEASE_ERR_PROVENANCE
#      The build provenance of cdl.sh does not verify.

set -o errexit -o nounset -o pipefail

readonly RELEASE_ERR_USAGE=20
readonly RELEASE_ERR_VERSION=21
readonly RELEASE_ERR_NOTES=22
readonly RELEASE_ERR_ASSETS=23
readonly RELEASE_ERR_PUBLISH=24
readonly RELEASE_ERR_PROVENANCE=25

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
readonly PROJECT_ROOT

readonly CI_SCRIPT_NAME='Release'
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# region Helpers

#######################################
# Print the version in the header of cdl.sh.
#######################################
function script_version() {
  sed -n 's/^# Version: *//p' "${PROJECT_ROOT}/cdl.sh"
}

#######################################
# Write the SHA-256 file of every asset in a directory.
#
# Arguments:
#   1: Directory of the assets.
#######################################
function write_checksums() {
  local -r directory="$1"
  local asset

  for asset in "${directory}"/*; do
    printf '%s  %s\n' "$(sha256_of "${asset}")" "${asset##*/}" >"${asset}.sha256"
  done
}

# endregion

# region Steps

#######################################
# Check that a tag names the version in cdl.sh.
#
# Arguments:
#   1: Tag, e.g. v2.0.0.
#
# Globals:
#   GITHUB_ENV (read): when set, VERSION is appended to it.
#
# Outputs:
#   The version to stdout.
#
# Returns:
#   0 on a match; RELEASE_ERR_VERSION otherwise.
#######################################
function check_tag() {
  local -r tag="$1"
  local version
  version="$(script_version)"

  if [[ ${tag} != "v${version}" ]]; then
    ci_error "the tag is ${tag}, but cdl.sh says ${version}" \
      "${RELEASE_ERR_VERSION}" || return
  fi

  if [[ -n ${GITHUB_ENV-} ]]; then
    printf 'VERSION=%s\n' "${version}" >>"${GITHUB_ENV}"
  fi
  printf '%s\n' "${version}"
}

#######################################
# Write the release notes of a version.
#
# Arguments:
#   1: Version, e.g. 2.0.0.
#   2: File to write.
#
# Returns:
#   0 on success; RELEASE_ERR_NOTES without notes.
#######################################
function write_notes() {
  local -r version="$1"
  local -r file="$2"

  if ! "${PROJECT_ROOT}/tools/release-notes.sh" "${version}" >"${file}"; then
    ci_error "CHANGELOG.md has no notes for ${version}" \
      "${RELEASE_ERR_NOTES}" || return
  fi
}

#######################################
# Build the release assets and their checksums.
#
# The tarball comes from `git archive`,
# which leaves out the files marked export-ignore.
#
# Arguments:
#   1: Tag, e.g. v2.0.0.
#   2: Directory to build the assets in.
#
# Returns:
#   0 on success; RELEASE_ERR_ASSETS if a step fails.
#######################################
function build_assets() {
  local -r tag="$1"
  local -r directory="$2"

  if ! mkdir -p "${directory}" \
    || ! cp "${PROJECT_ROOT}/cdl.sh" "${directory}/" \
    || ! git -C "${PROJECT_ROOT}" archive --format=tar.gz --prefix="cdl-${tag}/" \
      --output="${directory}/cdl-${tag}.tar.gz" HEAD \
    || ! write_checksums "${directory}"; then
    ci_error "could not build the assets of ${tag}" \
      "${RELEASE_ERR_ASSETS}" || return
  fi

  ls -l "${directory}"
}

#######################################
# Publish the GitHub release of a tag with its assets.
#
# Arguments:
#   1: Tag, e.g. v2.0.0.
#   2: Directory of the assets.
#   3: File with the release notes.
#
# Globals:
#   GH_TOKEN (read by gh).
#
# Returns:
#   0 on success; RELEASE_ERR_PUBLISH if gh fails.
#######################################
function publish_release() {
  local -r tag="$1"
  local -r directory="$2"
  local -r notes="$3"

  if ! gh release create "${tag}" \
    --title "cdl ${tag}" \
    --notes-file "${notes}" \
    --verify-tag \
    --latest \
    "${directory}"/*; then
    ci_error "gh could not publish ${tag}" "${RELEASE_ERR_PUBLISH}" || return
  fi
}

#######################################
# Verify the signed build provenance of the released cdl.sh.
#
# A last check that what users download is what CI built.
#
# Arguments:
#   1: Directory of the assets.
#
# Globals:
#   GH_TOKEN (read by gh), GITHUB_REPOSITORY (read).
#
# Returns:
#   0 on success; RELEASE_ERR_PROVENANCE otherwise.
#######################################
function verify_provenance() {
  local -r directory="$1"

  if ! gh attestation verify "${directory}/cdl.sh" \
    --repo "${GITHUB_REPOSITORY:-BMTLab/cdl}" >/dev/null; then
    ci_error 'the build provenance of cdl.sh does not verify' \
      "${RELEASE_ERR_PROVENANCE}" || return
  fi
}

# endregion

# region Entry point

#######################################
# Check the number of arguments a step got.
#
# Arguments:
#   1: Step.
#   2: Expected count.
#   3: Actual count.
#
# Returns:
#   0 on a match; RELEASE_ERR_USAGE otherwise.
#######################################
function require_arguments() {
  local -r step="$1"
  local -ir expected="$2"
  local -ir actual="$3"

  if ((actual != expected)); then
    ci_error "${step} takes ${expected} argument(s), got ${actual}" \
      "${RELEASE_ERR_USAGE}" || return
  fi
}

#######################################
# Run one step of the release.
#
# Arguments:
#   1: Step: check, notes, assets, publish or verify.
#   $@: The arguments of the step, see the usage.
#######################################
function main() {
  local -r step="${1-}"
  if (($# > 0)); then
    shift
  fi

  case ${step} in
    check)
      require_arguments "${step}" 1 "$#"
      check_tag "$@"
      ;;
    notes)
      require_arguments "${step}" 2 "$#"
      write_notes "$@"
      ;;
    assets)
      require_arguments "${step}" 2 "$#"
      build_assets "$@"
      ;;
    publish)
      require_arguments "${step}" 3 "$#"
      publish_release "$@"
      ;;
    verify)
      require_arguments "${step}" 1 "$#"
      verify_provenance "$@"
      ;;
    *)
      ci_error "unknown step '${step}': use check, notes, assets, publish or verify" \
        "${RELEASE_ERR_USAGE}"
      ;;
  esac
}

# endregion

main "$@"

### End
