#!/usr/bin/env bash

# Name: tools/bench.sh
# Author: Nikita Neverov (BMTLab)
# License: MIT
#
# Description:
#   Measure what one cdl call costs, next to a plain `cd` and `ls`,
#   in every shell given.
#   Each shell runs all its calls in one process,
#   so the numbers show cdl itself and not shell start-up.
#   Output goes to /dev/null: the cost of the terminal is left out.
#
# Usage:
#   tools/bench.sh [-n CALLS] [-d DIRECTORY] [SHELL ...]
#
#   The shells must provide EPOCHREALTIME: bash 5 or later, or zsh;
#   the bash 3.2 of macOS cannot be measured this way.
#
#   tools/bench.sh                   # 200 calls in /usr/bin, bash and zsh
#   tools/bench.sh -n 500 -d ~ bash  # 500 calls in ~, bash only
#
# Exit Codes:
#   0: Success.
#   40: BENCH_ERR_USAGE
#      Unknown option or missing value.
#   41: BENCH_ERR_SHELL
#      A shell to measure is not installed.
#   42: BENCH_ERR_CLOCK
#      A shell to measure has no EPOCHREALTIME clock.
#   49: BENCH_ERR_INTERNAL
#      A bug: a command failed where no code planned it.

readonly BENCH_ERR_USAGE=40
readonly BENCH_ERR_SHELL=41
readonly BENCH_ERR_CLOCK=42
readonly BENCH_ERR_INTERNAL=49

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly PROJECT_ROOT

# region Errors

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
  if ((${#FUNCNAME[@]} == 2 || $1 == 141 || $1 / 10 == BENCH_ERR_INTERNAL / 10)); then
    exit "$1"
  fi

  printf 'bench: internal error at line %s (status %s): %s\n' \
    "$2" "$1" "$3" >&2

  exit "${BENCH_ERR_INTERNAL}"
}

# endregion Errors

# region Measurement

#######################################
# Print the milliseconds per call of a command, run in a loop.
#
# Arguments:
#   1: Shell to run the loop in.
#   2: Number of calls.
#   3: Directory to list.
#   4: The command to time, as shell code.
#
# Outputs:
#   Milliseconds per call, with two decimals, to stdout.
#######################################
function time_per_call() {
  local -r shell="$1"
  local -r calls="$2"
  local -r directory="$3"
  local -r command="$4"

  # EPOCHREALTIME: bash 5+ built in, zsh from zsh/datetime.
  # shellcheck disable=SC2016 # expanded by the shell being measured
  "${shell}" -c '
    zmodload zsh/datetime 2>/dev/null
    COLUMNS="${COLUMNS:-120}"
    source "$1" || exit
    function baseline() { builtin cd -- "$1" && command ls -Al; }
    start="${EPOCHREALTIME}"
    calls_done=0
    while ((calls_done < $2)); do
      '"${command}"' "$3" >/dev/null 2>&1
      calls_done=$((calls_done + 1))
    done
    end="${EPOCHREALTIME}"
    awk -v start="${start}" -v end="${end}" -v calls="$2" \
      "BEGIN { printf \"%.2f\n\", (end - start) * 1000 / calls }"
  ' bench "${PROJECT_ROOT}/cdl.sh" "${calls}" "${directory}"
}

#######################################
# Print one result row for a shell.
#
# Arguments:
#   1: Shell.
#   2: Number of calls.
#   3: Directory to list.
#######################################
function measure_shell() {
  local -r shell="$1"
  local -r calls="$2"
  local -r directory="$3"
  local cdl_ms baseline_ms

  cdl_ms="$(time_per_call "${shell}" "${calls}" "${directory}" 'cdl')"
  baseline_ms="$(time_per_call "${shell}" "${calls}" "${directory}" 'baseline')"

  printf '  %-6s  cdl %7s ms   cd + ls -Al %7s ms\n' \
    "${shell}" "${cdl_ms}" "${baseline_ms}"
}

#######################################
# Report whether a shell offers the EPOCHREALTIME clock.
#
# Arguments:
#   1: Shell.
#######################################
function has_clock() {
  local -r shell="$1"

  # shellcheck disable=SC2016 # expanded by the shell being checked
  "${shell}" -c 'zmodload zsh/datetime 2>/dev/null; [[ -n "${EPOCHREALTIME-}" ]]'
}

# endregion Measurement

# region Entry point

#######################################
# Print the usage.
#######################################
function usage() {
  sed -n '/^# Usage:/,/^# Exit Codes:/{/^# Exit Codes:/d; s/^# \{0,1\}//; p;}' \
    "${BASH_SOURCE[0]}"
}

#######################################
# Parse the options and measure every shell.
#
# Arguments:
#   $@: Options and shells, see the usage.
#######################################
function main() {
  local calls=200
  local directory='/usr/bin'
  local -a shells
  local shell

  while (($# > 0)); do
    case "$1" in
      -n)
        # The number reaches arithmetic in the shell it times.
        if [[ ! "${2-}" =~ ^[1-9][0-9]*$ ]]; then
          printf 'bench: -n needs a number of calls, not: %s\n' "${2-}" >&2
          return "${BENCH_ERR_USAGE}"
        fi
        calls="$2"
        shift 2
        ;;
      -d)
        if [[ -z "${2-}" ]]; then
          printf 'bench: -d needs a directory\n' >&2
          return "${BENCH_ERR_USAGE}"
        fi
        directory="$2"
        shift 2
        ;;
      -h | --help)
        usage
        return 0
        ;;
      -*)
        printf 'bench: unknown option: %s\n' "$1" >&2
        return "${BENCH_ERR_USAGE}"
        ;;
      *) break ;;
    esac
  done

  shells=("$@")
  if ((${#shells[@]} == 0)); then
    shells=(bash zsh)
  fi

  printf '\n  %s calls in %s, output to /dev/null\n\n' "${calls}" "${directory}"

  for shell in "${shells[@]}"; do
    if ! command -v "${shell}" >/dev/null; then
      printf 'bench: shell not found: %s\n' "${shell}" >&2
      return "${BENCH_ERR_SHELL}"
    fi
    if ! has_clock "${shell}"; then
      printf 'bench: %s has no EPOCHREALTIME (bash 5+ or zsh)\n' "${shell}" >&2
      return "${BENCH_ERR_CLOCK}"
    fi

    measure_shell "${shell}" "${calls}" "${directory}"
  done
  printf '\n'
}

# endregion Entry point

# region Execution guard

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

# endregion Execution guard

### End
