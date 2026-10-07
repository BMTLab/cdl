#!/usr/bin/env bash

# Name: tests/support/fakes.bash
# Author: Nikita Neverov (BMTLab)
# License: MIT
#
# Description:
#   Stand-ins for the external tools cdl runs: ls, gls and awk.
#   Each one lands in FAKE_BIN, which sandbox_setup puts first on PATH,
#   so a test can reproduce another system (BSD ls, Homebrew gls)
#   or another awk without touching the machine.
#
#   Loaded by tests/support/test_helper.bash.

# region Real tools

#######################################
# Find an ls that understands the GNU options cdl relies on.
#
# Ubuntu 26.04 ships uutils as `ls` and GNU ls as `gnuls`;
# Homebrew coreutils installs GNU ls as `gls`.
#
# Outputs:
#   The path of the first such ls to stdout.
#
# Returns:
#   0 if one was found; 1 otherwise.
#######################################
function gnu_compatible_ls() {
  local candidate path

  for candidate in gnuls gls ls; do
    path="$(PATH="${PATH#"${FAKE_BIN}":}" command -v "${candidate}")" || continue
    if "${path}" --group-directories-first --version >/dev/null 2>&1; then
      printf '%s\n' "${path}"
      return 0
    fi
  done

  return 1
}

#######################################
# Find GNU ls itself, the reference for sizes.
#
# uutils ls speaks the GNU options but rounds some sizes its own way,
# so it does not count here.
#
# Outputs:
#   The path of GNU ls to stdout.
#
# Returns:
#   0 if one was found; 1 otherwise.
#######################################
function gnu_ls() {
  local candidate path

  for candidate in gnuls gls ls; do
    path="$(PATH="${PATH#"${FAKE_BIN}":}" command -v "${candidate}")" || continue
    if "${path}" --version 2>/dev/null | grep -q 'GNU coreutils'; then
      printf '%s\n' "${path}"
      return 0
    fi
  done

  return 1
}

#######################################
# List the awk implementations this machine can run.
#
# 'awk' is the system default (BSD awk on macOS);
# 'gawk-utf8' is gawk in a UTF-8 locale, which counts characters
# instead of bytes, like the UTF-8 aware awks do.
#
# Outputs:
#   One implementation name per line, for use_awk.
#######################################
function available_awks() {
  local name

  printf 'awk\n'
  for name in gawk mawk original-awk; do
    if command -v "${name}" >/dev/null; then
      printf '%s\n' "${name}"
    fi
  done
  if command -v busybox >/dev/null && busybox awk 'BEGIN {}' 2>/dev/null; then
    printf 'busybox-awk\n'
  fi
  if command -v gawk >/dev/null && [[ ${SANDBOX_UTF8_LOCALE} != 'C' ]]; then
    printf 'gawk-utf8\n'
  fi
}

# endregion

# region Fakes

#######################################
# Make the formatter of cdl run the given awk implementation.
#
# cdl prefers mawk when it is installed,
# so the stand-in answers to both `awk` and `mawk`.
#
# Arguments:
#   1: A name printed by available_awks.
#######################################
function use_awk() {
  local -r name="$1"
  local command

  case ${name} in
    busybox-awk) command='exec busybox awk "$@"' ;;
    gawk-utf8) command="LC_ALL='${SANDBOX_UTF8_LOCALE}' exec gawk \"\$@\"" ;;
    *)
      local real_awk
      real_awk="$(PATH="${PATH#"${FAKE_BIN}":}" command -v "${name}")"
      command="exec '${real_awk}' \"\$@\""
      ;;
  esac

  __fakes_install awk "${command}"
  __fakes_install mawk "${command}"
}

#######################################
# Replace ls with a fake BSD ls, and hide any gls.
#
# Like the real one, the fake rejects GNU long options.
# Its listing is a fixed text naming its arguments,
# so a test can tell whether cdl passed it through untouched.
#
# Arguments:
#   1: 'with-color' to accept -G, like macOS and FreeBSD;
#      'without-color' to reject it, like OpenBSD and NetBSD.
#   2: Exit status of a listing (optional; default: 0).
#
# Globals:
#   PATH (write): FAKE_BIN, /usr/bin and /bin only,
#   so a Homebrew gls cannot take precedence over the fake.
#######################################
function fake_bsd_ls() {
  local -r colors="$1"
  local -ir listing_status="${2:-0}"
  local accepts_g='yes'
  if [[ ${colors} == 'without-color' ]]; then
    accepts_g='no'
  fi

  __fakes_install ls "
for arg in \"\$@\"; do
  case \$arg in
    --*) echo \"ls: unrecognized option: \$arg\" >&2; exit 2 ;;
    -*G*) [ '${accepts_g}' = 'yes' ] || { echo 'ls: unknown option -- G' >&2; exit 1; } ;;
  esac
