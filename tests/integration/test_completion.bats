#!/usr/bin/env bats

# Name: tests/integration/test_completion.bats
# Author: Nikita Neverov (BMTLab)
# License: MIT
#
# Description:
#   What Tab offers after cdl and cdl_list, and after cd when cdl replaces it:
#   the options after a dash; otherwise the directories and files
#   a word begins, as cdl takes both,
#   and the directories under CDPATH, as cd offers them.
#   bash runs the completion function itself;
#   zsh runs on a pseudo-terminal through tests/support/bin/zsh-completions,
#   with compinit, as a user meets it.
#   Each test belongs to one shell and skips in the other.
#
#   Each test follows the Arrange-Act-Assert pattern.

bats_require_minimum_version 1.11.0

load '../support/test_helper'

function setup() {
  sandbox_setup

  WORK_DIR="$(make_dir 'work')"
  make_entries "${WORK_DIR}" 'pictures/' 'projects/' 'My Docs/' 'plain.txt'
  POOL_BASE="$(make_dir 'base')"
  make_entries "${POOL_BASE}" 'pool/'
}

# region Helpers

#######################################
# Skip the test unless the shell under test is of the given kind.
#
# Arguments:
#   1: 'bash' or 'zsh'.
#######################################
function only_in() {
  if [[ ${CDL_SHELL_KIND} != "$1" ]]; then
    skip "a test of the $1 completion"
  fi
}

#######################################
# Print what the bash completion of cdl offers for a word,
# typed in the work directory.
#
# Arguments:
#   1: The word.
#
# Outputs:
#   The candidates, one per line, sorted.
#######################################
function bash_completions() {
  in_shell 'cd "$1" && COMP_WORDS=(cdl "$2") && COMP_CWORD=1 && __cdl_complete_bash \
    && printf "%s\n" ${COMPREPLY[@]+"${COMPREPLY[@]}"}' "${WORK_DIR}" "$1" | LC_ALL=C sort
}

#######################################
# Print what the zsh completion offers for a command line,
# typed in the work directory.
#
# Arguments:
#   $@: [--before-compinit] and the command line.
#
# Outputs:
#   The candidates, one per line, sorted.
#######################################
function zsh_completions() {
  local -a options=()
  if [[ $1 == '--before-compinit' ]]; then
    options=("$1")
    shift
  fi

  CDL_ZSH="${CDL_SHELL_PATH}" "${__CDL_SUPPORT_DIR}/bin/zsh-completions" \
    ${options[@]+"${options[@]}"} "${CDL_SCRIPT}" "${WORK_DIR}" "$1"
}

# endregion

# region bash

@test "bash completes the options of cdl after a dash" {
  # Arrange
  only_in bash

  # Act
  run --separate-stderr bash_completions '-'

  # Assert
  assert_success
  assert_output "$(printf '%s\n' -- --all --help --one-column --version -1 -L -P -V -a -h)"
}

@test "with CDL_REPLACE_CD=1, bash completes cd with the options of cdl" {
  # Arrange
  only_in bash
  export CDL_REPLACE_CD=1

  # Act:
  # Tab runs the function that `complete -p cd` names.
  run --separate-stderr in_shell \
    'spec="$(complete -p cd)" && function_name="${spec##* -F }" \
     && function_name="${function_name%% *}" \
     && COMP_WORDS=(cd -) && COMP_CWORD=1 && "${function_name}" \
     && printf "%s\n" "${COMPREPLY[@]}" | LC_ALL=C sort'

  # Assert
  assert_success
  assert_output "$(printf '%s\n' -- --all --help --one-column --version -1 -L -P -V -a -h)"
}

@test "under ble.sh, with CDL_REPLACE_CD=1, bash still completes cd with the options of cdl" {
  # Arrange
  only_in bash
  export CDL_REPLACE_CD=1

  # Act:
  # the stand-in for ble.sh loads its completion module at the first Tab,
  # with a completion of cd of its own, then runs the hooks queued for it;
  # at Tab, it asks its own completion first, then the one `complete` names.
  run --separate-stderr in_bare_shell \
    'after_complete=()
     function blehook/eval-after-load() { after_complete+=("$2"); }
     source "$CDL_SCRIPT"
     function ble/cmdinfo/complete:cd() { COMPREPLY=(-e -@); }
     for hook in "${after_complete[@]}"; do eval "${hook}"; done
     COMP_WORDS=(cd -) && COMP_CWORD=1
     if declare -F ble/cmdinfo/complete:cd >/dev/null; then
       ble/cmdinfo/complete:cd
     else
       spec="$(complete -p cd)" && function_name="${spec##* -F }"
       "${function_name%% *}"
     fi
     printf "%s\n" "${COMPREPLY[@]}" | LC_ALL=C sort'

  # Assert
  assert_success
  assert_output "$(printf '%s\n' -- --all --help --one-column --version -1 -L -P -V -a -h)"
}

