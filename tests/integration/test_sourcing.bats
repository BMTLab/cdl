#!/usr/bin/env bats

# Test that loading cdl.sh is cheap, repeatable and tidy, in any shell setup.
#
# cdl.sh lives in ~/.bashrc and ~/.zshrc,
# so cdl must hold up in whatever shell setup it lands in.

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

@test "bash in POSIX mode, as sh is on macOS, refuses cdl.sh with CDL_ERR_NOT_SOURCED" {
  # Arrange: no fixtures needed.

  # Act
  run --separate-stderr bash --posix "${CDL_SCRIPT}"

  # Assert
  assert_failure 50
  assert_stderr_contains 'cdl.sh must be sourced into bash or zsh'
}

@test "the return codes keep their documented values" {
  # Arrange: no fixtures needed.

  # Act
  run --separate-stderr in_shell \
    'printf "%s " "${CDL_ERR_USAGE}" "${CDL_ERR_SETTING}" "${CDL_ERR_CHDIR}" \
       "${CDL_ERR_NOT_FOUND}" "${CDL_ERR_DENIED}" "${CDL_ERR_NOT_DIRECTORY}" \
       "${CDL_ERR_LIST}" "${CDL_ERR_NOT_SOURCED}"'

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
       cdl "${HOME}/${target}" 2>/dev/null
       if (( $? / 10 == CDL_ERR_CHDIR / 10 )); then
         printf "caught %s\n" "${target}"
       fi
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
  run --separate-stderr in_shell '(eval "$1=99") 2>/dev/null || printf "%s\n" refused' "${name}"

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
  local target

  # Arrange
  target="$(make_directory 'target')"

  # Act
  run --separate-stderr in_shell \
    'source "${CDL_SCRIPT}" && cdl "$1" >/dev/null && printf "%s\n" "${PWD}"' "${target}"

  # Assert
  assert_success
  assert_output "${target}"
  assert_no_stderr
}

@test "sourcing from inside a function keeps cdl working afterwards" {
  local -r missing="${HOME}/missing"

  # Arrange:
  # zsh plugin managers source plugins from inside functions.
  # Act
  run --separate-stderr in_bare_shell \
    'function load_plugin() { source "${CDL_SCRIPT}"; }
     load_plugin
     cdl "$1"
     printf "%s\n" "$?"' "${missing}"

  # Assert
  assert_success
  assert_output '31'
}

# bats test_tags=smoke
@test "the zsh plugin file sources cdl.sh from its own directory" {
  local target

  # Arrange
  if [[ "${CDL_SHELL_KIND}" != 'zsh' ]]; then
    skip 'cdl.plugin.zsh is for zsh plugin managers'
  fi

  target="$(make_directory 'target')"

  # Act:
  # sourced from elsewhere, from inside a function, as managers do.
  run --separate-stderr in_bare_shell \
    'function load_plugin() { source "$1"; }
     cd / && load_plugin "$1" && cdl "$2" >/dev/null && printf "%s\n" "${PWD}"' \
    "${CDL_ROOT}/cdl.plugin.zsh" "${target}"

  # Assert
  assert_success
  assert_output "${target}"
  assert_no_stderr
}

@test "loaded from a function under WARN_CREATE_GLOBAL, cdl stays quiet" {
  local target

  # Arrange:
  # zsh warns about every global a function creates with this option,
  # and plugin managers load files from functions.
  if [[ "${CDL_SHELL_KIND}" != 'zsh' ]]; then
    skip 'WARN_CREATE_GLOBAL is an option of zsh'
  fi

  target="$(make_directory 'target')"
  export CDL_REPLACE_CD=1

  # Act:
  # sourcing, a call of each function, cd, and the first prompt.
  run --separate-stderr in_bare_shell \
    'setopt warn_create_global
     function load_plugin() { source "${CDL_SCRIPT}"; }
     load_plugin
     cdl "$1" >/dev/null && cdl_list >/dev/null && cd / \
       && for hook in "${precmd_functions[@]}"; do "${hook}"; done >/dev/null' \
    "${target}"

  # Assert
  assert_success
  assert_no_stderr
}

@test "sourcing runs no external command" {
  local -r empty_path="${BATS_TEST_TMPDIR}/empty"

  # Arrange:
  # with an empty PATH, any external command would fail loudly.
  mkdir -p "${empty_path}"

  # Act
  run --separate-stderr in_bare_shell \
    'PATH="$1" source "${CDL_SCRIPT}" && printf "%s\n" loaded' "${empty_path}"

  # Assert
  assert_success
  assert_output 'loaded'
  assert_no_stderr
}