done
echo \"bsd-ls \$*\"
exit ${listing_status}"

  export PATH="${FAKE_BIN}:/usr/bin:/bin"
  if command -v gls >/dev/null; then
    skip 'a gls in /usr/bin would take precedence over the fake BSD ls'
  fi
}

#######################################
# Put a recording gls in front of PATH.
#
# It logs each call, then runs a real GNU-compatible ls,
# so the listing stays genuine.
#
# Globals:
#   GLS_LOG (write): the file that collects the calls.
#######################################
function fake_recording_gls() {
  local real_ls
  real_ls="$(gnu_compatible_ls)" || skip 'no GNU-compatible ls here'

  GLS_LOG="${BATS_TEST_TMPDIR}/gls.log"
  __fakes_install gls "echo \"\$*\" >>'${GLS_LOG}'
exec '${real_ls}' \"\$@\""
}

#######################################
# Put an ls in front of PATH that counts the GNU-option probes.
#
# It records each call carrying --version, then runs a real ls.
# It stands in for gls as well,
# so it is counted whichever of the two cdl picks.
#
# Globals:
#   LS_PROBE_LOG (write): the file that collects the probes.
#######################################
function fake_probe_counting_ls() {
  local real_ls
  real_ls="$(gnu_compatible_ls)" || skip 'no GNU-compatible ls here'

  LS_PROBE_LOG="${BATS_TEST_TMPDIR}/ls-probes.log"
  : >"${LS_PROBE_LOG}"

  local -r body="case \" \$* \" in
  *' --version '*) echo probe >>'${LS_PROBE_LOG}' ;;
esac
exec '${real_ls}' \"\$@\""
  __fakes_install ls "${body}"
  __fakes_install gls "${body}"
}

#######################################
# Log every run of the external tools cdl may start.
#
# Each of ls, gls, awk, mawk, gawk and tput that exists on PATH
# gets a stand-in that writes its name to a log, then runs the real one;
# missing tools stay missing, so cdl picks what it would pick anyway.
# git and hostname, which cdl must never start,
# get stand-ins that only log, so a run would show
# even on a machine without them.
#
# Globals:
#   TOOL_LOG (write): the file that collects one name per run.
#######################################
function fake_logging_tools() {
  TOOL_LOG="${BATS_TEST_TMPDIR}/tools.log"
  : >"${TOOL_LOG}"

  local name real_path
  for name in ls gls awk mawk gawk tput; do
    real_path="$(PATH="${PATH#"${FAKE_BIN}":}" command -v "${name}")" || continue
    __fakes_install "${name}" "echo '${name}' >>'${TOOL_LOG}'
exec '${real_path}' \"\$@\""
  done

  for name in git hostname; do
    __fakes_install "${name}" "echo '${name}' >>'${TOOL_LOG}'
exit 1"
  done
}

#######################################
# Count the runs logged by fake_logging_tools.
#
# Arguments:
#   $@: Tool names to count together, e.g. awk mawk gawk.
#
# Outputs:
#   The number of runs to stdout.
#######################################
function logged_runs() {
  local -i runs=0
  local name

  for name in "$@"; do
    runs+=$(grep -cx "${name}" "${TOOL_LOG}" || true)
  done

  printf '%d\n' "${runs}"
}

#######################################
# Write an executable stand-in into FAKE_BIN.
#
# Arguments:
#   1: Command name.
#   2: Script body, run by /bin/sh.
#######################################
function __fakes_install() {
  local -r name="$1"
  local -r body="$2"

  printf '#!/bin/sh\n%s\n' "${body}" >"${FAKE_BIN}/${name}"
  chmod +x -- "${FAKE_BIN}/${name}"
}

# endregion

### End