@test "under ble.sh, with CDL_REPLACE_CD=1, cd counts as a command without options of its own" {
  # Arrange
  only_in bash
  export CDL_REPLACE_CD=1

  # Act:
  # the stand-in for ble.sh loads its command specs after cdl.sh,
  # with the one it has for cd, then runs the callbacks queued for them;
  # the last spec of cd is the one ble.sh goes by.
  run --separate-stderr in_bare_shell \
    'after_cmdspec=()
     function ble-import() { if [[ $1 == -C ]]; then after_cmdspec+=("$2"); fi; }
     function ble/cmdspec/opts() { cd_spec="$1"; }
     source "$CDL_SCRIPT"
     ble/cmdspec/opts "mandb-help=%help cd" cd
     for callback in "${after_cmdspec[@]}"; do eval "${callback}"; done
     printf "%s\n" "${cd_spec}"'

  # Assert
  assert_success
  assert_output '+no-options'
}

@test "bash offers the options of cdl as words, not as file names" {
  # Arrange
  only_in bash
  if (($(in_shell 'printf "%s" "${BASH_VERSINFO[0]}"') < 4)); then
    skip 'compopt came with bash 4'
  fi

  # Act:
  # compopt stands in for the builtin, which works only inside completion.
  run --separate-stderr in_shell \
    'function compopt() { printf "compopt %s\n" "$*"; }
     cd "$1" && COMP_WORDS=(cdl -) && COMP_CWORD=1 && __cdl_complete_bash' "${WORK_DIR}"

  # Assert
  assert_success
  assert_output 'compopt +o filenames'
}

@test "bash completes the directories and files a word begins" {
  # Arrange
  only_in bash

  # Act
  run --separate-stderr bash_completions 'p'

  # Assert
  assert_success
  assert_output "$(printf '%s\n' pictures plain.txt projects)"
}

@test "bash adds the directories under CDPATH, without their base" {
  # Arrange
  only_in bash
  export CDPATH="${POOL_BASE}"

  # Act
  run --separate-stderr bash_completions 'p'

  # Assert
  assert_success
  assert_output "$(printf '%s\n' pictures plain.txt pool projects)"
}

@test "bash keeps a name with a space as one candidate" {
  # Arrange
  only_in bash

  # Act
  run --separate-stderr bash_completions 'My'

  # Assert
  assert_success
  assert_output 'My Docs'
}

@test "bash leaves a word with ~ to readline, which keeps the ~" {
  # Arrange
  only_in bash

  # Act:
  # the function offers nothing, so readline completes the file names.
  # shellcheck disable=SC2088 # the ~ as a user types it
  run --separate-stderr bash_completions '~/'
  local -r function_output="${output}"
  run --separate-stderr in_shell 'complete -p cdl'

  # Assert
  assert_success
  assert_equal "${function_output}" '' 'what the function offers'
  assert_output_contains '-o default'
}

@test "bash completes the two options of cdl_list" {
  # Arrange
  only_in bash

  # Act
  run --separate-stderr in_shell 'complete -p cdl_list'

  # Assert
  assert_success
  assert_output_contains "-W '-a --all -1 --one-column'"
}

# endregion

# region zsh

@test "zsh completes the options of cdl after a dash" {
  # Arrange
  only_in zsh

  # Act
  run --separate-stderr zsh_completions 'cdl -'

  # Assert
  assert_success
  assert_output "$(printf '%s\n' --all --help --one-column --version -1 -L -P -V -a -h)"
}

@test "with CDL_REPLACE_CD=1, zsh completes cd with the options of cdl" {
  # Arrange
  only_in zsh
  export CDL_REPLACE_CD=1

  # Act
  run --separate-stderr zsh_completions 'cd -'

  # Assert
  assert_success
  assert_output "$(printf '%s\n' --all --help --one-column --version -1 -L -P -V -a -h)"
}

@test "zsh completes the directories and files a word begins, and CDPATH directories" {
  # Arrange
  only_in zsh
  export CDPATH="${POOL_BASE}"

  # Act
  run --separate-stderr zsh_completions 'cdl p'

  # Assert
  assert_success
  assert_output "$(printf '%s\n' pictures plain.txt pool projects)"
}

@test "zsh quotes a name with a space" {
  # Arrange
  only_in zsh

  # Act
  run --separate-stderr zsh_completions 'cdl My'

  # Assert
  assert_success
  assert_output 'My\ Docs'
}

@test "zsh completes the two options of cdl_list" {
  # Arrange
  only_in zsh

  # Act
  run --separate-stderr zsh_completions 'cdl_list -'

  # Assert
  assert_success
  assert_output "$(printf '%s\n' --all --one-column -1 -a)"
}

@test "sourced before compinit, cdl registers its zsh completion at the first prompt" {
  # Arrange:
  # without it, zsh would complete file names, and none starts with a dash.
  only_in zsh

  # Act
  run --separate-stderr zsh_completions --before-compinit 'cdl -'

  # Assert
  assert_success
  assert_output "$(printf '%s\n' --all --help --one-column --version -1 -L -P -V -a -h)"
}

@test "sourced before compinit, cdl.sh prints nothing" {
  # Arrange
  only_in zsh

  # Act
  run --separate-stderr in_bare_shell 'source "$CDL_SCRIPT"'

  # Assert
  assert_success
  assert_output ''
  assert_no_stderr
}

# endregion

### End
