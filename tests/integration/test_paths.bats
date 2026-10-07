#!/usr/bin/env bats

# Name: tests/integration/test_paths.bats
# Author: Nikita Neverov (BMTLab)
# License: MIT
#
# Description:
#   Paths that are not a plain directory:
#   a file, which cdl shows in its directory with a mark;
#   a file:// URI, as file managers copy them;
#   and a leading ~ that the shell left alone,
#   as in a quoted operand or a piped path.
#
#   Each test follows the Arrange-Act-Assert pattern.

# The tests spell out the ~ that cdl expands.
# shellcheck disable=SC2088

bats_require_minimum_version 1.11.0

load '../support/test_helper'

function setup() {
  sandbox_setup
  require_gnu_compatible_ls

  DOCS_DIR="$(make_dir 'docs')"
  make_entries "${DOCS_DIR}" 'drafts/' 'notes.md' 'report.pdf'
}

# region Files

# bats test_tags=smoke
@test "a file operand enters its directory and marks the file there" {
  # Arrange: no fixtures needed.

  # Act
  run --separate-stderr in_shell \
    'cdl "$1" && printf "PWD=%s\n" "$PWD"' "${DOCS_DIR}/notes.md"

  # Assert
  assert_success
  assert_output_contains "$(marked_row 0 'notes.md')"
  assert_output_contains "PWD=${DOCS_DIR}"
}

#######################################
# Check that a file of the current directory is marked
# without a move that would replace OLDPWD.
#
# Arguments:
#   1: How the file is named: 'notes.md' or './notes.md'.
#######################################
function a_file_here_is_marked_without_moving() {
  local -r name="$1"

  # Arrange: the snippet comes to docs from HOME.

  # Act
  run --separate-stderr in_shell \
    'cd "$1" && cdl "$2" >/dev/null && printf "%s\n" "$PWD" "$OLDPWD"' "${DOCS_DIR}" "${name}"

  # Assert:
  # docs, and HOME before it, for cdl - to go back to.
  assert_success
  assert_output "${DOCS_DIR}"$'\n'"${HOME}"
}

for __name in 'notes.md' './notes.md'; do
  bats_test_function \
    --description "a file here named ${__name} is marked without moving, so cdl - still goes back" \
    -- a_file_here_is_marked_without_moving "${__name}"
done

@test "a relative path to a file enters its own directory, whatever CDPATH holds" {
  # Arrange:
  # CDPATH holds another docs directory, which cd would prefer.
  local -r elsewhere="$(make_dir 'elsewhere')"
  make_dir 'elsewhere/docs' >/dev/null

  # Act
  run --separate-stderr in_shell \
    'CDPATH="$1" cdl docs/notes.md >/dev/null && printf "%s\n" "$PWD"' "${elsewhere}"

  # Assert
  assert_success
  assert_output "${DOCS_DIR}"
}

@test "cd still decides first: a CDPATH directory wins over a file of the same name" {
  # Arrange
  local -r elsewhere="$(make_dir 'elsewhere')"
  make_dir 'elsewhere/report.pdf' >/dev/null

  # Act
  run --separate-stderr in_shell \
    'cd "$1" && CDPATH="$2" cdl report.pdf >/dev/null && printf "%s\n" "$PWD"' \
    "${DOCS_DIR}" "${elsewhere}"

  # Assert
  assert_success
  assert_output "${elsewhere}/report.pdf"
}

@test "a symlink to a file is marked in the directory of the link" {
  # Arrange
  make_entries "${HOME}" 'latest -> docs/report.pdf'

  # Act
  run --separate-stderr in_shell \
    'cdl "$1" && printf "PWD=%s\n" "$PWD"' "${HOME}/latest"

  # Assert
  assert_success
  assert_output_contains ' ❯latest -> docs/report.pdf'
  assert_output_contains "PWD=${HOME}"
}

@test "a broken symlink is marked in its directory" {
  # Arrange
  make_entries "${DOCS_DIR}" 'old -> gone.pdf'

  # Act
  run --separate-stderr in_shell 'cdl "$1"' "${DOCS_DIR}/old"

  # Assert
  assert_success
  assert_output_contains ' ❯old -> gone.pdf'
}

@test "a hidden file is listed and marked even with CDL_HIDDEN=0" {
  # Arrange
  make_entries "${DOCS_DIR}" '.secret'

  # Act
  run --separate-stderr in_shell 'CDL_HIDDEN=0 cdl "$1"' "${DOCS_DIR}/.secret"

  # Assert
  assert_success
  assert_output_contains "$(marked_row 0 '.secret')"
}

@test "a file deep in a long listing on a terminal brings the listing to it" {
  # Arrange:
  # forty entries in one column; ten lines keep six rows,
  # five of them around the mark under the line about those before.
  local -r long_dir="$(make_dir 'long')"
  local -a names=()
  local -i number
  for ((number = 10; number < 50; number++)); do
    names+=("entry-${number}")
  done
  make_entries "${long_dir}" "${names[@]}"
  export LINES=10 COLUMNS=60 CDL_COLOR='never' CDL_TEST_FILE="${long_dir}/entry-40"

  # Act
  run --separate-stderr in_terminal 'cdl "${CDL_TEST_FILE}"'

  # Assert:
  # the header, the line before, entry-38 to entry-42, the line after.
  assert_success
  assert_equal "${lines[1]}" '… 28 before' 'the line before'
  assert_equal "${lines[4]}" "$(marked_row 0 'entry-40')" 'the marked row'
  assert_equal "${lines[7]}" '… 7 more; -a shows all' 'the line after'
}

