#!/usr/bin/env bats

# Name: tests/style/test_conventions.bats
# Author: Nikita Neverov (BMTLab)
# License: MIT
#
# Description:
#   The conventions of the BMTLab ScriptsLib code style
#   that shellcheck and shfmt cannot see,
#   and the facts that several files must agree on:
#   the version, the date and the return codes.
#
#   Each test collects every violation first and then reports them all,
#   so one run shows the whole list.
#   Each test follows the Arrange-Act-Assert pattern.

bats_require_minimum_version 1.11.0

load '../support/test_helper'

# region Helpers

#######################################
# List the shell files of the project, relative to its root.
#
# Outputs:
#   One path per line: scripts, helpers and test files.
#######################################
function shell_files() {
  (
    cd "${CDL_ROOT}" || exit
    find . \( -path ./.git -o -path ./.idea \) -prune -o -type f \
      \( -name '*.sh' -o -name '*.bash' -o -name '*.bats' -o -path './tests/support/bin/*' \) \
      -print | sed 's#^\./##' | sort
  )
}

#######################################
# Print the value of a `# Key: value` line in the header of cdl.sh.
#
# Arguments:
#   1: Header key, e.g. 'Version'.
#######################################
function script_header() {
  sed -n "s/^# $1: *//p" "${CDL_SCRIPT}" | head -n 1
}

