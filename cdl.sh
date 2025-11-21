#!/bin/bash

# Name: cdl.sh
# Author: Nikita Neverov (BMTLab)
# Version: 1.0.0
# Date: 2025-11-21
# License: MIT
#
# Description:
#   Convenience helper that combines "cd" and a compact, colored "ls"
#   into a single command. It changes directory and immediately prints
#   a human-friendly listing of the target directory.
#
#   Behavior:
#     - With argument:
#         cdl /path/to/dir
#     - Without args:
#         cdl
#         -> cd "${HOME}" and print a rich listing of $HOME.
#     - With stdin (Pipe):
#         echo /path | cdl
#         -> Reads directory from stdin, changes to it *inside the subshell*,
#            and prints the listing.
#            NOTE: The parent shell remains in the original directory.
#
#   Listing format (Adaptive & Grid):
#     - If GNU ls is detected (Linux standard):
#         Displays a compact listing (Size + Date + Name).
#         Calculates visible length including symlink targets.
#         If contents fit within the terminal width in two columns,
#         splits output; otherwise falls back to a single column.
#     - If BSD ls is detected (macOS standard):
#         Standard "ls -AlhG" output fallback to avoid crashes/parsing errors.
#
# Usage:
#   # In your shell init (e.g., ~/.bashrc):
#   source /path/to/cdl.sh
#
#   # Then, interactively:
#   cdl [<directory>]
#   cdl "$(xclip -o)"       # Recommended: Changes parent directory
#   echo '/some/path' | cdl # List only (see Notes)
#
#   Notes:
#     - PIPE LIMITATION: Since pipelines execute in subshells, using `| cdl`
#       will NOT change your current shell's working directory.
#       It will only show the listing of that target.
#       To change directory using output from another command,
#       use command substitution: cdl "$(command)"
#     - When both an argument and stdin are present, the explicit argument wins.
#     - Only the first non-empty line from stdin is used as the directory.
#     - Surrounding whitespace in the stdin path is trimmed.
#     - If neither an argument nor stdin provide a directory, $HOME is used.
#
# Exit Codes / Return Codes:
#   0: Success.
#   1: CDL_ERR_GENERAL
#      Generic error (e.g., unexpected failure).
#   2: CDL_ERR_CHDIR
#      Directory does not exist or cannot be accessed.
#   3: CDL_ERR_NOT_SOURCED
#      This script was executed directly instead of being sourced.
#
# Disclaimer:
#   This script is provided "as is",
#   without any warranty or guarantee of correctness, performance,
#   or fitness for a particular purpose.
#   Always verify that the resolved target path is what you expect before
#   relying on it in automation or critical workflows.

# Error codes (readonly; safe for repeated sourcing)
# bashsupport disable=BP5001
if [[ -z ${CDL_ERR_GENERAL+x} ]]; then
  readonly CDL_ERR_GENERAL=1
fi
if [[ -z ${CDL_ERR_CHDIR+x} ]]; then
  readonly CDL_ERR_CHDIR=2
fi
if [[ -z ${CDL_ERR_NOT_SOURCED+x} ]]; then
  readonly CDL_ERR_NOT_SOURCED=3
fi

#######################################
# Print a usage/help message.
#
# Outputs:
#   Usage and behavior description to stdout.
#######################################
function __cdl_usage() {
  cat << 'EOF'
cdl - change directory and immediately list its contents (cd + ls)

Description:
  cdl is a small helper that changes into a target directory
  and prints a compact, colored listing.
  It is convenient for interactive use when jumping around the filesystem.

Usage:
  cdl [<directory>]
  cdl "$(xclip -o)"     # Use command substitution to change directory
  echo '/path' | cdl    # List only (see Pipe Limitation below)

Behavior:
  - If a directory argument is provided, it is used as the target directory.
  - If no argument is provided and stdin is not a TTY,
    the first non-empty line from stdin is used as the target directory.
  - If neither argument nor stdin provide a directory, $HOME is used.

Pipe Limitation:
  - When used in a pipe (e.g., `echo ... | cdl`), the directory change
    occurs in a subshell. The parent shell (your terminal) remains in
    the original directory. Use this mode for "peeking" into directories.

Listing format:
  - Adaptive: Tries to use advanced formatting (dirs first, simplified columns).
    It calculates if the content (including long symlinks) fits into two columns.
    If not, it falls back to a standard single-column list.

Return codes:
  0  Success.
  1  CDL_ERR_GENERAL (generic error).
  2  CDL_ERR_CHDIR (directory does not exist or cannot be accessed).
  3  CDL_ERR_NOT_SOURCED (script executed instead of sourced).
EOF
}

