#!/usr/bin/env bash

# Name: tests/support/screen.bash
# Author: Nikita Neverov (BMTLab)
# License: MIT
#
# Description:
#   Look at a listing the way a terminal shows it:
#   strip escape sequences, count screen cells,
#   and check how rows line up in columns.
#
#   Cells are counted by tests/support/bin/screen-cells,
#   a separate process and a separate implementation
#   from the width table inside cdl.sh.
#
#   Loaded by tests/support/test_helper.bash.

SCREEN_CELLS="${__CDL_SUPPORT_DIR}/bin/screen-cells"

# region Text

#######################################
# Remove CSI and OSC escape sequences.
#
# Inputs:
#   Text on stdin.
#
# Outputs:
#   The text without escapes to stdout.
#######################################
function strip_escapes() {
  LC_ALL=C sed -E $'s#\033\\[[0-?]*[ -/]*[@-~]##g; s#\033\\][^\a\033]*(\a|\033\\\\)##g'
}

#######################################
# Count the screen cells of one line of text.
#
# Arguments:
#   1: Text; escape sequences take no cells.
#
# Outputs:
#   The number of cells to stdout.
#######################################
function screen_cells() {
  printf '%s\n' "$1" | "${SCREEN_CELLS}"
}

# endregion

# region Columns

# An awk program that finds the date of every entry in a row
# and, for each entry after the first,
# prints its column (mode=column) or the text before it (mode=prefix).
__SCREEN_ENTRY_SCAN='
  {
    rest = $0
    consumed = 0
    column = 0
    while (match(rest, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]/)) {
      column++
      if (column > 1) print (mode == "column" ? column : substr($0, 1, consumed + RSTART - 1))
      consumed += RSTART + RLENGTH - 1
      rest = substr(rest, RSTART + RLENGTH)
    }
  }
'

#######################################
# Print where each entry after the first of a row starts.
#
# An entry is "SIZE  DATE TIME  NAME" with an 8-cell size field,
# so an entry starts 10 cells before its date.
#
# Inputs:
#   The listing on stdin.
#
# Outputs:
#   "COLUMN CELL" per entry after the first of a row:
#   the column of the entry (2, 3, ...) and its first cell.
#######################################
function entry_offsets() {
  local plain
  plain="$(strip_escapes)"

  paste -d ' ' \
    <(awk -v mode=column "${__SCREEN_ENTRY_SCAN}" <<<"${plain}") \
    <(awk -v mode=prefix "${__SCREEN_ENTRY_SCAN}" <<<"${plain}" | "${SCREEN_CELLS}") \
    | awk '{ print $1, $2 - 10 }'
}

#######################################
# Print how many columns a listing has.
#
# Arguments:
#   1: The listing.
#######################################
function grid_columns() {
  local -r listing="$1"

  entry_offsets <<<"${listing}" \
    | awk 'BEGIN { max = 1 } $1 > max { max = $1 } END { print max }'
}

#######################################
# Assert a listing has columns that line up on screen:
# each column starts at one cell in every row.
#
# Arguments:
#   1: The listing.
#######################################
function assert_columns_aligned() {
  local -r listing="$1"
  local offsets
  offsets="$(entry_offsets <<<"${listing}" | sort -u)"

  if [[ -z ${offsets} ]]; then
    __assert_fail 'expected rows with more than one entry'
    return
  fi

  local misaligned
  misaligned="$(awk '{ seen[$1]++ } END { for (c in seen) if (seen[c] > 1) print c }' <<<"${offsets}")"
  if [[ -n ${misaligned} ]]; then
    __assert_fail "column(s) ${misaligned//$'\n'/, } start at different cells: ${offsets//$'\n'/; }"
  fi
}

#######################################
# Assert a listing has one entry per row.
#
# Arguments:
#   1: The listing.
#######################################
function assert_one_column() {
  local -r listing="$1"

  if [[ -n $(entry_offsets <<<"${listing}") ]]; then
    __assert_fail 'expected one entry per row'
  fi
}

#######################################
# Assert every row of a listing is narrower than the terminal.
#
# A row exactly as wide as the terminal
# wraps on some terminals, so it must stay strictly narrower.
#
# Arguments:
#   1: The listing.
#   2: Terminal width in columns.
#######################################
function assert_fits_width() {
  local -r listing="$1"
  local -ir width="$2"
  local -i widest

  widest="$("${SCREEN_CELLS}" <<<"${listing}" | sort -n | tail -n 1)"
  if ((widest >= width)); then
    __assert_fail "the widest row takes ${widest} cells of ${width}"
  fi
}

# endregion

### End