#######################################
# Fail the test with a list of violations, if there are any.
#
# Arguments:
#   1: What the violations break.
#   $@: The violations.
#######################################
function report_violations() {
  local -r rule="$1"
  shift

  if (($# > 0)); then
    __assert_fail "${rule}:$(printf '\n  - %s' "$@")"
  fi
}

# endregion

# region Headers

@test "every shell file starts with a header naming itself, its author and license" {
  # Arrange
  local file
  local -a violations=()

  # Act
  while IFS= read -r file; do
    local header
    header="$(head -n 12 "${CDL_ROOT}/${file}")"
    if ! grep -qxF "# Name: ${file##*/}" <<<"${header}" \
      && ! grep -qxF "# Name: ${file}" <<<"${header}"; then
      violations+=("${file}: no '# Name:' line naming the file")
    fi
    if ! grep -qx '# Author: Nikita Neverov (BMTLab)' <<<"${header}"; then
      violations+=("${file}: no '# Author:' line")
    fi
    if ! grep -qx '# License: MIT' <<<"${header}"; then
      violations+=("${file}: no '# License: MIT' line")
    fi
  done < <(shell_files)

  # Assert
  report_violations 'headers' "${violations[@]}"
}

@test "cdl.sh declares a semantic version and an ISO date" {
  # Arrange: the header of cdl.sh is the input.

  # Act
  local -r version="$(script_header 'Version')"
  local -r date="$(script_header 'Date')"

  # Assert
  if [[ ! ${version} =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    __assert_fail "not a semantic version: '${version}'"
  fi
  if [[ ! ${date} =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    __assert_fail "not an ISO date: '${date}'"
  fi
}

# endregion

# region Facts several files share

@test "cdl --version reports the version in the header of cdl.sh" {
  # Arrange
  local -r version="$(script_header 'Version')"

  # Act
  run grep -cx "CDL_VERSION='${version}'" "${CDL_SCRIPT}"

  # Assert
  assert_success
  assert_output '1'
}

@test "the CHANGELOG has a section for the version and date of cdl.sh" {
  # Arrange
  local -r version="$(script_header 'Version')"
  local -r date="$(script_header 'Date')"

  # Act
  run grep -cxF "## [${version}] - ${date}" "${CDL_ROOT}/CHANGELOG.md"

  # Assert
  assert_success
  assert_output '1'
}

@test "every return code is documented in the header, the help and the README" {
  # Arrange
  local -r help_text="$(in_shell 'cdl --help')"
  local -r readme="$(<"${CDL_ROOT}/README.md")"
  local name value
  local -a violations=()

  # Act
  while IFS='=' read -r name value; do
    if ! grep -qxF "#   ${value}: ${name}" "${CDL_SCRIPT}"; then
      violations+=("${name}=${value}: missing from the header of cdl.sh")
    fi
    if ! grep -qE "^  ${value}  ${name} " <<<"${help_text}"; then
      violations+=("${name}=${value}: missing from cdl --help")
    fi
    # The README holds a table row: | `2` | `CDL_ERR_NOT_FOUND` | ... |
    if ! grep -qE "^\| +\`${value}\` +\| +\`${name}\` +\|" <<<"${readme}"; then
      violations+=("${name}=${value}: missing from the table of codes in README.md")
    fi
  done < <(sed -n 's/^: "\${\(CDL_ERR_[A-Z_]*\):=\([0-9]*\)}"$/\1=\2/p' "${CDL_SCRIPT}")

  # Assert
  if ((${#violations[@]} == 0)) && [[ -z ${help_text} ]]; then
    __assert_fail 'cdl --help printed nothing'
  fi
  report_violations 'return codes' "${violations[@]}"
}

#######################################
# Print the exit codes every tool of the project names, as "FILE CODE NAME".
#
# The shell scripts name their codes `readonly X_ERR_Y=N`,
# the Makefile `X_ERR_Y := N` and the Python tools `EXIT_X = N`;
# success is left out. The return codes of cdl.sh are no tool's:
# a test of their own checks them.
#
# Outputs:
#   One line per code, paths relative to the project root.
#######################################
function named_exit_codes() {
  (
    cd "${CDL_ROOT}" || exit
    for file in $(shell_files) tools/*.py Makefile; do
      sed -n -E \
        -e "s/^readonly ([A-Z_]+_ERR_[A-Z_]+)=([0-9]+)$/${file//\//\\/} \\2 \\1/p" \
        -e "s/^([A-Z_]+_ERR_[A-Z_]+) *:= *([0-9]+)$/${file//\//\\/} \\2 \\1/p" \
        -e "s/^(EXIT_[A-Z_]+) = ([0-9]+)$/${file//\//\\/} \\2 \\1/p" \
        "${file}"
    done
  ) | awk '$2 != 0'
}

@test "every return code of cdl is a category of ten, or a reason inside one" {
  # Arrange:
  # the codes of cdl.sh, a public API of their own,
  # apart from the blocks of the tools (see "Exit codes" in CLAUDE.md).
  local -r codes="$(sed -n 's/^: "\${\(CDL_ERR_[A-Z_]*\):=\([0-9]*\)}"$/\2 \1/p' "${CDL_SCRIPT}")"
  local -a violations=()

  # Act:
  # a code out of range, a code named twice,
  # and a reason whose category has no code of its own.
  local line
  while IFS= read -r line; do
    violations+=("${line}")
  done < <(awk '
    $1 < 10 { print $2 " = " $1 ": codes start at 10, the first category" }
    $1 > 125 { print $2 " = " $1 ": the shell and the signals own the codes from 126" }
    { count[$1]++; names[$1] = names[$1] " " $2 }
    END {
      for (code in count) {
        if (count[code] > 1) print "code " code " is named more than once:" names[code]
        category = code - code % 10
        if (code % 10 && !(category in count)) print names[code] " = " code ": its category " category " has no code"
      }
    }' <<<"${codes}")

  # Assert
  if [[ -z ${codes} ]]; then
    __assert_fail 'no return codes found in cdl.sh'
  fi
  report_violations 'return codes of cdl' "${violations[@]}"
}

@test "every tool owns a block of ten exit codes, which no other tool uses" {
  # Arrange
  local -r codes="$(named_exit_codes)"
  local -a violations=()

  # Act:
  # a code named twice; a file whose codes span two blocks;
  # a block that two files share.
  local duplicate
  while IFS= read -r duplicate; do
    violations+=("code ${duplicate} is named more than once: $(awk -v code="${duplicate}" '$2 == code { printf "%s %s; ", $1, $3 }' <<<"${codes}")")
  done < <(awk '{ print $2 }' <<<"${codes}" | sort -n | uniq -d)

  local line
  while IFS= read -r line; do
    violations+=("${line}")
  done < <(awk '
    { block = int($2 / 10) }
    ($1 in owner_block) && owner_block[$1] != block && !reported[$1, block]++ {
      print $1 " spans the blocks " owner_block[$1] "0 and " block "0"
    }
    !($1 in owner_block) {
      owner_block[$1] = block
      if (block in block_owner) print "block " block "0 belongs to " block_owner[block] " and " $1
      else block_owner[block] = $1
    }' <<<"${codes}")

  # Assert
  if [[ -z ${codes} ]]; then
    __assert_fail 'no named exit codes found'
  fi
  report_violations 'exit codes' "${violations[@]}"
}

@test "every setting is documented in cdl.sh, the help and the README" {
  # Arrange
  local -r help_text="$(in_shell 'cdl --help')"
  local -r readme="$(<"${CDL_ROOT}/README.md")"
  local name
  local -i settings=0
  local -a violations=()

  # Act:
  # the settings are the variables that __cdl_read_settings reads,
  # as list_cdl_settings finds them for the sandbox too.
  while IFS= read -r name; do
    settings+=1
    if ! grep -qE "^#   ${name} " "${CDL_SCRIPT}"; then
      violations+=("${name}: missing from the table of settings in cdl.sh")
    fi
    if ! grep -qE "^  ${name} " <<<"${help_text}"; then
      violations+=("${name}: missing from cdl --help")
    fi
    if [[ ${readme} != *"| \`${name}\`"* ]]; then
      violations+=("${name}: missing from the table of settings in README.md")
    fi
  done < <(list_cdl_settings)

  # Assert
  if ((settings == 0)); then
    __assert_fail 'no settings found in __cdl_read_settings'
  fi
  report_violations 'settings' "${violations[@]}"
}

@test "the map in CLAUDE.md names the regions of cdl.sh in order" {
  # Arrange
  local -r regions="$(sed -n 's/^# region //p' "${CDL_SCRIPT}" | paste -sd ',' - | sed 's/,/, /g')"

  # Act:
  # the numbered list under the map, each item up to its first comma,
  # which leaves out the regions of the awk program.
  local -r mapped="$(
    awk '
      /^The regions of `cdl.sh` read top to bottom:$/ { inside = 1; next }
      inside && /^[0-9]+\. / { sub(/^[0-9]+\. /, ""); sub(/,.*/, ""); print; listed = 1; next }
      listed && /^$/ { exit }
    ' "${CDL_ROOT}/CLAUDE.md" | paste -sd ',' - | sed 's/,/, /g'
  )"

  # Assert
  assert_equal "${mapped}" "${regions}" 'regions'
}

# endregion

# region Code style

@test "every shell file is formatted as the workspace rule shfmt -i 2 -ci -bn says" {
  # Arrange:
  # `make format` takes its options from .editorconfig;
  # this keeps that file in step with the flags of the workspace style.
  if ! command -v shfmt >/dev/null; then
    skip 'shfmt is not installed'
  fi
  local -a files=()
  local file
  while IFS= read -r file; do
    files+=("${CDL_ROOT}/${file}")
  done < <(shell_files)

  # Act
  run shfmt -i 2 -ci -bn -d "${files[@]}"

  # Assert
  assert_success
  assert_output ''
}

@test "no file uses the em-dash" {
  # Arrange: the punctuation rule covers every text file.

  # Act:
  # the UTF-8 bytes of U+2014, matched byte by byte.
  LC_ALL=C run grep -rIl --exclude-dir=.git --exclude-dir=.idea \
    $'\xe2\x80\x94' "${CDL_ROOT}"

  # Assert:
  # grep exits with 1 when nothing matches.
  assert_failure 1
  assert_output ''
}

@test "shell functions are declared with the function keyword" {
  # Arrange
  local file
  local -a violations=()

  # Act
  while IFS= read -r file; do
    while IFS= read -r match; do
      violations+=("${file}:${match}")
    done < <(grep -nE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*\(\)[[:space:]]*\{' "${CDL_ROOT}/${file}")
  done < <(shell_files)

  # Assert
  report_violations "declarations without 'function'" "${violations[@]}"
}

@test "every shell function of cdl.sh carries a documentation header" {
  # Arrange: functions start at column 0; awk functions are indented.

  # Act
  run awk '
    /^function / && previous != "#######################################" {
      print FILENAME ":" FNR ": " $2
    }
    { previous = $0 }
  ' "${CDL_SCRIPT}"

  # Assert
  assert_success
  assert_output ''
}

@test "region markers are balanced in every shell file" {
  # Arrange
  local file
  local -a violations=()

  # Act
  while IFS= read -r file; do
    local verdict
    verdict="$(awk '
      /^[[:space:]]*# region / { depth++ }
      /^[[:space:]]*# endregion/ { if (--depth < 0) { print "endregion without region at line " FNR; exit } }
      END { if (depth > 0) print depth " region(s) left open" }
    ' "${CDL_ROOT}/${file}")"
    if [[ -n ${verdict} ]]; then
      violations+=("${file}: ${verdict}")
    fi
  done < <(shell_files)

  # Assert
  report_violations 'regions' "${violations[@]}"
}

@test "every test follows Arrange-Act-Assert" {
  # Arrange
  local file
  local -a violations=()

  # Act:
  # inside each @test block, and inside each function
  # that bats_test_function registers as a test,
  # the three phase comments appear in order.
  # The first pass collects the registered names (after `-- `),
  # the second checks the bodies.
  while IFS= read -r file; do
    while IFS= read -r test_name; do
      violations+=("${file}: ${test_name}")
    done < <(awk '
      FNR == NR {
        if (match($0, /^[[:space:]]*-- [A-Za-z_][A-Za-z0-9_]*/)) {
          registered = substr($0, RSTART, RLENGTH)
          sub(/^[[:space:]]*-- /, "", registered)
          is_test[registered] = 1
        }
        next
      }
      /^@test / { name = $0; phase = 0; next }
      /^function / {
        candidate = $2
        sub(/\(\).*/, "", candidate)
        if (candidate in is_test) { name = "function " candidate; phase = 0; next }
      }
      name != "" && /^[[:space:]]*# Arrange/ && phase == 0 { phase = 1 }
      name != "" && /^[[:space:]]*# Act/ && phase == 1 { phase = 2 }
      name != "" && /^[[:space:]]*# Assert/ && phase == 2 { phase = 3 }
      name != "" && /^}/ { if (phase != 3) print name; name = "" }
    ' "${CDL_ROOT}/${file}" "${CDL_ROOT}/${file}")
  done < <(shell_files | grep '\.bats$')

  # Assert
  report_violations 'tests without Arrange, Act and Assert in order' "${violations[@]}"
}

# endregion

### End
