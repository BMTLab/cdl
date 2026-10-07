#!/usr/bin/env bats

# Name: tests/integration/test_header.bats
# Author: Nikita Neverov (BMTLab)
# License: MIT
#
# Description:
#   The header line above the listing:
#   the directory, with ~ for HOME, its git branch,
#   read from the files of the repository without running git,
#   and how many directories and files it holds.
#   A terminal gets the header, a file or a pipe does not,
#   and CDL_HEADER and CDL_GIT change both.
#
#   Each test follows the Arrange-Act-Assert pattern.

# The header writes HOME as a literal ~, and the expected lines do too.
# shellcheck disable=SC2088

bats_require_minimum_version 1.11.0

load '../support/test_helper'

function setup() {
  sandbox_setup
  if ! gnu_compatible_ls >/dev/null; then
    skip 'no GNU-compatible ls on this machine'
  fi

  # 60 columns keep one entry per line, so a test can count lines.
  export COLUMNS=60
  LISTED_DIR="$(make_dir 'projects/app')"
  make_entries "${LISTED_DIR}" 'src/' 'notes.md'
  export CDL_TEST_DIR="${LISTED_DIR}"
}

# region Helpers

#######################################
# Make a directory the top of a fake git repository.
#
# Only HEAD is written: that is all cdl reads.
#
# Arguments:
#   1: Directory.
#   2: The line of HEAD: 'ref: refs/heads/NAME' or a commit hash.
#######################################
function make_git_head() {
  local -r dir="$1"
  local -r head="$2"

  mkdir -p -- "${dir}/.git"
  printf '%s\n' "${head}" >"${dir}/.git/HEAD"
}

#######################################
# Run git on its own, away from the configuration of the machine.
#
# Arguments:
#   $@: Arguments for git.
#######################################
function sandbox_git() {
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    git -c user.name='cdl tests' -c user.email='cdl@example.invalid' \
    -c commit.gpgsign=false "$@"
}

# endregion

# region Where the header shows

# bats test_tags=smoke
@test "a terminal gets a header with the directory, ~ for HOME, and what it holds" {
  # Arrange
  export CDL_COLOR='never'
  printf '%1000s' '' >"${LISTED_DIR}/notes.md"
  printf '%536s' '' >"${LISTED_DIR}/todo.md"

  # Act
  run --separate-stderr in_terminal 'cdl "${CDL_TEST_DIR}"'

  # Assert:
  # the sizes of the two files add up to 1536 bytes.
  assert_success
  assert_equal "${lines[0]}" '~/projects/app · 1 dir, 2 files, 1.5K' 'the header'
}

@test "a colored header shows the directory in bold and the rest dimmed" {
  # Arrange:
  # the terminal takes colors by default; links would wrap the path.
  export CDL_LINKS='never'

  # Act
  run --separate-stderr in_terminal 'cdl "${CDL_TEST_DIR}"'

  # Assert
  assert_success
  assert_equal "${lines[0]}" $'\033[1m~/projects/app\033[0m\033[2m · 1 dir, 1 file\033[0m' \
    'the header'
}

@test "a listing sent to a pipe has no header" {
  # Arrange: no fixtures needed.

  # Act
  run --separate-stderr in_shell 'cdl "$1"' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_equal "${#lines[@]}" '2' 'lines'
  refute_output_contains '~/projects/app'
}

@test "CDL_HEADER=always puts the header on a pipe too" {
  # Arrange: no fixtures needed.

  # Act
  run --separate-stderr in_shell 'CDL_HEADER=always cdl "$1"' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_equal "${lines[0]}" '~/projects/app · 1 dir, 1 file' 'the header'
}

@test "CDL_HEADER=never keeps a terminal listing without a header" {
  # Arrange
  export CDL_COLOR='never' CDL_HEADER='never'

  # Act
  run --separate-stderr in_terminal 'cdl "${CDL_TEST_DIR}"'

  # Assert
  assert_success
  assert_equal "${#lines[@]}" '2' 'lines'
  refute_output_contains '~/projects/app'
}

@test "a directory ls cannot read gets no header, so no count misleads" {
  # Arrange:
  # search permission without read permission: cd works, ls does not.
  if ((EUID == 0)); then
    skip 'root reads any directory'
  fi
  local -r blind="$(make_dir 'blind')"
  chmod 100 "${blind}"

  # Act
  run --separate-stderr in_shell 'CDL_HEADER=always cdl "$1"' "${blind}"
  chmod 755 "${blind}"

  # Assert
  assert_failure 40
  assert_output ''
}

# endregion

# region The path

#######################################
# Check that the header shows the whole path when HOME cannot shorten it.
#
# Arguments:
#   1: Shell code that changes HOME.
#######################################
function the_header_shows_the_whole_path() {
  local -r home_change="$1"

  # Arrange:
  # the listed directory lies under the HOME of the sandbox,
  # and a wide terminal leaves its path room enough.
  export COLUMNS=250

  # Act
  run --separate-stderr in_shell \
    "${home_change}; CDL_HEADER=always cdl \"\$1\"" "${LISTED_DIR}"

  # Assert
  assert_success
  assert_equal "${lines[0]}" "${LISTED_DIR} · 1 dir, 1 file" 'the header'
}

# Samples: "description|code that changes HOME".
__HOME_CHANGES=(
  'with HOME elsewhere|HOME=/elsewhere'
  'without HOME|unset HOME'
  'with HOME at the root|HOME=/'
)

