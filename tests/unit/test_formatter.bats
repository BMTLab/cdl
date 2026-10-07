#!/usr/bin/env bats

# Name: tests/unit/test_formatter.bats
# Author: Nikita Neverov (BMTLab)
# License: MIT
#
# Description:
#   The formatter that turns `ls -l` lines into the compact listing,
#   fed with canned lines, so every rule is checked
#   independently of the files and the ls on this machine.
#
#   Each test follows the Arrange-Act-Assert pattern.

bats_require_minimum_version 1.11.0

load '../support/test_helper'

function setup() {
  sandbox_setup
}

# region Parsing

@test "a row shows the size, the date and time, and the name" {
  # Arrange
  local -r input="$(ls_file 'README.md' '6')"

  # Act
  run --separate-stderr format_listing 120 <<<"${input}"

  # Assert
  assert_success
  assert_output "$(listing_row '6' 'README.md')"
}

@test "the total line of ls is left out, in any language" {
  # Arrange
  local -r input="$(
    printf 'total 12K\n'
    printf 'итого 12K\n'
    ls_file 'notes.md'
  )"

  # Act
  run --separate-stderr format_listing 120 <<<"${input}"

  # Assert
  assert_success
  assert_output "$(listing_row '12' 'notes.md')"
}

@test "a device file keeps its major and minor numbers as the size" {
  # Arrange
  local -r input="$(ls_line 'crw-rw-rw-' '1, 3' 'null')"

  # Act
  run --separate-stderr format_listing 120 <<<"${input}"

  # Assert
  assert_success
  assert_output "$(listing_row '1, 3' 'null')"
}

@test "an owner or group name with spaces does not shift the columns" {
  # Arrange:
  # directory services can name a group "domain users".
  local -r input="-rw-r--r-- 1 john domain users 12 ${FIXTURE_DATE} report.pdf"

  # Act
  run --separate-stderr format_listing 120 <<<"${input}"

  # Assert
  assert_success
  assert_output "$(listing_row '12' 'report.pdf')"
}

@test "a name keeps its runs of spaces and its leading space" {
  # Arrange
  local -r input="$(ls_file '  two  spaces  inside')"

  # Act
  run --separate-stderr format_listing 120 <<<"${input}"

  # Assert
  assert_success
  assert_output "$(listing_row '12' '  two  spaces  inside')"
}

@test "a symlink keeps its arrow and target" {
  # Arrange
  local -r input="$(ls_line 'lrwxrwxrwx' '9' 'latest -> v2.0/build')"

  # Act
  run --separate-stderr format_listing 120 <<<"${input}"

  # Assert
  assert_success
  assert_output "$(listing_row '9' 'latest -> v2.0/build')"
}

@test "colors around a name pass through unchanged" {
  # Arrange:
  # uutils ls also emits a leading reset and a trailing erase-in-line.
  local -r name=$'\033[0m\033[01;34msrc\033[0m\033[K'
  local -r input="$(ls_dir "${name}")"

  # Act
  run --separate-stderr format_listing 120 <<<"${input}"

  # Assert
  assert_success
  assert_output "$(listing_row '4.0K' "${name}")"
}

@test "a name that looks like the date column stays whole" {
  # Arrange
  local -r name="${FIXTURE_DATE} notes.txt"
  local -r input="$(ls_file "${name}")"

  # Act
  run --separate-stderr format_listing 120 <<<"${input}"

  # Assert
  assert_success
  assert_output "$(listing_row '12' "${name}")"
}

@test "DEL in a name shows as a question mark" {
  # Arrange
  local -r input="$(ls_file $'before\177after')"

  # Act
  run --separate-stderr format_listing 120 <<<"${input}"

  # Assert
  assert_success
  assert_output "$(listing_row '12' 'before?after')"
}

@test "control characters in a name show as question marks" {
  # Arrange:
  # a name that would set the window title, ring the bell,
  # and open a C1 control sequence (U+009B) on the terminal.
  local -r input="$(ls_file $'evil\033]0;pwned\a\302\23331m.txt')"

  # Act
  run --separate-stderr format_listing 120 <<<"${input}"

  # Assert
  assert_success
  assert_output "$(listing_row '12' 'evil?]0;pwned??31m.txt')"
}