@test "a file with a trailing slash fails, and says it is not a directory" {
  # Arrange: docs/notes.md is a file.

  # Act
  run --separate-stderr cdl_then_pwd "${DOCS_DIR}/notes.md/"

  # Assert
  assert_failure 33
  assert_output "${HOME}"
  assert_stderr_contains "cdl: Not a directory: '${DOCS_DIR}/notes.md/'"
}

# bats test_tags=smoke
@test "a path through a file fails with CDL_ERR_NOT_DIRECTORY, and names the file" {
  # Arrange: docs/notes.md is a file.

  # Act
  run --separate-stderr cdl_then_pwd "${DOCS_DIR}/notes.md/inner"

  # Assert
  assert_failure 33
  assert_output "${HOME}"
  assert_stderr_contains \
    "cdl: Not a directory: '${DOCS_DIR}/notes.md/inner' ('${DOCS_DIR}/notes.md' is a file)"
}

# endregion

# region URIs

@test "a file:// URI enters the path its percent escapes spell" {
  # Arrange:
  # a space and a Cyrillic letter, as a file manager encodes them.
  local -r target="$(make_dir 'My Docs Д')"

  # Act
  run --separate-stderr cdl_then_pwd "file://${HOME}/My%20Docs%20%D0%94"

  # Assert
  assert_success
  assert_output "${target}"
}

@test "a file://localhost URI enters its path too" {
  # Arrange: no fixtures needed.

  # Act
  run --separate-stderr cdl_then_pwd "file://localhost${DOCS_DIR}"

  # Assert
  assert_success
  assert_output "${DOCS_DIR}"
}

@test "a URI of a file enters its directory and marks the file" {
  # Arrange: no fixtures needed.

  # Act
  run --separate-stderr in_shell 'cdl "$1"' "file://${DOCS_DIR}/report.pdf"

  # Assert
  assert_success
  assert_output_contains "$(marked_row 0 'report.pdf')"
}

@test "a percent sign without two hex digits after it stays as it is" {
  # Arrange
  local -r target="$(make_dir '100%')"

  # Act
  run --separate-stderr cdl_then_pwd "file://${HOME}/100%"

  # Assert
  assert_success
  assert_output "${target}"
}

@test "a %00 in a URI stays as written, in bash and zsh alike" {
  # Arrange:
  # no name holds a NUL byte; zsh would cut the path there,
  # and enter the directory of notes.md.

  # Act
  run --separate-stderr cdl_then_pwd "file://${DOCS_DIR}/notes.md%00tail"

  # Assert
  assert_failure 31
  assert_output "${HOME}"
  assert_stderr_contains "cdl: No such file or directory: '${DOCS_DIR}/notes.md%00tail'"
}

@test "a URI of another host fails as written, with CDL_ERR_NOT_FOUND" {
  # Arrange: no fixtures needed.

  # Act
  run --separate-stderr cdl_then_pwd 'file://server/share'

  # Assert
  assert_failure 31
  assert_stderr_contains "cdl: No such file or directory: 'file://server/share'"
}

# endregion

# region Tilde

#######################################
# Check that a leading ~ the shell left alone means HOME.
#
# Arguments:
#   1: Snippet that hands cdl the path in $1.
#   2: The path, starting with ~.
#   3: Where cdl should land, relative to HOME.
#######################################
function a_leading_tilde_means_home() {
  local -r snippet="$1"
  local -r path="$2"
  local -r landing="$3"

  # Arrange: docs lies in HOME; the snippet starts in the root.

  # Act
  run --separate-stderr in_shell \
    "cd / && ${snippet} >/dev/null && printf '%s\n' \"\$PWD\"" "${path}"

  # Assert
  assert_success
  assert_output "${HOME}${landing}"
}

bats_test_function \
  --description 'a quoted ~ operand means HOME' \
  -- a_leading_tilde_means_home 'cdl "$1"' '~' ''
bats_test_function \
  --description 'a quoted ~/docs operand means the docs of HOME' \
  -- a_leading_tilde_means_home 'cdl "$1"' '~/docs' '/docs'

@test "a piped ~/docs means the docs of HOME" {
  # Arrange: docs lies in HOME; the snippet starts in the root.

  # Act:
  # bash runs a piped cdl in a subshell, so the listing tells where it went.
  run --separate-stderr in_shell 'cd / && printf "%s\n" "$1" | cdl' '~/docs'

  # Assert
  assert_success
  assert_output_contains 'notes.md'
}

@test "a directory named ~ here wins over HOME" {
  # Arrange
  local -r literal="$(make_dir 'here/~')"

  # Act
  run --separate-stderr in_shell \
    'cd "$1" && cdl "~" >/dev/null && printf "%s\n" "$PWD"' "${HOME}/here"

  # Assert
  assert_success
  assert_output "${literal}"
}

# endregion

### End
