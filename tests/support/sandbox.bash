#!/usr/bin/env bash

# Name: tests/support/sandbox.bash
# Author: Nikita Neverov (BMTLab)
# License: MIT
#
# Description:
#   A hermetic environment for each test.
#   Everything cdl reads from the environment is pinned,
#   so a result never depends on the machine that runs the suite.
#
#   Loaded by tests/support/test_helper.bash.

# region Locale

#######################################
# Find a UTF-8 locale installed on this machine.
#
# Linux ships C.UTF-8, macOS ships en_US.UTF-8;
# the spelling of the suffix varies between libcs.
#
# Outputs:
#   The locale name to stdout, or 'C' if there is none.
#######################################
function __sandbox_find_utf8_locale() {
  local -r installed="$(locale -a 2>/dev/null)"
  local candidate

  for candidate in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do
    if grep -qx "${candidate}" <<<"${installed}"; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  printf 'C\n'
}

# Probed once per test file rather than once per test.
SANDBOX_UTF8_LOCALE="$(__sandbox_find_utf8_locale)"

# endregion

# region Settings

#######################################
# List the settings of cdl: the variables that __cdl_read_settings reads.
#
# Globals:
#   CDL_SCRIPT (read).
#
# Outputs:
#   The names to stdout, one per line.
#######################################
function list_cdl_settings() {
  sed -n 's/^  __cdl_setting_[a-z_]*="\${\(CDL_[A-Z_]*\)[-:].*/\1/p' "${CDL_SCRIPT}"
}

# Read once per test file, as the locale is probed.
SANDBOX_CDL_SETTINGS="$(list_cdl_settings)"

# endregion

# region Setup

#######################################
# Give the test a hermetic environment.
#
# Pins HOME, PATH (with a directory for fakes in front),
# the time zone, the locale, the terminal type and width,
# and the ls colors; unsets everything else cdl reacts to,
# its own settings too, which the shell of the user may export.
# Paths are physical, because macOS links /var to /private/var
# and cd would otherwise report a different spelling.
#
# Globals:
#   HOME, FAKE_BIN, PATH, TZ, LANG, TERM, COLUMNS, LS_COLORS (write);
#   SANDBOX_CDL_SETTINGS (read).
#######################################
function sandbox_setup() {
  local root setting
  root="$(cd "${BATS_TEST_TMPDIR}" && pwd -P)"

  export HOME="${root}/home"
  export FAKE_BIN="${root}/fake-bin"
  mkdir -p "${HOME}" "${FAKE_BIN}"

  export PATH="${FAKE_BIN}:${PATH}"
  export TZ='UTC'
  export LANG="${SANDBOX_UTF8_LOCALE}"
  export TERM='xterm-256color'
  export COLUMNS=120
  export LS_COLORS='di=01;34:ln=01;36:ex=01;32'

  unset LC_ALL LC_CTYPE LC_COLLATE LC_MESSAGES LC_NUMERIC LC_TIME
  unset NO_COLOR CLICOLOR CLICOLOR_FORCE CDPATH OLDPWD LINES

  # The README has the user export CDL_REPLACE_CD=1, for one.
  while IFS= read -r setting; do
    unset "${setting}"
  done <<<"${SANDBOX_CDL_SETTINGS}"

  cd "${HOME}" || return 1
}

# endregion

### End