@test "a name holding a newline stays on one row, the newline as a question mark" {
  # Arrange:
  # ls prints such a name raw, so it arrives split over two lines.
  local -r input="$(
    ls_file $'first line\nsecond line.txt'
    ls_file 'next.txt'
  )"

  # Act
  run --separate-stderr format_listing 120 0 1 <<<"${input}"

  # Assert
  assert_success
  assert_output "$(
    listing_row '12' 'first line?second line.txt'
    printf '\n'
    listing_row '12' 'next.txt'
  )"
}

@test "an input without entries prints nothing" {
  # Arrange
  local -r input='total 0'

  # Act
  run --separate-stderr format_listing 120 <<<"${input}"

  # Assert
  assert_success
  assert_output ''
}

# endregion

# region Layout

@test "a wide terminal puts the entries side by side" {
  # Arrange
  local -r input="$(
    ls_dir 'src'
    ls_file 'a.txt'
    ls_file 'b.txt'
    ls_file 'c.txt'
  )"

  # Act
  run --separate-stderr format_listing 120 <<<"${input}"

  # Assert
  assert_success
  assert_columns_aligned "${output}"
  assert_fits_width "${output}" 120
}

@test "a single entry on a wide terminal is one row without trailing spaces" {
  # Arrange
  local -r input="$(ls_file 'alone.txt')"

  # Act
  run --separate-stderr format_listing 200 <<<"${input}"

  # Assert
  assert_success
  assert_output "$(listing_row '12' 'alone.txt')"
}

@test "rows that would fill the terminal exactly stay in one column" {
  # Arrange:
  # each row takes 69 cells (8 + 2 + 16 + 2 + a 41-letter name),
  # so two rows side by side take 69 + 4 + 69 = 142 cells;
  # a row as wide as the terminal would wrap on some terminals.
  local -r name="$(printf 'x%.0s' {1..41})"
  local -r input="$(
    ls_file "${name}"
    ls_file "${name}"
  )"

  # Act
  run --separate-stderr format_listing 142 <<<"${input}"

  # Assert
  assert_success
  assert_one_column "${output}"
}

@test "rows with one cell to spare sit side by side" {
  # Arrange: the same 142 cells of rows as above.
  local -r name="$(printf 'x%.0s' {1..41})"
  local -r input="$(
    ls_file "${name}"
    ls_file "${name}"
  )"

  # Act
  run --separate-stderr format_listing 143 <<<"${input}"

  # Assert
  assert_success
  assert_columns_aligned "${output}"
}

@test "rows too wide to sit side by side stay in one column" {
  # Arrange
  local -r long_name="$(printf 'very-long-name-%.0s' {1..6})"
  local -r input="$(
    ls_file 'a.txt'
    ls_file "${long_name}"
  )"

  # Act
  run --separate-stderr format_listing 120 <<<"${input}"

  # Assert
  assert_success
  assert_one_column "${output}"
}

@test "a terminal narrower than a row still lists every entry, one per row" {
  # Arrange:
  # no row of 29 cells fits 20 columns; the terminal wraps each one.
  local -r input="$(for name in a b c; do ls_file "${name}"; done)"

  # Act
  run --separate-stderr format_listing 20 <<<"${input}"

  # Assert
  assert_success
  assert_output "$(listing_row 12 'a')"$'\n'"$(listing_row 12 'b')"$'\n'"$(listing_row 12 'c')"
}

@test "entries fill the columns top to bottom, like ls" {
  # Arrange:
  # five rows of 29 cells fit three columns in 120 cells.
  local -r input="$(for name in 1 2 3 4 5; do ls_file "${name}"; done)"
  local -r expected="$(
    printf '%s    %s    %s\n' "$(listing_row 12 1)" "$(listing_row 12 3)" "$(listing_row 12 5)"
    printf '%s    %s\n' "$(listing_row 12 2)" "$(listing_row 12 4)"
  )"

  # Act
  run --separate-stderr format_listing 120 <<<"${input}"

  # Assert:
  # the last row has no entry in the last column, and no trailing spaces.
  assert_success
  assert_output "${expected}"
}

