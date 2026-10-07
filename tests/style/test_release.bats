#!/usr/bin/env bats

# Name: tests/style/test_release.bats
# Author: Nikita Neverov (BMTLab)
# License: MIT
#
# Description:
#   A release must be possible from the current tree:
#   the release steps accept the version in cdl.sh,
#   refuse anything else with their documented codes,
#   and find the notes of the version in the CHANGELOG.
#
#   Each test follows the Arrange-Act-Assert pattern.

bats_require_minimum_version 1.11.0

load '../support/test_helper'

function setup() {
  RELEASE="${CDL_ROOT}/tools/ci/release.sh"
  VERSION="$(sed -n 's/^# Version: *//p' "${CDL_SCRIPT}")"
  unset GITHUB_ENV
}

# region Tag check

@test "the release check accepts the tag of the version in cdl.sh" {
  # Arrange: the version comes from the header of cdl.sh.

  # Act
  run --separate-stderr "${RELEASE}" check "v${VERSION}"

  # Assert
  assert_success
  assert_output "${VERSION}"
}

@test "the release check refuses a tag of another version with RELEASE_ERR_VERSION" {
  # Arrange: no fixtures needed.

  # Act
  run --separate-stderr "${RELEASE}" check 'v0.0.0'

  # Assert
  assert_failure 21
  assert_stderr_contains "the tag is v0.0.0, but cdl.sh says ${VERSION}"
}

@test "the release check exports VERSION under GitHub Actions" {
  # Arrange
  export GITHUB_ENV="${BATS_TEST_TMPDIR}/github-env"
  : >"${GITHUB_ENV}"

  # Act
  run --separate-stderr "${RELEASE}" check "v${VERSION}"

  # Assert
  assert_success
  assert_equal "$(<"${GITHUB_ENV}")" "VERSION=${VERSION}" 'GITHUB_ENV'
}

# endregion

# region Notes

@test "the release notes of the version in cdl.sh come from its CHANGELOG section" {
  # Arrange
  local -r notes="${BATS_TEST_TMPDIR}/notes.md"

  # Act
  run --separate-stderr "${RELEASE}" notes "${VERSION}" "${notes}"

  # Assert:
  # the section starts with a subsection, not with its own heading.
  assert_success
  assert_equal "$(head -n 1 "${notes}")" '### Fixed' 'first line of the notes'
}

@test "a version without a CHANGELOG section fails with RELEASE_ERR_NOTES" {
  # Arrange
  local -r notes="${BATS_TEST_TMPDIR}/notes.md"

  # Act
  run --separate-stderr "${RELEASE}" notes '0.0.0' "${notes}"

  # Assert
  assert_failure 22
  assert_stderr_contains 'CHANGELOG.md has no notes for 0.0.0'
}

# endregion

# region Usage

@test "an unknown release step fails with RELEASE_ERR_USAGE" {
  # Arrange: no fixtures needed.

  # Act
  run --separate-stderr "${RELEASE}" deploy

  # Assert
  assert_failure 20
  assert_stderr_contains "unknown step 'deploy'"
}

# endregion

### End