#######################################
# Print error and return with code.
#
# Arguments:
#   1: Message text.
#   2: Return code (optional; default: CDL_ERR_GENERAL).
#
# Globals:
#   CDL_ERR_GENERAL
#######################################
function __cdl_error() {
  local -r message="$1"
  local -ir code="${2:-$CDL_ERR_GENERAL}"

  printf 'ERROR: %s\n' "$message" >&2

  return "$code"
}

#######################################
# Read directory path from stdin.
#
# Reads the first non-empty line from stdin
# and trims surrounding whitespace.
#
# Returns:
#   0: If a directory string was read.
#   1: If nothing (non-empty) was read.
#
# Outputs:
#   Prints the directory path to stdout.
#######################################
function __cdl_read_dir_from_stdin() {
  local input_line

  # Loop until a valid line is found or input is exhausted
  while IFS= read -r input_line || [[ -n $input_line ]]; do
    # Trim leading whitespace
    input_line="${input_line#"${input_line%%[![:space:]]*}"}"
    # Trim trailing whitespace
    input_line="${input_line%"${input_line##*[![:space:]]}"}"

    if [[ -n $input_line ]]; then
      printf '%s' "$input_line"
      return 0
    fi
  done

  return 1
}

#######################################
# Print directory listing in a compact, colored format.
#
# This function attempts to use GNU ls features for a cleaner look.
# It uses awk to buffer the output and display it in two columns
# if the terminal width allows AND the content fits
# (accounting for symlinks and visible length).
#
# It automatically degrades to standard `ls` on BSD/macOS systems
# to avoid crashes due to unsupported flags.
#
# Outputs:
#   Formatted listing to stdout.
#######################################
function __cdl_print_listing() {
  # Determine which binary to use.
  # Prefer `gls` (GNU ls on macOS via brew) if available, then standard `ls`.
  local ls_command='ls'
  if command -v gls > /dev/null 2>&1; then
    ls_command='gls'
  fi

  # Check if the chosen binary supports the GNU-specific flags we rely on.
  # We check --group-directories-first. BSD ls will exit > 0.
  local supports_gnu_flags=false
  if command "$ls_command" \
    --group-directories-first \
    --version > /dev/null 2>&1; then
    supports_gnu_flags=true
  fi

  if [[ $supports_gnu_flags == true ]]; then
    # GNU Mode: Rich formatting with awk parsing.
    # We force LC_ALL=C locally for ls to ensure date/number formats
    # match what the awk script expects, regardless of user locale.
    local -x LC_ALL=C

    # Get current terminal width (default to 80 if tput fails)
    local -ir terminal_width_cols=$(tput cols 2> /dev/null || echo 80)

    # shellcheck disable=SC2012
    command "$ls_command" -Alh \
      --group-directories-first \
      --time-style='+%Y-%m-%d %H:%M' \
      --color=always \
      | awk -v width="$terminal_width_cols" '
      # Helper: remove ANSI color codes to calculate visible string length
      function __strip_ansi(s) {
        gsub(/\033\[[0-9;]*[a-zA-Z]/, "", s)
        return s
      }

      BEGIN {
        # Width for size column (standard "4.0K" is 4 chars, so 6-8 is plenty).
        size_width = 8
        count = 0
      }

      # Skip the "total NNN" line if present (standard ls output).
      /^total [0-9.]+[KMGTP]?$/ { next }

      {
        # Fields in `ls -l` (C locale):
        #  1: perms (drwxr-xr-x)
        #  2: links (2)
        #  3: owner (root)
        #  4: group (root)
        #  5: size  (4.0K)
        #  6: date  (YYYY-MM-DD)
        #  7: time  (HH:MM)
        #  8+: filename (possibly with spaces and ANSI colors)

        size = $5
        ts   = $6 " " $7

        # Clear the metadata fields.
        # We do this instead of printing $8 because $8 only captures
        # the first word of the filename.
        # By clearing $1-$7, the "rest of the line" ($0) preserves the full
        # filename (including spaces) and colors.
        $1 = $2 = $3 = $4 = $5 = $6 = $7 = ""

        # Clearing fields leaves the OFS (output field separator, space)
        # at the beginning of the line. We use sub() to strip leading spaces.
        sub(/^ +/, "", $0)

        # Format: SIZE  TIMESTAMP  NAME
        # We store the fully formatted colored string in an array.
        count++
        lines[count] = sprintf("%*s  %s  %s", size_width, size, ts, $0)
      }

      END {
        # If we have no files, exit
        if (count == 0) exit

        # Decision logic for layout.
        # We only use 2 columns if the terminal is reasonably wide (>100)
        # AND if the content actually fits in 2 columns.
        use_two_columns = 0
        gutter = 4

        if (width >= 100) {
          rows = int((count + 1) / 2)
          max_col1_len = 0
          max_col2_len = 0

          # Calculate visible width for the potential Left Column
          for (i = 1; i <= rows; i++) {
            len = length(__strip_ansi(lines[i]))
            if (len > max_col1_len) max_col1_len = len
          }

          # Calculate visible width for the potential Right Column
          for (i = rows + 1; i <= count; i++) {
            len = length(__strip_ansi(lines[i]))
            if (len > max_col2_len) max_col2_len = len
          }

          # Check if they fit side-by-side
          if ((max_col1_len + gutter + max_col2_len) < width) {
            use_two_columns = 1
          }
        }

        if (use_two_columns == 1) {
          # 2-Column Output
          for (i = 1; i <= rows; i++) {
            # Print Left Column
            printf "%s", lines[i]

            # Calculate dynamic padding
            vis_len = length(__strip_ansi(lines[i]))
            pad = max_col1_len - vis_len + gutter
            for (k = 0; k < pad; k++) printf " "

            # Print Right Column (if it exists)
            right_idx = i + rows
            if (right_idx <= count) {
              print lines[right_idx]
            } else {
              print "" # Newline if right column is empty
            }
          }
        } else {
          # Single Column Fallback
          # (Used if terminal is narrow OR if symlinks are too long)
          for (i = 1; i <= count; i++) {
            print lines[i]
          }
        }
      }
    '
  else
    # Fallback Mode (BSD/macOS): Standard listing.
    # We cannot safely parse columns
    # because BSD ls date formats vary by file age.
    # Just print the list so the user sees the files.
    command "$ls_command" -AlhG
  fi
}

#######################################
# Change directory and list contents.
#
# Behavior:
#   - If $1 is '-h' or '--help', prints usage and returns.
#   - Else, if $1 is non-empty, uses it as directory.
#   - Else, if stdin is not a TTY, reads first non-empty line as directory.
#   - Else, falls back to $HOME.
#
# Arguments:
#   1: Optional directory path.
#
# Returns:
#   0: On success.
#   non-zero: On error (see return codes above).
#######################################
function cdl() {
  # Limit word splitting inside this function to newline/tab only
  local IFS=$'\n\t'

  ## Help check
  if [[ ${1-} == '-h' || ${1-} == '--help' ]]; then
    __cdl_usage
    return 0
  fi

  local target_directory=''

  ## 1. Explicit argument wins
  if [[ -n ${1-} ]]; then
    target_directory=$1
  ## 2. Check stdin if no argument provided
  elif [[ ! -t 0 ]]; then
    # Try to read from stdin.
    # If read fails or result is empty, we fall through to default.
    if ! target_directory="$(__cdl_read_dir_from_stdin)" \
      || [[ -z $target_directory ]]; then
      target_directory=''
    fi
  fi

  ## 3. Fall back to $HOME (robust default)
  if [[ -z $target_directory ]]; then
    target_directory="${HOME:-/}"
  fi

  ## Change directory
  # Use `builtin cd` to ensure we don't recursively call a `cd` wrapper
  if ! builtin cd "$target_directory" > /dev/null 2>&1; then
    __cdl_error \
      "Directory does not exist or cannot be accessed: '$target_directory'" \
      "$CDL_ERR_CHDIR" \
      || return "$?"
  fi

  ## Print listing
  __cdl_print_listing
}

# Execution Guard:
# This file must be sourced, not executed!
# If executed as a script, print an error and exit with CDL_ERR_NOT_SOURCED.
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  error_msg='cdl.sh is a shell helper and must be sourced, not executed. '
  error_msg+="Run:  'source $0'"
  __cdl_error "$error_msg" "$CDL_ERR_NOT_SOURCED" \
    || exit "$?"
fi
### End