@test "the second column starts four spaces after the widest left row" {
  # Arrange
  local -r input="$(
    ls_file 'longest-left.txt'
    ls_file 'a'
    ls_file 'right-1'
    ls_file 'right-2'
  )"
  local -r expected="$(
    printf '%s    %s\n' "$(listing_row 12 'longest-left.txt')" "$(listing_row 12 'right-1')"
    printf '%s%19s%s\n' "$(listing_row 12 'a')" '' "$(listing_row 12 'right-2')"
  )"

  # Act
  run --separate-stderr format_listing 120 <<<"${input}"

  # Assert
  assert_success
  assert_output "${expected}"
}

@test "escape sequences take no room in the layout" {
  # Arrange
  local -r input="$(
    ls_dir "$(paint '01;34' 'src')"
    ls_file 'plain-name.txt'
    ls_file "$(paint '01;32' 'run.sh')"
    ls_file 'other.txt'
  )"

  # Act
  run --separate-stderr format_listing 120 <<<"${input}"

  # Assert
  assert_success
  assert_columns_aligned "${output}"
}

#######################################
# Check how many columns twelve short entries get.
#
# Arguments:
#   1: Terminal width.
#   2: Expected columns.
#######################################
function the_grid_takes_as_many_columns_as_fit() {
  local -r width="$1"
  local -r expected="$2"

  # Arrange:
  # every row takes 29 cells, and the gutter 4.
  local -r input="$(for name in a b c d e f g h i j k l; do ls_file "${name}"; done)"

  # Act
  run --separate-stderr format_listing "${width}" <<<"${input}"

  # Assert
  assert_success
  assert_equal "$(grid_columns "${output}")" "${expected}" 'columns'
  assert_fits_width "${output}" "${width}"
}

for __layout in '60|1' '70|2' '120|3' '140|4'; do
  bats_test_function \
    --description "a terminal of ${__layout%%|*} columns gets ${__layout#*|} column(s) of short entries" \
    -- the_grid_takes_as_many_columns_as_fit "${__layout%%|*}" "${__layout#*|}"
done

@test "the grid never leaves its last column empty" {
  # Arrange:
  # nine entries would take three rows in four columns,
  # which would leave the fourth column empty; three columns fill.
  local -r input="$(for name in a b c d e f g h i; do ls_file "${name}"; done)"

  # Act
  run --separate-stderr format_listing 140 <<<"${input}"

  # Assert
  assert_success
  assert_equal "$(grid_columns "${output}")" '3' 'columns'
}

@test "a column limit keeps the grid narrower" {
  # Arrange
  local -r input="$(for name in a b c d e f g h i j k l; do ls_file "${name}"; done)"

  # Act
  run --separate-stderr format_listing 140 0 2 <<<"${input}"

  # Assert
  assert_success
  assert_equal "$(grid_columns "${output}")" '2' 'columns'
}

@test "a column limit wider than the terminal takes only the columns that fit" {
  # Arrange:
  # 120 columns fit three columns of these entries.
  local -r input="$(for name in a b c d e f g h i j k l; do ls_file "${name}"; done)"

  # Act
  run --separate-stderr format_listing 120 0 9 <<<"${input}"

  # Assert
  assert_success
  assert_equal "$(grid_columns "${output}")" '3' 'columns'
  assert_fits_width "${output}" 120
}

@test "a row limit cuts the grid and says how many entries are left" {
  # Arrange:
  # two rows of four columns show eight of the twelve entries.
  local -r input="$(for name in a b c d e f g h i j k l; do ls_file "${name}"; done)"

  # Act
  run --separate-stderr format_listing 140 2 <<<"${input}"

  # Assert
  assert_success
  assert_equal "${#lines[@]}" '3' 'lines'
  assert_equal "${lines[2]}" '… 4 more; -a shows all' 'the last line'
}

@test "the cut note falls back to three dots without UTF-8" {
  # Arrange
  local -r input="$(for name in a b c; do ls_file "${name}"; done)"

  # Act
  LANG=C run --separate-stderr format_listing 40 1 <<<"${input}"

  # Assert
  assert_success
  assert_output_contains '... 2 more; -a shows all'
}

# endregion

# region Sizes

#######################################
# Check that a size in bytes is written like `ls -h`.
#
# Arguments:
#   1: Size in bytes.
#   2: What `ls -h` prints for it.
#######################################
function sizes_read_like_ls_h() {
  local -r bytes="$1"
  local -r expected="$2"

  # Arrange
  local -r input="$(ls_file 'file' "${bytes}")"

  # Act
  run --separate-stderr format_listing 120 <<<"${input}"

  # Assert
  assert_success
  assert_output "$(listing_row "${expected}" 'file')"
}

