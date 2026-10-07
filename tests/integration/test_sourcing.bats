#!/usr/bin/env bats

# Name: tests/integration/test_sourcing.bats
# Author: Nikita Neverov (BMTLab)
# License: MIT
#
# Description:
#   cdl.sh lives in ~/.bashrc and ~/.zshrc,
#   so loading it must be cheap, repeatable and tidy,
#   and cdl must hold up in whatever shell setup it lands in.
#
#   Each test follows the Arrange-Act-Assert pattern.

bats_require_minimum_version 1.11.0

load '../support/test_helper'

function setup() {
  sandbox_setup
}

# region Loading

# bats test_tags=smoke
@test "executing cdl.sh fails with CDL_ERR_NOT_SOURCED and says how to source it" {
  # Arrange: no fixtures needed.

  # Act
  run --separate-stderr "${CDL_SHELL_PATH}" "${CDL_SCRIPT}"

  # Assert
  assert_failure 50
  assert_stderr_contains 'cdl.sh must be sourced, not executed'
}

@test "a POSIX sh refuses cdl.sh with CDL_ERR_NOT_SOURCED" {
  # Arrange: no fixtures needed.

  # Act
  run --separate-stderr sh "${CDL_SCRIPT}"

  # Assert
  assert_failure 50
  assert_stderr_contains 'cdl.sh must be'
}

@test "the return codes keep their documented values" {
  # Arrange: no fixtures needed.

  # Act
  run --separate-stderr in_shell \
    'printf "%s " "$CDL_ERR_USAGE" "$CDL_ERR_SETTING" "$CDL_ERR_CHDIR" \
       "$CDL_ERR_NOT_FOUND" "$CDL_ERR_DENIED" "$CDL_ERR_NOT_DIRECTORY" \
       "$CDL_ERR_LIST" "$CDL_ERR_NOT_SOURCED"'

  # Assert
  assert_success
  assert_output '10 20 30 31 32 33 40 50 '
}

@test "every failure to enter a directory falls in the ten of CDL_ERR_CHDIR" {
  # Arrange:
  # a missing directory, a path through a file, and a broken symlink.
  make_entries "${HOME}" 'notes.md' 'gone -> nowhere'

  # Act:
  # a script that compares the tens, as the header of cdl.sh advises.
  run --separate-stderr in_shell \
    'for target in missing notes.md/drafts gone/inner; do
       cdl "$HOME/$target" 2>/dev/null
       (( $? / 10 == CDL_ERR_CHDIR / 10 )) && printf "caught %s\n" "$target"
     done'

  # Assert
  assert_success
  assert_output "$(printf 'caught %s\n' missing notes.md/drafts gone/inner)"
}

#######################################
# Check that a return code cannot be changed.
#
# Arguments:
#   1: Name of the code.
#######################################
function a_return_code_is_read_only() {
  local -r name="$1"

  # Arrange: no fixtures needed.

  # Act
  run --separate-stderr in_shell '(eval "$1=99") 2>/dev/null || echo refused' "${name}"

  # Assert
  assert_success
  assert_output 'refused'
}

for __name in CDL_ERR_USAGE CDL_ERR_SETTING CDL_ERR_CHDIR CDL_ERR_NOT_FOUND \
  CDL_ERR_DENIED CDL_ERR_NOT_DIRECTORY CDL_ERR_LIST CDL_ERR_NOT_SOURCED; do
  bats_test_function \
    --description "${__name} is read-only" \
    -- a_return_code_is_read_only "${__name}"
done

@test "sourcing twice in one shell keeps cdl working" {
  # Arrange
  local -r target="$(make_dir 'target')"

  # Act
  run --separate-stderr in_shell \
    'source "$CDL_SCRIPT" && cdl "$1" >/dev/null && printf "%s\n" "$PWD"' "${target}"

  # Assert
  assert_success
  assert_output "${target}"
  assert_no_stderr
}

@test "sourcing from inside a function keeps cdl working afterwards" {
  # Arrange:
  # zsh plugin managers source plugins from inside functions.
  local -r missing="${HOME}/missing"

  # Act
  run --separate-stderr in_bare_shell \
    'function load_plugin() { source "$CDL_SCRIPT"; }
     load_plugin
     cdl "$1"
     printf "%s\n" "$?"' "${missing}"

  # Assert
  assert_success
  assert_output '31'
}

# bats test_tags=smoke
@test "the zsh plugin file sources cdl.sh from its own directory" {
  # Arrange
  if [[ ${CDL_SHELL_KIND} != 'zsh' ]]; then
    skip 'cdl.plugin.zsh is for zsh plugin managers'
  fi
  local -r target="$(make_dir 'target')"

  # Act:
  # sourced from elsewhere, from inside a function, as managers do.
  run --separate-stderr in_bare_shell \
    'function load_plugin() { source "$1"; }
     cd / && load_plugin "$1" && cdl "$2" >/dev/null && printf "%s\n" "$PWD"' \
    "${CDL_ROOT}/cdl.plugin.zsh" "${target}"

  # Assert
  assert_success
  assert_output "${target}"
  assert_no_stderr
}