for __sample in "${__HOME_CHANGES[@]}"; do
  bats_test_function \
    --description "${__sample%%|*}, the header shows the whole path" \
    -- the_header_shows_the_whole_path "${__sample#*|}"
done

@test "a HOME with a trailing slash still shows as ~" {
  # Arrange: no fixtures needed.

  # Act
  run --separate-stderr in_shell \
    'HOME="${HOME}/"; CDL_HEADER=always cdl "$1"' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_equal "${lines[0]}" '~/projects/app · 1 dir, 1 file' 'the header'
}

# endregion

# region Git branch

# bats test_tags=smoke
@test "the header names the git branch, read from .git/HEAD" {
  # Arrange
  make_git_head "${LISTED_DIR}" 'ref: refs/heads/feature/header'

  # Act
  run --separate-stderr in_shell 'CDL_HEADER=always cdl "$1"' "${LISTED_DIR}"

  # Assert:
  # .git is a hidden directory, and counts as one.
  assert_success
  assert_equal "${lines[0]}" '~/projects/app · feature/header · 2 dirs, 1 file' 'the header'
}

@test "a subdirectory shows the branch of its repository" {
  # Arrange
  make_git_head "${HOME}/projects" 'ref: refs/heads/main'

  # Act
  run --separate-stderr in_shell 'CDL_HEADER=always cdl "$1"' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_equal "${lines[0]}" '~/projects/app · main · 1 dir, 1 file' 'the header'
}

@test "a detached HEAD shows the short hash of its commit" {
  # Arrange
  make_git_head "${LISTED_DIR}" '0123456789abcdef0123456789abcdef01234567'

  # Act
  run --separate-stderr in_shell 'CDL_HEADER=always cdl "$1"' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_equal "${lines[0]}" '~/projects/app · 0123456 · 2 dirs, 1 file' 'the header'
}

#######################################
# Check that a worktree shows the branch of the git directory
# its .git file names.
#
# Arguments:
#   1: How the .git file names it: 'absolute' or 'relative'.
#######################################
function a_worktree_shows_its_own_branch() {
  local -r spelling="$1"

  # Arrange:
  # the .git file of the worktree names a git directory
  # under ~/repo.git, as `git worktree add` lays them out.
  # A relative name counts from the directory of the .git file,
  # so the test lists a subdirectory, where the two differ.
  local -r git_dir="${HOME}/repo.git/worktrees/app"
  mkdir -p -- "${git_dir}"
  printf 'ref: refs/heads/topic\n' >"${git_dir}/HEAD"
  if [[ ${spelling} == 'absolute' ]]; then
    printf 'gitdir: %s\n' "${git_dir}" >"${LISTED_DIR}/.git"
  else
    printf 'gitdir: ../../repo.git/worktrees/app\n' >"${LISTED_DIR}/.git"
  fi

  # Act
  run --separate-stderr in_shell 'CDL_HEADER=always cdl "$1"' "${LISTED_DIR}/src"

  # Assert
  assert_success
  assert_output '~/projects/app/src · topic · 0 dirs, 0 files'
}

for __spelling in 'absolute' 'relative'; do
  bats_test_function \
    --description "a worktree whose .git file gives an ${__spelling} path shows its own branch" \
    -- a_worktree_shows_its_own_branch "${__spelling}"
done

@test "a reftable repository shows no branch rather than a wrong one" {
  # Arrange:
  # the reftable format leaves this stub in HEAD for older tools.
  make_git_head "${LISTED_DIR}" 'ref: refs/heads/.invalid'

  # Act
  run --separate-stderr in_shell 'CDL_HEADER=always cdl "$1"' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_equal "${lines[0]}" '~/projects/app · 2 dirs, 1 file' 'the header'
}

@test "a .git without HEAD shows no branch, and no error" {
  # Arrange
  mkdir -p "${LISTED_DIR}/.git"

  # Act
  run --separate-stderr in_shell 'CDL_HEADER=always cdl "$1"' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_equal "${lines[0]}" '~/projects/app · 2 dirs, 1 file' 'the header'
  assert_no_stderr
}

@test "CDL_GIT=0 leaves the branch out" {
  # Arrange
  make_git_head "${LISTED_DIR}" 'ref: refs/heads/main'

  # Act
  run --separate-stderr in_shell 'CDL_GIT=0 CDL_HEADER=always cdl "$1"' "${LISTED_DIR}"

  # Assert
  assert_success
  assert_equal "${lines[0]}" '~/projects/app · 2 dirs, 1 file' 'the header'
}

@test "a repository and its worktree made by git show their branches" {
  # Arrange
  if ! command -v git >/dev/null; then
    skip 'git is not installed'
  fi
  local -r repository="$(make_dir 'repository')"
  sandbox_git init --quiet --initial-branch=trunk "${repository}"
  sandbox_git -C "${repository}" commit --quiet --allow-empty --message='Start'
  sandbox_git -C "${repository}" worktree add --quiet -b topic "${HOME}/worktree"

  # Act
  run --separate-stderr in_shell \
    'CDL_HEADER=always cdl "$1" | head -n 1 && CDL_HEADER=always cdl "$2" | head -n 1' \
    "${repository}" "${HOME}/worktree"

  # Assert
  assert_success
  assert_output_contains '~/repository · trunk · '
  assert_output_contains '~/worktree · topic · '
}

# endregion

### End