# Samples: "bytes|ls -h", around the steps of the rounding.
__SIZE_SAMPLES=(
  '0|0'
  '1023|1023'
  '1024|1.0K'
  '1025|1.1K'
  '5000|4.9K'
  '10239|10K'
  '10240|10K'
  '10241|11K'
  '1047552|1023K'
  '1047553|1.0M'
  '1048575|1.0M'
  '1048576|1.0M'
  '3000000|2.9M'
  '1073741824|1.0G'
)

for __sample in "${__SIZE_SAMPLES[@]}"; do
  bats_test_function \
    --description "${__sample%%|*} bytes read as ${__sample#*|}, like ls -h" \
    -- sizes_read_like_ls_h "${__sample%%|*}" "${__sample#*|}"
done

# endregion

# region Header

@test "the header names the directory, its branch, and what it holds" {
  # Arrange
  local -r input="$(
    printf 'total 8\n'
    ls_dir 'src'
    ls_file 'a.txt' 1000
    ls_file 'b.txt' 1048
  )"

  # Act
  run --separate-stderr format_listing 120 0 0 0 '/srv/projects/app' 'main' <<<"${input}"

  # Assert:
  # directories are counted apart, and only files add up their sizes.
  assert_success
  assert_equal "${lines[0]}" '/srv/projects/app · main · 1 dir, 2 files, 2.0K' 'the header'
}

@test "the header leaves out the branch outside a repository" {
  # Arrange
  local -r input="$(ls_file 'a.txt' 12)"

  # Act
  run --separate-stderr format_listing 120 0 0 0 '/tmp' '' <<<"${input}"

  # Assert
  assert_success
  assert_equal "${lines[0]}" '/tmp · 0 dirs, 1 file, 12B' 'the header'
}

@test "the header counts the entries a cut leaves out" {
  # Arrange:
  # two rows of four columns show eight of the twelve entries.
  local -r input="$(for name in a b c d e f g h i j k l; do ls_file "${name}"; done)"

  # Act
  run --separate-stderr format_listing 140 2 0 0 '/srv' '' <<<"${input}"

  # Assert
  assert_success
  assert_equal "${lines[0]}" '/srv · 0 dirs, 12 files, 144B' 'the header'
  assert_equal "${lines[3]}" '… 4 more; -a shows all' 'the last line'
}

@test "an empty directory still gets its header" {
  # Arrange
  local -r input='total 0'

  # Act
  run --separate-stderr format_listing 120 0 0 0 '/srv/empty' '' <<<"${input}"

  # Assert
  assert_success
  assert_output '/srv/empty · 0 dirs, 0 files'
}

@test "a long path in the header is shortened from the left to fit" {
  # Arrange
  local -r input="$(ls_file 'a' 1)"
  local -r path='/one/two/three/four/five/six'

  # Act
  run --separate-stderr format_listing 40 0 0 0 "${path}" '' <<<"${input}"

  # Assert
  assert_success
  assert_equal "${lines[0]}" '…/four/five/six · 0 dirs, 1 file, 1B' 'the header'
  assert_fits_width "${lines[0]}" 40
}

@test "control characters in the directory name show as question marks in the header" {
  # Arrange
  local -r input="$(ls_file 'a' 1)"

  # Act
  run --separate-stderr format_listing 120 0 0 0 $'/tmp/evil\033]0;x\a' '' <<<"${input}"

  # Assert
  assert_success
  assert_equal "${lines[0]}" '/tmp/evil?]0;x? · 0 dirs, 1 file, 1B' 'the header'
}

#######################################
# Check that an escape in a text of the header shows as "?".
#
# Arguments:
#   1: The directory of the header.
#   2: The branch of the header.
#   3: The header expected.
#######################################
function a_crafted_header_text_cannot_color_the_header() {
  local -r path="$1"
  local -r branch="$2"
  local -r expected="$3"

  # Arrange
  local -r input="$(ls_file 'a' 1)"

  # Act
  run --separate-stderr format_listing 120 0 0 0 "${path}" "${branch}" <<<"${input}"

  # Assert
  assert_success
  assert_equal "${lines[0]}" "${expected}" 'the header'
}