@test "loaded from a function under WARN_CREATE_GLOBAL, cdl stays quiet" {
  # Arrange:
  # zsh warns about every global a function creates with this option,
  # and plugin managers load files from functions.
  if [[ ${CDL_SHELL_KIND} != 'zsh' ]]; then
    skip 'WARN_CREATE_GLOBAL is an option of zsh'
  fi
  local -r target="$(make_dir 'target')"
  export CDL_REPLACE_CD=1

  # Act:
  # sourcing, a call of each function, cd, and the first prompt.
  run --separate-stderr in_bare_shell \
    'setopt warn_create_global
     function load_plugin() { source "$CDL_SCRIPT"; }
     load_plugin
     cdl "$1" >/dev/null && cdl_list >/dev/null && cd / \
       && for hook in "${precmd_functions[@]}"; do "${hook}"; done >/dev/null' \
    "${target}"

  # Assert
  assert_success
  assert_no_stderr
}

@test "sourcing runs no external command" {
  # Arrange:
  # with an empty PATH, any external command would fail loudly.
  local -r empty_path="${BATS_TEST_TMPDIR}/empty"
  mkdir -p "${empty_path}"

  # Act
  run --separate-stderr in_bare_shell \
    'PATH="$1" source "$CDL_SCRIPT" && echo loaded' "${empty_path}"

  # Assert
  assert_success
  assert_output 'loaded'
  assert_no_stderr
}

@test "sourcing adds only cdl, cdl_list and __cdl_ functions" {
  # Arrange
  local list_functions='compgen -A function'
  if [[ ${CDL_SHELL_KIND} == 'zsh' ]]; then
    list_functions='print -l ${(k)functions}'
  fi

  # Act
  run --separate-stderr in_bare_shell "
    before=\"\$(${list_functions})\"
    source \"\$CDL_SCRIPT\"
    after=\"\$(${list_functions})\"
    printf '%s\n' \"\$after\" | grep -vxF \"\$before\""

  # Assert
  assert_success
  local name
  while IFS= read -r name; do
    case ${name} in
      cdl | cdl_list | __cdl_*) ;;
      *) __assert_fail "unexpected function: ${name}" ;;
    esac
  done <<<"${output}"
}

# endregion

# region Hostile shell setups

@test "cdl works in a shell running with set -eu and no terminal" {
  # Arrange:
  # without COLUMNS and TERM, tput fails,
  # which must not end a shell running with errexit.
  local -r target="$(make_dir 'target')"
  make_entries "${target}" 'entry'

  # Act
  run --separate-stderr in_bare_shell \
    'set -eu
     unset COLUMNS TERM
     source "$CDL_SCRIPT"
     cdl "$1"
     echo survived' "${target}"

  # Assert
  assert_success
  assert_output "$(listing_row '0' 'entry')"$'\nsurvived'
}

@test "user aliases and functions named ls, awk or tput do not change the listing" {
  # Arrange
  local -r target="$(make_dir 'target')"
  make_entries "${target}" 'entry'

  # Act:
  # aliases come before sourcing, the way an rc file defines them;
  # without COLUMNS, cdl has to ask tput for the width.
  run --separate-stderr in_bare_shell \
    'if [ -n "${BASH_VERSION-}" ]; then shopt -s expand_aliases; fi
     alias ls="echo hijacked"
     alias awk="echo hijacked"
     source "$CDL_SCRIPT"
     function ls() { echo hijacked; }
     function awk() { echo hijacked; }
     function tput() { echo hijacked; }
     unset COLUMNS
     cdl "$1"' "${target}"

  # Assert
  assert_success
  assert_output "$(listing_row '0' 'entry')"
}

@test "zsh options that change word splitting and arrays do not break cdl" {
  # Arrange
  if [[ ${CDL_SHELL_KIND} != 'zsh' ]]; then
    skip 'zsh only'
  fi
  local -r target="$(make_dir 'my target')"
  make_entries "${target}" 'entry'

  # Act
  run --separate-stderr in_shell \
    'setopt KSH_ARRAYS SH_WORD_SPLIT NO_UNSET WARN_CREATE_GLOBAL
     cdl "$1"
     [[ -o KSH_ARRAYS && -o SH_WORD_SPLIT ]] && echo options-kept' "${target}"

  # Assert
  assert_success
  assert_output "$(listing_row '0' 'entry')"$'\noptions-kept'
  assert_no_stderr
}

@test "cdl leaves no REPLY behind" {
  # Arrange
  local -r target="$(make_dir 'target')"

  # Act
  run --separate-stderr in_shell \
    'REPLY=mine; cdl "$1" >/dev/null; printf "%s\n" "$REPLY"' "${target}"

  # Assert
  assert_success
  assert_output 'mine'
}

# endregion

# region Listing without moving

@test "cdl_list lists the current directory and keeps OLDPWD" {
  # Arrange
  local -r first="$(make_dir 'first')"
  local -r second="$(make_dir 'second')"
  make_entries "${second}" 'entry'

  # Act
  run --separate-stderr in_shell \
    'cd "$1" && cd "$2" && cdl_list && printf "%s\n" "$OLDPWD"' "${first}" "${second}"

  # Assert
  assert_success
  assert_output "$(listing_row '0' 'entry')"$'\n'"${first}"
}

@test "a cd wrapper written for cdl 1.0 keeps working" {
  # Arrange
  local -r target="$(make_dir 'target')"
  make_entries "${target}" 'entry'

  # Act
  run --separate-stderr in_shell \
    'function cd() { builtin cd "$@" && __cdl_print_listing; }
     cd "$1"' "${target}"

  # Assert
  assert_success
  assert_output "$(listing_row '0' 'entry')"
}

# endregion

### End
