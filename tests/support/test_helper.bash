#!/usr/bin/env bash

# Name: tests/support/test_helper.bash
# Author: Nikita Neverov (BMTLab)
# License: MIT
#
# Description:
#   The one file every test loads:
#     load '../support/test_helper'
#
#   It resolves the project paths and the shell under test,
#   then loads the focused helper modules:
#     - sandbox.bash:     a hermetic environment for each test;
#     - shells.bash:      run cdl inside the shell under test;
#     - assertions.bash:  assertions that explain their failures;
#     - fixtures.bash:    directory trees and canned `ls -l` lines;
#     - screen.bash:      strip escapes, count screen cells, find columns;
#     - fakes.bash:       stand-in ls, gls and awk binaries on PATH.
#
#   The shell under test comes from CDL_TEST_SHELL:
#   'bash' (the default), 'zsh',
#   or a path such as /bin/bash to test the bash 3.2 of macOS.

# shellcheck disable=SC2034 # used by the modules and the tests
CDL_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd -P)"
CDL_SCRIPT="${CDL_ROOT}/cdl.sh"
export CDL_SCRIPT

CDL_SHELL_PATH="$(command -v "${CDL_TEST_SHELL:-bash}")" || {
  printf 'Shell under test not found: %s\n' "${CDL_TEST_SHELL:-bash}" >&2
  exit 1
}
case ${CDL_SHELL_PATH##*/} in
  zsh*) CDL_SHELL_KIND='zsh' ;;
  *) CDL_SHELL_KIND='bash' ;;
esac

__CDL_SUPPORT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# shellcheck source=sandbox.bash
source "${__CDL_SUPPORT_DIR}/sandbox.bash"
# shellcheck source=shells.bash
source "${__CDL_SUPPORT_DIR}/shells.bash"
# shellcheck source=assertions.bash
source "${__CDL_SUPPORT_DIR}/assertions.bash"
# shellcheck source=fixtures.bash
source "${__CDL_SUPPORT_DIR}/fixtures.bash"
# shellcheck source=screen.bash
source "${__CDL_SUPPORT_DIR}/screen.bash"
# shellcheck source=fakes.bash
source "${__CDL_SUPPORT_DIR}/fakes.bash"

### End