bats_test_function \
  --description 'a directory name cannot color the header' \
  -- a_crafted_header_text_cannot_color_the_header \
  $'/tmp/r\033[31med' 'main' '/tmp/r?[31med · main · 0 dirs, 1 file, 1B'
bats_test_function \
  --description 'a crafted HEAD cannot color the header' \
  -- a_crafted_header_text_cannot_color_the_header \
  '/tmp' $'br\033[31manch' '/tmp · br?[31manch · 0 dirs, 1 file, 1B'

@test "the header separators fall back to bars without UTF-8" {
  # Arrange
  local -r input="$(ls_file 'a' 1)"

  # Act
  LANG=C run --separate-stderr format_listing 120 0 0 0 '/tmp' 'main' <<<"${input}"

  # Assert
  assert_success
  assert_equal "${lines[0]}" '/tmp | main | 0 dirs, 1 file, 1B' 'the header'
}

# endregion

# region Mark

@test "the marked entry has the mark in place of the space before its name" {
  # Arrange
  local -r input="$(
    ls_file 'a.txt'
    ls_file 'b.txt'
  )"

  # Act
  run --separate-stderr format_listing 40 0 0 0 '' '' 'b.txt' <<<"${input}"

  # Assert
  assert_success
  assert_output "$(listing_row 12 'a.txt')"$'\n'"$(marked_row 12 'b.txt')"
}

@test "a marked symlink is found by its own name, before the arrow" {
  # Arrange
  local -r input="$(ls_line 'lrwxrwxrwx' 10 'latest -> report.pdf')"

  # Act
  run --separate-stderr format_listing 60 0 0 0 '' '' 'latest' <<<"${input}"

  # Assert
  assert_success
  assert_output "$(marked_row 10 'latest -> report.pdf')"
}

@test "a colored entry is found by its plain name" {
  # Arrange
  local -r painted="$(paint '01;32' 'run.sh')"
  local -r input="$(ls_file "${painted}")"

  # Act
  run --separate-stderr format_listing 60 0 0 0 '' '' 'run.sh' <<<"${input}"

  # Assert
  assert_success
  assert_output "$(marked_row 12 "${painted}")"
}

@test "only the entry of exactly that name is marked" {
  # Arrange:
  # both names hold the marked one.
  local -r input="$(
    ls_file 'notes.md'
    ls_file 'notes.md.bak'
    ls_file 'old-notes.md'
  )"

  # Act
  run --separate-stderr format_listing 40 0 0 0 '' '' 'notes.md' <<<"${input}"

  # Assert
  assert_success
  assert_equal "$(grep -c '❯' <<<"${output}")" '1' 'marked rows'
  assert_equal "${lines[0]}" "$(marked_row 12 'notes.md')" 'the marked row'
}

@test "the mark falls back to > without UTF-8" {
  # Arrange
  local -r input="$(ls_file 'b.txt')"

  # Act
  LANG=C run --separate-stderr format_listing 40 0 0 0 '' '' 'b.txt' <<<"${input}"

  # Assert
  assert_success
  assert_output "$(printf '%8s  %s >%s' 12 "${FIXTURE_DATE}" 'b.txt')"
}

#######################################
# Check which entries a cut listing shows around a mark.
#
# Twelve entries, a to l, in one column of at most four rows.
#
# Arguments:
#   1: The marked entry.
#   2: The lines expected, with "*" for the marked row.
#######################################
function a_cut_listing_shows_the_rows_around_the_mark() {
  local -r mark="$1"
  local -r expected="$2"

  # Arrange
  local -r input="$(for name in a b c d e f g h i j k l; do ls_file "${name}"; done)"

  # Act
  run --separate-stderr format_listing 40 4 0 0 '' '' "${mark}" <<<"${input}"

  # Assert:
  # each row reduced to its name, and the mark to "*".
  assert_success
  assert_equal "$(sed -e 's/^.* ❯/*/' -e 's/^ .* //' <<<"${output}" | paste -sd ' ' -)" \
    "${expected}" 'the lines'
}

# Samples: "marked entry|lines, notes and names, the mark as *".
__MARK_WINDOWS=(
  'b|a *b c d … 8 more; -a shows all'
  'h|… 6 before g *h i … 3 more; -a shows all'
  'l|… 9 before j k *l'
)

