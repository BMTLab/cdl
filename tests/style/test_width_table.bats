#!/usr/bin/env bats

# Name: tests/style/test_width_table.bats
# Author: Nikita Neverov (BMTLab)
# License: MIT
#
# Description:
#   The width table inside cdl.sh is generated
#   by tools/gen-width-table.py from the Unicode data of Python,
#   so it must match the generator and keep the order
#   that the binary search of the formatter relies on.
#
#   Each test follows the Arrange-Act-Assert pattern.

bats_require_minimum_version 1.11.0

load '../support/test_helper'

# EXIT_UNICODE_MISMATCH of tools/gen-width-table.py:
# the file was generated from another Unicode version than this Python ships.
readonly UNICODE_MISMATCH=52

function setup_file() {
  if ! command -v python3 >/dev/null; then
    skip 'python3 is not installed'
  fi

  # The generator scans all of Unicode, so it runs once per file.
  export GENERATOR="${CDL_ROOT}/tools/gen-width-table.py"
  export GENERATED_BLOCK="${BATS_FILE_TMPDIR}/width-table"
  python3 "${GENERATOR}" >"${GENERATED_BLOCK}"
}

# region Helpers

#######################################
# Print the ranges of the generated table, one per line.
#
# Outputs:
#   "FIRST LAST CELLS" with decimal code points, in table order.
#######################################
function generated_ranges() {
  awk '
    function hex(digits,    value, i) {
      value = 0
      for (i = 1; i <= length(digits); i++)
        value = value * 16 + index("0123456789ABCDEF", substr(digits, i, 1)) - 1
      return value
    }
    /t = t "/ {
      sub(/^[^"]*"/, "")
      sub(/"$/, "")
      count = split($0, tokens, " ")
      for (i = 1; i <= count; i++) {
        split(tokens[i], parts, ":")
        if (split(parts[1], bounds, "-") == 1) bounds[2] = bounds[1]
        print hex(bounds[1]), hex(bounds[2]), parts[2]
      }
    }
  ' "${GENERATED_BLOCK}"
}

#######################################
# Print the cells the generated table gives a code point.
#
# Arguments:
#   1: Code point in hex, e.g. 4E00.
#######################################
function generated_cells() {
  local -r code="$((16#$1))"

  generated_ranges | awk -v code="${code}" '
    $1 <= code && code <= $2 { print $3; found = 1; exit }
    END { if (!found) print 1 }
  '
}

# endregion

# region Agreement

@test "the width table in cdl.sh is what the generator produces" {
  # Arrange: the generator compares its block with the file.

  # Act
  run --separate-stderr python3 "${GENERATOR}" --check "${CDL_SCRIPT}"

  # Assert:
  # another Unicode version than this Python ships makes no verdict.
  if ((status == UNICODE_MISMATCH)); then
    skip "${stderr}"
  fi
  assert_success
}

# endregion

# region Content

@test "the generated ranges ascend without overlapping" {
  # Arrange: the binary search in cdl.sh needs this order.

  # Act
  run generated_ranges

  # Assert
  assert_success
  local -r disorder="$(awk '
    $1 > $2 || $1 <= last { print "range " NR ": " $0 }
    { last = $2 }
  ' <<<"${output}")"
  assert_equal "${disorder}" '' 'ranges out of order'
}

#######################################
# Check the cells the generated table gives one character.
#
# Arguments:
#   1: Code point in hex.
#   2: Expected cells.
#######################################
function character_takes_cells() {
  local -r code="$1"
  local -r expected="$2"

  # Arrange: the generated table is the input.

  # Act
  run generated_cells "${code}"

  # Assert
  assert_success
  assert_output "${expected}"
}

# Samples: "code point|cells|description".
__CELL_SAMPLES=(
  '0041|1|a Latin letter'
  '0416|1|a Cyrillic letter'
  '0301|0|a combining acute accent'
  '05B4|0|a Hebrew point'
  '0E31|0|a Thai vowel sign'
  '00AD|1|the soft hyphen'
  '200D|0|the zero-width joiner'
  '1160|0|a Hangul medial vowel'
  '4E00|2|a CJK ideograph'
  'AC00|2|a Hangul syllable'
  'FF21|2|a fullwidth letter'
  'FF71|1|a halfwidth katakana'
  '1F389|2|an emoji'
)

for __sample in "${__CELL_SAMPLES[@]}"; do
  IFS='|' read -r __code __cells __description <<<"${__sample}"
  bats_test_function \
    --description "${__description} (U+${__code}) takes ${__cells} cell(s)" \
    -- character_takes_cells "${__code}" "${__cells}"
done

# endregion

### End