@test "sourcing adds only cdl, cdl_list and __cdl_ functions" {
  local list_functions='compgen -A function'
  local name

  # Arrange
  if [[ "${CDL_SHELL_KIND}" == 'zsh' ]]; then
    list_functions='print -l ${(k)functions}'
  fi

  # Act
  run --separate-stderr in_bare_shell "
    before=\"\$(${list_functions})\"
    source \"\${CDL_SCRIPT}\"
    after=\"\$(${list_functions})\"
    printf '%s\n' \"\${after}\" | grep -vxF \"\${before}\""

  # Assert
  assert_success

  while IFS= read -r name; do
    case "${name}" in
      cdl | cdl_list | __cdl_*) ;;
      *) fail_with_report "unexpected function: ${name}" ;;
    esac
  done <<<"${output}"
}

# endregion Loading

# region Hostile shell setups

@test "cdl works in a shell running with set -eu and no terminal" {
  local target

  # Arrange:
  # without COLUMNS and TERM, tput fails,
  # which must not end a shell running with errexit.
  require_gnu_compatible_ls
  target="$(make_directory 'target')"
  make_entries "${target}" 'entry'

  # Act
  run --separate-stderr in_bare_shell \
    'set -eu
     unset COLUMNS TERM
     source "${CDL_SCRIPT}"
     cdl "$1"
     printf "%s\n" survived' "${target}"

  # Assert
  assert_success
  assert_output "$(listing_row '0' 'entry')"$'\nsurvived'
}

@test "user aliases and functions named ls, awk or tput do not change the listing" {
  local target

  # Arrange
  require_gnu_compatible_ls
  target="$(make_directory 'target')"
  make_entries "${target}" 'entry'

  # Act:
  # aliases come before sourcing, the way an rc file defines them;
  # without COLUMNS, cdl has to ask tput for the width.
  run --separate-stderr in_bare_shell \
    'if [[ -n "${BASH_VERSION-}" ]]; then shopt -s expand_aliases; fi
     alias ls="printf \"%s\n\" hijacked"
     alias awk="printf \"%s\n\" hijacked"
     source "${CDL_SCRIPT}"
     function ls() { printf "%s\n" hijacked; }
     function awk() { printf "%s\n" hijacked; }
     function tput() { printf "%s\n" hijacked; }
     unset COLUMNS
     cdl "$1"' "${target}"

  # Assert
  assert_success
  assert_output "$(listing_row '0' 'entry')"
}

@test "zsh options that change word splitting and arrays do not break cdl" {
  local target

  # Arrange
  if [[ "${CDL_SHELL_KIND}" != 'zsh' ]]; then
    skip 'zsh only'
  fi

  require_gnu_compatible_ls
  target="$(make_directory 'my target')"
  make_entries "${target}" 'entry'

  # Act
  run --separate-stderr in_shell \
    'setopt KSH_ARRAYS SH_WORD_SPLIT NO_UNSET WARN_CREATE_GLOBAL
     cdl "$1"
     if [[ -o KSH_ARRAYS && -o SH_WORD_SPLIT ]]; then
       printf "%s\n" options-kept
     fi' "${target}"

  # Assert
  assert_success
  assert_output "$(listing_row '0' 'entry')"$'\noptions-kept'
  assert_no_stderr
}

@test "cdl leaves no REPLY behind" {
  local target

  # Arrange
  target="$(make_directory 'target')"

  # Act
  run --separate-stderr in_shell \
    'REPLY=mine; cdl "$1" >/dev/null; printf "%s\n" "${REPLY}"' "${target}"

  # Assert
  assert_success
  assert_output 'mine'
}

# endregion Hostile shell setups

# region Listing without moving

@test "cdl_list lists the current directory and keeps OLDPWD" {
  local first
  local second

  # Arrange
  require_gnu_compatible_ls
  first="$(make_directory 'first')"
  second="$(make_directory 'second')"
  make_entries "${second}" 'entry'

  # Act
  run --separate-stderr in_shell \
    'cd "$1" && cd "$2" && cdl_list && printf "%s\n" "${OLDPWD}"' "${first}" "${second}"

  # Assert
  assert_success
  assert_output "$(listing_row '0' 'entry')"$'\n'"${first}"
}

@test "a cd wrapper written for cdl 1.0 keeps working" {
  local target

  # Arrange
  require_gnu_compatible_ls
  target="$(make_directory 'target')"
  make_entries "${target}" 'entry'

  # Act
  run --separate-stderr in_shell \
    'function cd() { builtin cd "$@" && __cdl_print_listing; }
     cd "$1"' "${target}"

  # Assert
  assert_success
  assert_output "$(listing_row '0' 'entry')"
}

# endregion Listing without moving

### End