for __sample in "${__MARK_WINDOWS[@]}"; do
  bats_test_function \
    --description "a cut listing marked at ${__sample%%|*} shows: ${__sample#*|}" \
    -- a_cut_listing_shows_the_rows_around_the_mark "${__sample%%|*}" "${__sample#*|}"
done

@test "the window around a mark puts it in the middle row of the middle column" {
  # Arrange:
  # thirty entries of 31 cells take three columns in 110 cells;
  # five rows leave four for entries under the line about those before.
  local -a names=()
  local -i number
  for ((number = 10; number < 40; number++)); do
    names+=("n${number}")
  done
  local -r input="$(for name in "${names[@]}"; do ls_file "${name}"; done)"

  # Act
  run --separate-stderr format_listing 110 5 0 0 '' '' 'n29' <<<"${input}"

  # Assert:
  # n24 to n35 are shown, n29 in the second row of the second column.
  assert_success
  assert_equal "${lines[0]}" '… 14 before' 'the first line'
  assert_equal "${lines[2]}" \
    "$(listing_row 12 'n25')    $(marked_row 12 'n29')    $(listing_row 12 'n33')" 'the second row'
  assert_equal "${lines[5]}" '… 4 more; -a shows all' 'the last line'
}

@test "a mark the listing does not hold changes nothing" {
  # Arrange
  local -r input="$(for name in a b c; do ls_file "${name}"; done)"

  # Act
  run --separate-stderr format_listing 40 2 0 0 '' '' 'missing' <<<"${input}"

  # Assert
  assert_success
  assert_output "$(listing_row 12 'a')"$'\n'"$(listing_row 12 'b')"$'\n''… 1 more; -a shows all'
}

# endregion

# region Links

@test "with a link directory, each name links to its file" {
  # Arrange
  export HOSTNAME='box'
  local -r input="$(ls_file 'notes.md')"
  local -r head="$(printf '%8s  %s  ' 12 "${FIXTURE_DATE}")"

  # Act
  run --separate-stderr format_listing 60 0 0 0 '' '' '' '/srv/app' <<<"${input}"

  # Assert
  assert_success
  assert_output "${head}$(hyperlink 'file://box/srv/app/notes.md' 'notes.md')"
}

@test "a symlink links by its own name, its target shown inside the link" {
  # Arrange
  export HOSTNAME='box'
  local -r input="$(ls_line 'lrwxrwxrwx' 9 'latest -> plain.txt')"

  # Act
  run --separate-stderr format_listing 60 0 0 0 '' '' '' '/srv' <<<"${input}"

  # Assert
  assert_success
  assert_output_contains "$(hyperlink 'file://box/srv/latest' 'latest -> plain.txt')"
}

@test "names in the root directory link without a double slash" {
  # Arrange
  export HOSTNAME='box'
  local -r input="$(ls_dir 'etc')"

  # Act
  run --separate-stderr format_listing 60 0 0 0 '' '' '' '/' <<<"${input}"

  # Assert
  assert_success
  assert_output_contains "$(hyperlink 'file://box/etc' 'etc')"
}

@test "a name that holds a newline links to its whole name" {
  # Arrange:
  # ls prints the newline raw, so the name spans two lines.
  export HOSTNAME='box'
  local -r input="$(
    ls_file $'two\nlines.txt'
    ls_file 'after.txt'
  )"

  # Act
  run --separate-stderr format_listing 60 0 0 0 '' '' '' '/srv' <<<"${input}"

  # Assert
  assert_success
  assert_output_contains "$(hyperlink 'file://box/srv/two%0Alines.txt' 'two?lines.txt')"
  assert_output_contains "$(hyperlink 'file://box/srv/after.txt' 'after.txt')"
}

@test "a name holding an escape sequence links to itself" {
  # Arrange:
  # the colors of ls around a name that holds an OSC sequence of its own.
  export HOSTNAME='box'
  local -r input="$(ls_file "$(paint '01;32' $'bad\033]8;;x\ay.txt')")"

  # Act
  run --separate-stderr format_listing 60 0 0 0 '' '' '' '/srv' <<<"${input}"

  # Assert:
  # the URI keeps the bytes of the name; the screen shows them as "?".
  assert_success
  assert_output_contains "$(hyperlink 'file://box/srv/bad%1B%5D8%3B%3Bx%07y.txt' \
    "$(paint '01;32' 'bad?]8;;x?y.txt')")"
}

@test "the header path links to the directory itself" {
  # Arrange
  export HOSTNAME='box'
  local -r input="$(ls_file 'a' 1)"

  # Act
  run --separate-stderr format_listing 60 0 0 0 '/srv/app' '' '' '/srv/app' <<<"${input}"

  # Assert
  assert_success
  assert_equal "${lines[0]}" "$(hyperlink 'file://box/srv/app' '/srv/app') · 0 dirs, 1 file, 1B" \
    'the header'
}

@test "the mark stays outside the link" {
  # Arrange
  export HOSTNAME='box'
  local -r input="$(ls_file 'b.txt')"
  local -r head="$(printf '%8s  %s ❯' 12 "${FIXTURE_DATE}")"

  # Act
  run --separate-stderr format_listing 60 0 0 0 '' '' 'b.txt' '/srv' <<<"${input}"

  # Assert
  assert_success
  assert_output "${head}$(hyperlink 'file://box/srv/b.txt' 'b.txt')"
}

@test "links take no room in the layout" {
  # Arrange
  local -r input="$(
    ls_dir 'src'
    ls_file 'plain-name.txt'
    ls_file 'run.sh'
    ls_file 'other.txt'
  )"

  # Act
  run --separate-stderr format_listing 120 0 0 0 '' '' '' '/srv/app' <<<"${input}"

  # Assert
  assert_success
  assert_columns_aligned "${output}"
  assert_fits_width "${output}" 120
}

#######################################
# Check that a link writes the bytes a URI cannot hold as %XX,
# in the given awk.
#
# Arguments:
#   1: awk implementation (see available_awks).
#######################################
function a_link_percent_encodes_what_a_uri_cannot_hold() {
  local -r awk_name="$1"

  # Arrange:
  # a space, a Cyrillic letter, a CJK character, a percent sign
  # and a control character, which the listing shows as "?".
  use_awk "${awk_name}"
  export HOSTNAME='box'
  local -r input="$(ls_file $'Д 日%\001.txt')"

  # Act
  run --separate-stderr format_listing 60 0 0 0 '' '' '' '/srv/Дир' <<<"${input}"

  # Assert
  assert_success
  assert_output_contains \
    "$(hyperlink 'file://box/srv/%D0%94%D0%B8%D1%80/%D0%94%20%E6%97%A5%25%01.txt' 'Д 日%?.txt')"
}

while IFS= read -r __awk; do
  bats_test_function \
    --description "a link writes what a URI cannot hold as %XX, in ${__awk}" \
    -- a_link_percent_encodes_what_a_uri_cannot_hold "${__awk}"
done < <(available_awks)

# endregion

# region Screen width of names

#######################################
# Check that a name in the left column keeps the columns aligned.
#
# Arguments:
#   1: awk implementation (see available_awks).
#   2: Name to place in the left column.
#######################################
function names_keep_columns_aligned() {
  local -r awk_name="$1"
  local -r name="$2"

  # Arrange
  use_awk "${awk_name}"
  local -r input="$(
    ls_file "${name}"
    ls_file 'a'
    ls_file 'b'
    ls_file 'c'
  )"

  # Act
  run --separate-stderr format_listing 120 <<<"${input}"

  # Assert
  assert_success
  assert_columns_aligned "${output}"
}

# Script samples: "description|name".
__WIDTH_SAMPLES=(
  'Latin|notes.md'
  'Cyrillic|Отчёт за сентябрь'
  'CJK ideographs|日本語ファイル'
  'Hangul|한국어 문서'
  'halfwidth katakana|ｶﾀｶﾅ'
  'fullwidth Latin|ＡＢＣ'
  'emoji|🎉 party'
  $'a combining accent|café'
  'mixed scripts|Отчёт 日本 🎉.txt'
)

while IFS= read -r __awk_name; do
  for __sample in "${__WIDTH_SAMPLES[@]}"; do
    bats_test_function \
      --description "${__sample%%|*} names keep the columns aligned (${__awk_name})" \
      -- names_keep_columns_aligned "${__awk_name}" "${__sample#*|}"
  done
done < <(available_awks)

# endregion

### End
