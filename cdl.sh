#!/usr/bin/env bash

# Name: cdl.sh
# Author: Nikita Neverov (BMTLab)
# Version: 2.0.0
# Date: 2026-10-07
# License: MIT
#
# Description:
#   Interactive helper that combines `cd` and a compact, colored `ls`:
#   it changes the current directory
#   and immediately prints a readable listing of the new one.
#
#   Compatibility:
#     - Source it into bash 3.2+ or zsh 5.0+, on Linux or macOS.
#     - The compact listing needs an ls that speaks GNU options:
#       GNU ls, uutils ls, or Homebrew's gls.
#       With BSD ls (the macOS default) cdl prints `ls -Alh` as is.
#     - Any POSIX awk will do: gawk, mawk, BSD awk or busybox awk.
#
#   Listing format (GNU-compatible ls):
#     - On a terminal, a header line first:
#       the directory, its git branch, read without running git,
#       and how many directories, files and bytes it holds.
#     - One row per entry: SIZE  DATE TIME  NAME,
#       directories first, symlinks with their targets.
#       Sizes read like those of GNU `ls -h`, whatever ls lists them.
#     - Names sort by bytes (uppercase first), whatever the locale:
#       the one order every ls implementation agrees on.
#     - As many columns as fit the terminal, filled top to bottom like ls.
#       Widths are measured in screen cells:
#       escape sequences take none, CJK and emoji take two.
#     - On a terminal, a long listing is cut at its height,
#       with a last line that says how many entries it left out.
#     - A file given to cdl is marked with ❯ (> without UTF-8),
#       and a cut listing moves to show it.
#     - Control characters in names show as '?', like `ls -q`,
#       so a crafted file name cannot drive the terminal.
#     - Colors only on a terminal, and never when NO_COLOR is set.
#     - With colors, names are hyperlinks (OSC 8) to their files,
#       and the header path to the directory.
#
# Usage:
#   # In ~/.bashrc or ~/.zshrc:
#   source /path/to/cdl.sh
#
#   # Then, interactively:
#   cdl [<directory>]
#   cdl "$(xclip -o)"       # Change into the path from the clipboard
#   echo '/some/path' | cdl # Read the directory from a pipe (see Notes)
#
#   # Or make cd itself run cdl, with its options and completion
#   # (set it before sourcing):
#   export CDL_REPLACE_CD=1
#
#   Tab completion for cdl and cdl_list, and for cd when cdl replaces it,
#   comes with sourcing, in bash, and in zsh once compinit has run.
#   zsh plugin managers can load cdl.plugin.zsh instead.
#
#   Notes:
#     - cdl reads the directory from stdin only when stdin is a pipe;
#       a redirected file or a terminal is never read.
#     - In bash, a pipeline runs cdl in a subshell:
#       `echo /path | cdl` prints the listing,
#       but your shell stays where it was.
#       zsh runs the last command of a pipeline in the current shell,
#       so there the directory does change.
#       `cdl "$(command)"` changes directory in both shells.
#     - An explicit operand wins over stdin.
#       From stdin, the first non-blank line is used, trimmed.
#     - With neither, cdl goes to $HOME, like cd.
#     - A file takes cdl to the directory that holds it.
#     - A file:// URI and a leading ~ work too,
#       as they come from a clipboard or a pipe.
#
# Exit Codes / Return Codes:
#   The tens digit names what failed, and the units digit why.
#   A code keeps its value within a major version,
#   and a new reason takes the next free code of its ten,
#   so a script that compares the tens keeps working:
#   `(( $? / 10 == CDL_ERR_CHDIR / 10 ))` holds for every reason
#   a directory could not be entered.
#   0: Success.
#   10: CDL_ERR_USAGE
#       Unknown option, empty directory name,
#       or more than one directory operand.
#   20: CDL_ERR_SETTING
#       A CDL_* setting holds an invalid value.
#   30: CDL_ERR_CHDIR
#       The directory could not be entered,
#       for a reason none of the codes below names.
#   31: CDL_ERR_NOT_FOUND
#       The directory does not exist,
#       or `cdl -` has no previous directory to go back to.
#   32: CDL_ERR_DENIED
#       The directory, or a directory on the way to it,
#       may not be entered.
#   33: CDL_ERR_NOT_DIRECTORY
#       A file stands where the path needs a directory,
#       as in 'notes.md/' or 'notes.md/drafts'.
#   40: CDL_ERR_LIST
#       The directory was entered, but ls could not list it in full
#       (e.g., it is searchable but not readable).
#   50: CDL_ERR_NOT_SOURCED
#       This script was executed instead of being sourced,
#       or sourced into a shell other than bash or zsh.
#
# Disclaimer:
#   This script is provided "as is",
#   without any warranty or guarantee of correctness, performance,
#   or fitness for a particular purpose.
#   Always verify that the resolved target path is what you expect
#   before relying on it in automation or critical workflows.

# region Version and error codes

# zsh plugin managers source files from inside functions,
# where creating a global warns under the WARN_CREATE_GLOBAL option;
# so in zsh each region declares its globals before it sets them.
# This region is POSIX code, read by sh too (see "Shell check").
# shellcheck disable=SC2292
if [ -n "${ZSH_VERSION-}" ]; then
  typeset -g CDL_VERSION CDL_ERR_USAGE CDL_ERR_SETTING CDL_ERR_CHDIR \
    CDL_ERR_NOT_FOUND CDL_ERR_DENIED CDL_ERR_NOT_DIRECTORY \
    CDL_ERR_LIST CDL_ERR_NOT_SOURCED
fi

# The version, for `cdl --version`.
# A plain assignment, unlike the codes below:
# sourcing a newer cdl.sh in the same shell must replace it.
CDL_VERSION='2.0.0'

# Each code is assigned only when unset,
# so sourcing the file again (e.g. reloading ~/.bashrc)
# keeps the values instead of failing on `readonly`.
# The POSIX `:=` form also runs in sh, for the shell check below.
# A multiple of ten names a category, what failed;
# the codes after it in its ten, the reasons why (see the header).
# bashsupport disable=BP5001
: "${CDL_ERR_USAGE:=10}"
: "${CDL_ERR_SETTING:=20}"
: "${CDL_ERR_CHDIR:=30}"
: "${CDL_ERR_NOT_FOUND:=31}"
: "${CDL_ERR_DENIED:=32}"
: "${CDL_ERR_NOT_DIRECTORY:=33}"
: "${CDL_ERR_LIST:=40}"
: "${CDL_ERR_NOT_SOURCED:=50}"

# endregion

# region Shell check

# Only bash and zsh can run the rest of the file.
# A POSIX sh (dash, for example) stops here with a clear message
# instead of tripping over the first `[[` below.
# SC2292: `[[` may not exist in this shell yet.
# SC2317: `exit` runs when the file is executed rather than sourced.
# shellcheck disable=SC2292,SC2317
if [ -z "${BASH_VERSION-}${ZSH_VERSION-}" ]; then
  printf 'cdl: cdl.sh must be sourced into bash or zsh\n' >&2
  return "${CDL_ERR_NOT_SOURCED}" 2>/dev/null || exit "${CDL_ERR_NOT_SOURCED}"
fi

# zsh needs `-g`: plugin managers source files from inside functions,
# where a bare `readonly` would create a local instead.
if [[ -n ${ZSH_VERSION-} ]]; then
  typeset -gr CDL_ERR_USAGE CDL_ERR_SETTING CDL_ERR_CHDIR \
    CDL_ERR_NOT_FOUND CDL_ERR_DENIED CDL_ERR_NOT_DIRECTORY \
    CDL_ERR_LIST CDL_ERR_NOT_SOURCED
else
  readonly CDL_ERR_USAGE CDL_ERR_SETTING CDL_ERR_CHDIR \
    CDL_ERR_NOT_FOUND CDL_ERR_DENIED CDL_ERR_NOT_DIRECTORY \
    CDL_ERR_LIST CDL_ERR_NOT_SOURCED
fi

# endregion

# region Session state

if [[ -n ${ZSH_VERSION-} ]]; then
  typeset -g __cdl_ls_bin __cdl_ls_is_gnu __cdl_ls_color_flag __cdl_awk_bin \
    __cdl_setting_color __cdl_setting_hidden __cdl_setting_width \
    __cdl_setting_max_rows __cdl_setting_max_columns __cdl_setting_header \
    __cdl_setting_git __cdl_setting_links __cdl_setting_replace_cd
fi

# What the probes in "Tool detection" learned about ls and awk,
# cached for the shell session.
# Sourcing the file again, e.g. after an update, starts fresh probes.
__cdl_ls_bin=''
__cdl_ls_is_gnu=0
__cdl_ls_color_flag=''
__cdl_awk_bin=''

# The settings of the call in progress,
# which __cdl_read_settings fills on every call (see "Settings").
__cdl_setting_color=''
__cdl_setting_hidden=''
__cdl_setting_width=''
__cdl_setting_max_rows=''
__cdl_setting_max_columns=''
__cdl_setting_header=''
__cdl_setting_git=''
__cdl_setting_links=''
__cdl_setting_replace_cd=''

# endregion

# region Messages

#######################################
# Print the usage and behavior description.
#
# Outputs:
#   The help text to stdout.
#######################################
function __cdl_usage() {
  cat <<'EOF'
Usage: cdl [-h] [-V] [-a] [-1] [-L | -P] [--] [DIRECTORY]

Change into DIRECTORY and list its contents: cd and ls in one step.

Arguments:
  DIRECTORY    Where to go; '-' means the previous directory ($OLDPWD).
               Without it, cdl reads the path from a pipe,
               and otherwise goes to $HOME, like cd.
               A file takes cdl to its directory, where the listing marks it.
               A file:// URI and a leading ~ work too, as pasted or piped in.

Options:
  -h, --help        Show this help.
  -V, --version     Show the version.
  -a, --all         Show every entry: no cut at the terminal height.
  -1, --one-column  One entry per row.
  -L, -P            As with cd: follow symbolic links as written (the default),
                    or resolve them to the physical directory (also for `-`);
                    the last of the two wins.
  --                End of options: the next word is the directory,
                    even when it starts with '-'.
  Each option is a word of its own, and comes before the directory.

Settings (environment variables):
  CDL_COLOR        auto (default), always or never.
                   auto colors a terminal unless NO_COLOR is set;
                   always and never win over NO_COLOR.
  CDL_HIDDEN       1 (default) lists hidden entries; 0 leaves them out.
  CDL_WIDTH        Terminal width in columns. Empty, the default,
                   means COLUMNS, then tput, then 80.
  CDL_MAX_ROWS     Rows before a listing is cut; 0 never cuts.
                   Empty, the default, means the terminal height,
                   and no cut when the listing goes to a file or a pipe.
  CDL_MAX_COLUMNS  Most columns side by side; empty or 0: as many as fit.
  CDL_HEADER       auto (default), always or never.
                   The header line names the directory and its git branch,
                   and counts its directories, files and bytes;
                   auto shows it on a terminal only.
  CDL_GIT          1 (default) shows the git branch in the header; 0 hides it.
  CDL_LINKS        auto (default), always or never.
                   auto makes names hyperlinks to their files
                   on a terminal with colors, but not on the Linux console.
  CDL_REPLACE_CD   1 makes cd run cdl on a terminal, with its options,
                   files and completion; set it before sourcing cdl.sh.
                   0 (default) keeps the shell's own cd.
  An empty value counts as unset.
  An invalid value fails with CDL_ERR_SETTING before cdl moves.

Examples:
  cdl ~/projects        Change into ~/projects and list it.
  cdl -                 Go back to the previous directory.
  cdl "$(xclip -o)"     Change into the path held in the clipboard.
  cdl ~/notes/todo.md   Change into ~/notes, with todo.md marked.
  echo /var/log | cdl   List /var/log (see Pipes).
  cdl -a /usr/bin       List all of /usr/bin, however long.
  cdl_list              List the current directory without moving;
                        it takes -a and -1 too.

Pipes:
  cdl uses the first non-blank line of a pipe as the directory.
  A redirected file or a terminal on stdin is never read.
  bash runs a piped cdl in a subshell, so it only shows the listing
  and your shell stays where it was; zsh changes the directory too.

Listing:
  With GNU ls, uutils ls or gls: SIZE, DATE TIME and NAME per entry,
  directories first, in as many columns as fit the terminal.
  A terminal gets a header line first (see CDL_HEADER),
  and cuts a long listing at its height (see -a);
  a file given to cdl is marked, and the cut keeps it in view.
  With BSD ls: the plain `ls -Alh` output.
  Colors follow CDL_COLOR, and links to the files CDL_LINKS (see Settings).

Return codes (the tens digit names what failed, the units digit why):
  0   Success.
  10  CDL_ERR_USAGE          Bad option or directory operand.
  20  CDL_ERR_SETTING        A CDL_* setting holds an invalid value.
  30  CDL_ERR_CHDIR          The directory could not be entered.
  31  CDL_ERR_NOT_FOUND      No such directory, or no previous one for '-'.
  32  CDL_ERR_DENIED         The directory, or one above it, may not be entered.
  33  CDL_ERR_NOT_DIRECTORY  A file stands where the path needs a directory.
  40  CDL_ERR_LIST           The directory was entered but could not be listed.
  50  CDL_ERR_NOT_SOURCED    cdl.sh was not sourced into bash or zsh.
  $(( $? / 10 )) is 3 for every reason a directory could not be entered.
EOF
}

#######################################
# Print an error message and return with a code.
#
# Arguments:
#   1: Message text.
#   2: Return code, one of the CDL_ERR_* codes.
#
# Outputs:
#   "cdl: <message>" to stderr.
#
# Returns:
#   The given code.
#######################################
function __cdl_error() {
  local -r message="$1"
  local -ir code="$2"

  printf 'cdl: %s\n' "${message}" >&2

  return "${code}"
}

# endregion

# region Settings

# Settings come from the environment, read once per call
# by __cdl_read_settings; nothing else reads CDL_* directly,
# but the cd of CDL_REPLACE_CD, which reads it alone (see "Replacing cd").
# A flag wins over a setting, and a setting wins over the default.
# An empty value counts as unset, as with NO_COLOR.
# An invalid value is an error (CDL_ERR_SETTING), not a silent default,
# so that a typo in an rc file shows at once.
#
#   Variable    Values                  Default  Effect
#   CDL_COLOR   auto, always, never     auto     Colors: on a terminal for auto,
#                                                unless NO_COLOR is set.
#   CDL_HIDDEN  0, 1                    1        List hidden entries.
#   CDL_WIDTH   a positive number       empty    Width of the terminal;
#                                                empty: COLUMNS, tput, 80.
#   CDL_MAX_ROWS     a number           empty    Rows before a listing is cut
#                                                (-a lifts it); 0: never;
#                                                empty: the terminal height,
#                                                and never off a terminal.
#   CDL_MAX_COLUMNS  a number           empty    Most columns side by side
#                                                (-1 sets 1); empty or 0:
#                                                as many as fit.
#   CDL_HEADER  auto, always, never     auto     A line with the directory,
#                                                its git branch and a summary;
#                                                auto: on a terminal.
#   CDL_GIT     0, 1                    1        The git branch in the header.
#   CDL_LINKS   auto, always, never     auto     Hyperlinks on the names;
#                                                auto: on a colored terminal,
#                                                not the Linux console.
#   CDL_REPLACE_CD  0, 1                0        1: cd runs cdl
#                                                on a terminal,
#                                                if set before sourcing.

#######################################
# Read and check every setting of cdl.
#
# A variable left unset costs nothing but its default:
# only a value the user set is checked.
#
# Globals:
#   CDL_COLOR, CDL_HIDDEN, CDL_WIDTH, CDL_MAX_ROWS, CDL_MAX_COLUMNS,
#   CDL_HEADER, CDL_GIT, CDL_LINKS, CDL_REPLACE_CD (read);
#   __cdl_setting_color, __cdl_setting_hidden, __cdl_setting_width,
#   __cdl_setting_max_rows, __cdl_setting_max_columns,
#   __cdl_setting_header, __cdl_setting_git, __cdl_setting_links,
#   __cdl_setting_replace_cd (write).
#
# Returns:
#   0 on success; CDL_ERR_SETTING for an invalid value.
#######################################
function __cdl_read_settings() {
  __cdl_setting_color="${CDL_COLOR:-auto}"
  __cdl_setting_hidden="${CDL_HIDDEN:-1}"
  __cdl_setting_width="${CDL_WIDTH-}"
  __cdl_setting_max_rows="${CDL_MAX_ROWS-}"
  __cdl_setting_max_columns="${CDL_MAX_COLUMNS:-0}"
  __cdl_setting_header="${CDL_HEADER:-auto}"
  __cdl_setting_git="${CDL_GIT:-1}"
  __cdl_setting_links="${CDL_LINKS:-auto}"
  __cdl_setting_replace_cd="${CDL_REPLACE_CD:-0}"

  if [[ -n ${CDL_COLOR-} ]]; then
    __cdl_check_choice 'CDL_COLOR' "${CDL_COLOR}" 'auto' 'always' 'never' || return
  fi
  if [[ -n ${CDL_HIDDEN-} ]]; then
    __cdl_check_choice 'CDL_HIDDEN' "${CDL_HIDDEN}" 0 1 || return
  fi
  if [[ -n ${CDL_WIDTH-} ]]; then
    __cdl_check_number 'CDL_WIDTH' "${CDL_WIDTH}" 1 || return
  fi
  if [[ -n ${CDL_MAX_ROWS-} ]]; then
    __cdl_check_number 'CDL_MAX_ROWS' "${CDL_MAX_ROWS}" 0 || return
  fi
  if [[ -n ${CDL_MAX_COLUMNS-} ]]; then
    __cdl_check_number 'CDL_MAX_COLUMNS' "${CDL_MAX_COLUMNS}" 0 || return
  fi
  if [[ -n ${CDL_HEADER-} ]]; then
    __cdl_check_choice 'CDL_HEADER' "${CDL_HEADER}" 'auto' 'always' 'never' || return
  fi
  if [[ -n ${CDL_GIT-} ]]; then
    __cdl_check_choice 'CDL_GIT' "${CDL_GIT}" 0 1 || return
  fi
  if [[ -n ${CDL_LINKS-} ]]; then
    __cdl_check_choice 'CDL_LINKS' "${CDL_LINKS}" 'auto' 'always' 'never' || return
  fi
  if [[ -n ${CDL_REPLACE_CD-} ]]; then
    __cdl_check_choice 'CDL_REPLACE_CD' "${CDL_REPLACE_CD}" 0 1 || return
  fi
}

#######################################
# Apply the listing options, which win over the settings.
#
# Arguments:
#   $@: Options: -a or --all, -1 or --one-column.
#
# Globals:
#   __cdl_setting_max_rows, __cdl_setting_max_columns (write).
#
# Returns:
#   0 on success; CDL_ERR_USAGE for anything else.
#######################################
function __cdl_apply_listing_options() {
  local option

  for option in "$@"; do
    case ${option} in
      -a | --all) __cdl_setting_max_rows=0 ;;
      -1 | --one-column) __cdl_setting_max_columns=1 ;;
      -?*)
        __cdl_error "Unknown option: '${option}' (see 'cdl --help')" \
          "${CDL_ERR_USAGE}" || return
        ;;
      *)
        __cdl_error "Unexpected argument: '${option}' (see 'cdl --help')" \
          "${CDL_ERR_USAGE}" || return
        ;;
    esac
  done
}

#######################################
# Check a setting that takes one of a few words.
#
# Arguments:
#   1: Name of the variable, for the error message.
#   2: Its value.
#   $@: The accepted words.
#
# Returns:
#   0 for an accepted word; CDL_ERR_SETTING for any other.
#######################################
function __cdl_check_choice() {
  local -r name="$1"
  local -r value="$2"
  shift 2

  local choice
  for choice in "$@"; do
    if [[ ${value} == "${choice}" ]]; then
      return 0
    fi
  done

  __cdl_join_choices "$@"
  __cdl_error "${name}: not ${REPLY}: '${value}'" "${CDL_ERR_SETTING}"
}

#######################################
# Check a setting that takes a whole number.
#
# Arguments:
#   1: Name of the variable, for the error message.
#   2: Its value.
#   3: The smallest number accepted: 0 or 1.
#
# Returns:
#   0 for a number in range; CDL_ERR_SETTING for anything else.
#######################################
function __cdl_check_number() {
  local -r name="$1"
  local -r value="$2"
  local -ir minimum="$3"

  if __cdl_is_positive_integer "${value}"; then
    return 0
  fi
  if ((minimum == 0)) && [[ ${value} == 0 ]]; then
    return 0
  fi

  if ((minimum == 0)); then
    __cdl_error "${name}: not a number: '${value}'" "${CDL_ERR_SETTING}"
  else
    __cdl_error "${name}: not a positive number: '${value}'" "${CDL_ERR_SETTING}"
  fi
}

#######################################
# Join words the way a sentence lists them: "a, b or c".
#
# Arguments:
#   $@: The words.
#
# Outputs:
#   Sets REPLY to the list.
#######################################
function __cdl_join_choices() {
  REPLY="$1"
  shift

  while (($# > 1)); do
    REPLY="${REPLY}, $1"
    shift
  done
  if (($# == 1)); then
    REPLY="${REPLY} or $1"
  fi
}

# endregion

# region Input

#######################################
# Trim leading and trailing whitespace.
#
# Arguments:
#   1: Text to trim.
#
# Outputs:
#   Sets REPLY to the trimmed text.
#######################################
function __cdl_trim() {
  local text="$1"

  text="${text#"${text%%[![:space:]]*}"}"
  text="${text%"${text##*[![:space:]]}"}"

  REPLY="${text}"
}

#######################################
# Report whether stdin is a pipe.
#
# A pipe means the caller sent a path on purpose (`echo /path | cdl`);
# a terminal, /dev/null or a file is what cdl merely inherited,
# for example from a `while read` loop.
#
# Returns:
#   0 if stdin is a pipe; 1 otherwise.
#######################################
function __cdl_stdin_is_pipe() {
  [[ -p /dev/stdin ]]
}

#######################################
# Read the target directory from stdin.
#
# Takes the first non-blank line and trims its surrounding whitespace.
#
# Outputs:
#   Sets REPLY to the directory.
#
# Returns:
#   0 if a directory was read;
#   1 if stdin held only blank lines.
#######################################
function __cdl_read_stdin_target() {
  local line

  while IFS= read -r line || [[ -n ${line} ]]; do
    __cdl_trim "${line}"
    if [[ -n ${REPLY} ]]; then
      return 0
    fi
  done

  return 1
}

#######################################
# Check the operands left after the options.
#
# Arguments:
#   $@: The operands: none, or one directory.
#
# Returns:
#   0 when they are fine;
#   CDL_ERR_USAGE for more than one, or for an empty one.
#######################################
function __cdl_check_operands() {
  if (($# > 1)) && [[ $2 == -?* ]]; then
    __cdl_error "Options go before the directory: '$2'" "${CDL_ERR_USAGE}" \
      || return "$?"
  fi
  if (($# > 1)); then
    __cdl_error "Too many arguments: expected one directory, got $#" \
      "${CDL_ERR_USAGE}" || return "$?"
  fi

  # An empty operand mostly comes from an empty substitution,
  # such as `cdl "$(xclip -o)"` with nothing in the clipboard,
  # where a jump to HOME would surprise.
  if (($# == 1)) && [[ -z $1 ]]; then
    __cdl_error 'Empty directory name' "${CDL_ERR_USAGE}" || return "$?"
  fi
}

# endregion

# region Paths

#######################################
# Turn the target as given into a path for cd.
#
# Paths often arrive pasted or piped, where the shell expands nothing:
# a file:// URI, as file managers copy them, loses its scheme
# and its percent escapes, and a leading ~ becomes HOME,
# unless a path spelled that way exists.
#
# Arguments:
#   1: Target as given.
#
# Outputs:
#   Sets REPLY to the path.
#######################################
function __cdl_expand_target() {
  local target="$1"

  case ${target} in
    'file:///'* | 'file://localhost/'*)
      __cdl_file_uri_path "${target}"
      target="${REPLY}"
      ;;
  esac

  REPLY="${target}"
  # shellcheck disable=SC2088 # the ~ the shell left alone is the point
  if [[ ${target} == '~' || ${target} == '~/'* ]] \
    && [[ -n ${HOME-} && ! -e ${target} ]]; then
    REPLY="${HOME}${target#'~'}"
  fi
}

#######################################
# Write the local path of a file:// URI.
#
# Arguments:
#   1: The URI, with an empty host or localhost.
#
# Outputs:
#   Sets REPLY to the path, its percent escapes decoded:
#   "file:///tmp/My%20Files" gives "/tmp/My Files".
#######################################
function __cdl_file_uri_path() {
  local uri_path="${1#file://}"
  uri_path="/${uri_path#*/}"

  __cdl_percent_decode "${uri_path}"
}

#######################################
# Decode the %XX escapes of a URI into bytes.
#
# A percent sign without two hex digits after it stays as it is,
# and so does %00: no name holds a NUL byte,
# which bash would drop and zsh would keep.
#
# Arguments:
#   1: Text with escapes.
#
# Outputs:
#   Sets REPLY to the decoded text.
#######################################
function __cdl_percent_decode() {
  local rest="$1"
  local decoded='' hex byte

  while [[ ${rest} == *%* ]]; do
    decoded="${decoded}${rest%%\%*}"
    rest="${rest#*%}"
    hex="${rest:0:2}"
    if [[ ${hex} != [0-9A-Fa-f][0-9A-Fa-f] || ${hex} == 00 ]]; then
      decoded="${decoded}%"
      continue
    fi

    # $'\xHH' makes a byte of hex digits without a fork
    # in bash 3.2 and zsh 5.0 alike, which lack `printf -v`;
    # eval sees nothing else, as the two digits are checked above.
    eval "byte=\$'\\x${hex}'"
    decoded="${decoded}${byte}"
    rest="${rest:2}"
  done

  REPLY="${decoded}${rest}"
}

# endregion

# region Navigation

#######################################
# Resolve the directory cdl should change into.
#
# An operand wins; without one, a path piped into cdl;
# without either, $HOME (or / if HOME is unset).
#
# Arguments:
#   1: Directory operand (may be empty).
#
# Outputs:
#   Sets REPLY to the target directory.
#######################################
function __cdl_resolve_target() {
  local -r operand="$1"

  if [[ -n ${operand} ]]; then
    REPLY="${operand}"
    return 0
  fi

  if __cdl_stdin_is_pipe && __cdl_read_stdin_target; then
    return 0
  fi

  REPLY="${HOME:-/}"
}

#######################################
# Enter the directory the target names, as cd would;
# if cd refuses a file, enter the directory that holds it.
#
# A file, a device, a symlink to either or a broken symlink
# stays in its place: cdl enters the directory that holds it,
# or stays when that is the current one,
# and the listing marks its name.
#
# Arguments:
#   1: Target ('-' means $OLDPWD, as with cd).
#   2: Option for cd: -L, -P, or empty.
#
# Outputs:
#   Sets REPLY to the name the listing marks, or to '' for a directory.
#
# Returns:
#   0 on success; the code of __cdl_diagnose_chdir_failure
#   if the directory cannot be entered.
#######################################
function __cdl_enter() {
  local -r target="$1"
  local -r option="$2"

  if __cdl_change_directory "${target}" "${option}"; then
    REPLY=''
    return 0
  fi
  if ! __cdl_names_a_file "${target}"; then
    __cdl_report_chdir_failure "${target}"
    return
  fi

  __cdl_holding_directory "${target}"
  local -r directory="${REPLY}"
  if [[ -n ${directory} ]] && ! __cdl_change_directory "${directory}" "${option}"; then
    __cdl_report_chdir_failure "${directory}"
    return
  fi

  REPLY="${target##*/}"
}

#######################################
# Report whether the target names an entry that is not a directory:
# a file, a device, or a symlink that does not lead to a directory,
# broken ones included.
#
# Arguments:
#   1: Target.
#
# Returns:
#   0 for such an entry; 1 otherwise, and always for '-'.
#######################################
function __cdl_names_a_file() {
  local -r target="$1"

  if [[ ${target} == '-' || -d ${target} ]]; then
    return 1
  fi

  [[ -e ${target} || -L ${target} ]]
}

#######################################
# Write the directory that holds an entry, ready for cd.
#
# A relative directory gets a leading ./,
# so CDPATH, which cd searches for relative names,
# cannot send cdl to another directory of the same name.
#
# Arguments:
#   1: Path of the entry.
#
# Outputs:
#   Sets REPLY to the directory, or to '' for the current one.
#######################################
function __cdl_holding_directory() {
  local -r entry_path="$1"

  if [[ ${entry_path} != */* ]]; then
    REPLY=''
    return 0
  fi

  REPLY="${entry_path%/*}"
  case ${REPLY} in
    '') REPLY='/' ;;
    '.') REPLY='' ;;
    /* | ./* | .. | ../*) ;;
    *) REPLY="./${REPLY}" ;;
  esac
}

#######################################
# Find out why cd could not enter a target, as cd itself would put it.
#
# cdl hides the error of cd, so the test operators stand in for it.
# A path is judged by its nearest part that exists:
# the target, or the directory or file where the path breaks off;
# and by the part right below that one, which does not exist:
#
#   Nearest part that exists         Reason, code, e.g.
#   a file                           Not a directory, CDL_ERR_NOT_DIRECTORY:
#                                    'notes.md/drafts', 'notes.md/'
#   a directory that may not be      Permission denied, CDL_ERR_DENIED:
#   entered                          '/root/secret', a locked target
#   a directory, below it a broken   No such file or directory,
#   symlink                          CDL_ERR_NOT_FOUND: 'gone/inner'
#   a directory, below it nothing    No such file or directory,
#                                    CDL_ERR_NOT_FOUND: 'missing'
#   the target, a directory cd       Cannot change directory,
#   refused all the same             CDL_ERR_CHDIR
#
# The reason names the part to blame when that is not the target.
#
# Arguments:
#   1: Target that cd rejected ('-' stands for $OLDPWD).
#
# Outputs:
#   Sets REPLY to the reason, quoting the path.
#
# Returns:
#   The code of the reason, from the table above;
#   CDL_ERR_NOT_FOUND for `-` without OLDPWD.
#######################################
function __cdl_diagnose_chdir_failure() {
  local target="$1"

  if [[ ${target} == '-' && -z ${OLDPWD-} ]]; then
    REPLY='No previous directory: OLDPWD is not set'
    return "${CDL_ERR_NOT_FOUND}"
  fi
  if [[ ${target} == '-' ]]; then
    target="${OLDPWD}"
  fi

  # Trailing slashes come off first: they hide a file from the tests,
  # where cd sees the file and calls it not a directory.
  local bare="${target%"${target##*[!/]}"}"
  bare="${bare:-/}"
  __cdl_nearest_existing_part "${bare}"
  local -r part="${REPLY}"

  if [[ ! -d ${part} ]]; then
    REPLY="Not a directory: '${target}'"
    __cdl_blame_part "${part}" "${bare}" 'is a file'
    return "${CDL_ERR_NOT_DIRECTORY}"
  fi
  if [[ ! -x ${part} ]]; then
    REPLY="Permission denied: '${target}'"
    __cdl_blame_part "${part}" "${bare}" 'may not be entered'
    return "${CDL_ERR_DENIED}"
  fi
  if [[ ${part} == "${bare}" ]]; then
    REPLY="Cannot change directory: '${target}'"
    return "${CDL_ERR_CHDIR}"
  fi

  __cdl_part_below "${part}" "${bare}"
  local -r below="${REPLY}"
  REPLY="No such file or directory: '${target}'"
  if [[ -L ${below} ]]; then
    __cdl_blame_part "${below}" "${bare}" 'is a broken symlink'
  fi
  return "${CDL_ERR_NOT_FOUND}"
}

#######################################
# Find the nearest part of a path that exists, from its end up.
#
# Arguments:
#   1: Path, without trailing slashes.
#
# Outputs:
#   Sets REPLY to the path itself, or the part of it that exists:
#   at the shortest, '/' for an absolute path and '.' for a relative one.
#######################################
function __cdl_nearest_existing_part() {
  REPLY="$1"

  while [[ ! -e ${REPLY} && ${REPLY} != '/' && ${REPLY} != '.' ]]; do
    case ${REPLY} in
      */*) REPLY="${REPLY%/*}" ;;
      *) REPLY='.' ;;
    esac
    REPLY="${REPLY:-/}"
  done
}

#######################################
# Find the part of a path one step below another part of it.
#
# Arguments:
#   1: A part of the path: the path cut after a slash, '/' or '.'.
#   2: The path, without trailing slashes.
#
# Outputs:
#   Sets REPLY to the part with the next name of the path added:
#   'a/b' below 'a' in 'a/b/c', '/a' below '/', 'a' below '.'.
#######################################
function __cdl_part_below() {
  local -r part="$1"
  local -r whole="$2"

  local rest="${whole}"
  if [[ ${part} == '/' ]]; then
    rest="${whole#/}"
  elif [[ ${part} != '.' ]]; then
    rest="${whole#"${part}"/}"
  fi

  case ${part} in
    '.') REPLY="${rest%%/*}" ;;
    '/') REPLY="/${rest%%/*}" ;;
    *) REPLY="${part}/${rest%%/*}" ;;
  esac
}

#######################################
# Add the part of a path to blame to the reason in REPLY,
# unless that part is the whole path.
#
# Arguments:
#   1: The part to blame.
#   2: The whole path, without trailing slashes.
#   3: What is wrong with the part, as words that follow its name.
#
# Outputs:
#   Appends " ('PART' WORDS)" to REPLY.
#######################################
function __cdl_blame_part() {
  local -r part="$1"
  local -r whole="$2"
  local -r words="$3"

  if [[ ${part} != "${whole}" ]]; then
    REPLY="${REPLY} ('${part}' ${words})"
  fi
}

#######################################
# Change the current directory, quietly.
#
# Arguments:
#   1: Target directory ('-' means $OLDPWD, as with cd).
#   2: Option for cd: -L, -P, or empty.
#
# Returns:
#   0 on success; the status of cd otherwise.
#######################################
function __cdl_change_directory() {
  local -r target="$1"
  local -r option="$2"

  # `builtin` bypasses any cd wrapper the user has defined,
  # `--` keeps a leading dash from being read as an option,
  # and the redirect hides the path that cd echoes
  # for `cd -` and for CDPATH matches,
  # as well as its own error, which cdl words better.
  # The +-expansion leaves out an empty option.
  builtin cd ${option:+"${option}"} -- "${target}" >/dev/null 2>&1 || return
}

#######################################
# Report a directory that could not be entered.
#
# Arguments:
#   1: Target that cd rejected ('-' stands for $OLDPWD).
#
# Outputs:
#   The reason to stderr.
#
# Returns:
#   The code of the reason (see __cdl_diagnose_chdir_failure).
#######################################
function __cdl_report_chdir_failure() {
  local -i code="${CDL_ERR_CHDIR}"
  __cdl_diagnose_chdir_failure "$1" || code=$?

  __cdl_error "${REPLY}" "${code}"
}

# endregion

# region Terminal

#######################################
# Report whether a value is a positive decimal integer.
#
# Arguments:
#   1: Value to check.
#
# Returns:
#   0 for "1", "80", "120"; 1 for "", "0", "080", "12a".
#######################################
function __cdl_is_positive_integer() {
  case $1 in
    '' | 0* | *[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

#######################################
# Determine the terminal width.
#
# CDL_WIDTH wins when set. Otherwise COLUMNS,
# which bash and zsh keep up to date for free;
# then tput, and 80 columns as the last resort.
#
# Globals:
#   __cdl_setting_width, COLUMNS (read).
#
# Outputs:
#   Sets REPLY to the width in columns.
#######################################
function __cdl_terminal_width() {
  REPLY="${__cdl_setting_width}"
  if [[ -n ${REPLY} ]]; then
    return 0
  fi

  REPLY="${COLUMNS-}"
  if __cdl_is_positive_integer "${REPLY}"; then
    return 0
  fi

  # tput fails without a terminal;
  # the `||` keeps that failure from ending a `set -e` shell.
  REPLY="$(command tput cols 2>/dev/null)" || REPLY=''
  if __cdl_is_positive_integer "${REPLY}"; then
    return 0
  fi

  REPLY=80
}

#######################################
# Determine the terminal height.
#
# Prefers LINES, which bash and zsh keep up to date like COLUMNS;
# falls back to tput, and to 24 lines as the last resort.
#
# Globals:
#   LINES (read).
#
# Outputs:
#   Sets REPLY to the height in lines.
#######################################
function __cdl_terminal_height() {
  REPLY="${LINES-}"
  if __cdl_is_positive_integer "${REPLY}"; then
    return 0
  fi

  # tput fails without a terminal;
  # the `||` keeps that failure from ending a `set -e` shell.
  REPLY="$(command tput lines 2>/dev/null)" || REPLY=''
  if __cdl_is_positive_integer "${REPLY}"; then
    return 0
  fi

  REPLY=24
}

#######################################
# Determine how many rows the listing may take.
#
# CDL_MAX_ROWS or -a decide when given.
# Otherwise a terminal keeps lines free for the command above the listing,
# its header, the line about what was cut and the next prompt,
# but always shows at least five rows;
# a file or a pipe gets every row.
#
# Arguments:
#   1: Lines the header takes: 1, or 0 without a header.
#
# Globals:
#   __cdl_setting_max_rows (read).
#
# Outputs:
#   Sets REPLY to the most rows, or to 0 for no limit.
#######################################
function __cdl_max_rows() {
  local -ir header_lines="$1"
  # The command line, the note about the cut and the next prompt.
  local -ir surrounding_lines=3
  local -ir fewest_rows=5

  REPLY="${__cdl_setting_max_rows}"
  if [[ -n ${REPLY} ]]; then
    return 0
  fi
  if [[ ! -t 1 ]]; then
    REPLY=0
    return 0
  fi

  __cdl_terminal_height
  REPLY=$((REPLY - surrounding_lines - header_lines))
  if ((REPLY < fewest_rows)); then
    REPLY="${fewest_rows}"
  fi
}

#######################################
# Report whether the terminal takes UTF-8 text.
#
# The listing then cuts with "…" and joins with "·";
# otherwise with "..." and "|".
#
# Returns:
#   0 for a UTF-8 locale; 1 otherwise.
#######################################
function __cdl_utf8_output() {
  case ${LC_ALL:-${LC_CTYPE:-${LANG-}}} in
    *[Uu][Tt][Ff]-8* | *[Uu][Tt][Ff]8*) return 0 ;;
    *) return 1 ;;
  esac
}

#######################################
# Decide whether the listing should be colored.
#
# CDL_COLOR=always and never decide by themselves.
# Under auto, colors go to terminals only,
# and NO_COLOR (https://no-color.org) turns them off;
# as no-color.org asks, a setting of cdl itself wins over NO_COLOR.
#
# Globals:
#   __cdl_setting_color, NO_COLOR (read).
#
# Returns:
#   0 to use colors; 1 otherwise.
#######################################
function __cdl_should_color() {
  case ${__cdl_setting_color} in
    always) return 0 ;;
    never) return 1 ;;
    *) [[ -z ${NO_COLOR-} && -t 1 ]] ;;
  esac
}

#######################################
# Decide whether names become hyperlinks to their files (OSC 8).
#
# CDL_LINKS=always and never decide by themselves.
# Under auto, a colored listing on a terminal gets them,
# but not on the Linux console or a dumb terminal,
# which would print the escape sequences as text.
#
# Arguments:
#   1: 1 if the listing is colored; 0 otherwise.
#
# Globals:
#   __cdl_setting_links, TERM (read).
#
# Returns:
#   0 to link the names; 1 otherwise.
#######################################
function __cdl_should_link() {
  local -ir colored="$1"

  case ${__cdl_setting_links} in
    always) return 0 ;;
    never) return 1 ;;
  esac
  if ((!colored)) || [[ ! -t 1 ]]; then
    return 1
  fi

  case ${TERM-} in
    linux | dumb | '') return 1 ;;
    *) return 0 ;;
  esac
}

# endregion

# region Header

#######################################
# Decide whether the listing gets a header line.
#
# CDL_HEADER=always and never decide by themselves.
# Under auto, a terminal gets the header,
# which tells where cd landed;
# a file or a pipe gets the entries alone.
#
# Globals:
#   __cdl_setting_header (read).
#
# Returns:
#   0 to print the header; 1 otherwise.
#######################################
function __cdl_should_show_header() {
  case ${__cdl_setting_header} in
    always) return 0 ;;
    never) return 1 ;;
    *) [[ -t 1 ]] ;;
  esac
}

#######################################
# Write a directory the way the header shows it: ~ for HOME.
#
# Arguments:
#   1: Directory.
#
# Outputs:
#   Sets REPLY to the short form.
#######################################
function __cdl_pretty_path() {
  local -r directory="$1"
  local home="${HOME-}"
  home="${home%/}"

  # Without a HOME, or with HOME at the root, every path stays whole.
  if [[ -z ${home} ]]; then
    REPLY="${directory}"
    return 0
  fi

  # shellcheck disable=SC2088 # the header shows a literal ~, as the prompt does
  case ${directory} in
    "${home}") REPLY='~' ;;
    "${home}"/*) REPLY="~/${directory#"${home}"/}" ;;
    *) REPLY="${directory}" ;;
  esac
}

#######################################
# Find the git branch of the current directory without running git.
#
# Reads HEAD in the git directory of the current one:
# a branch name, or the short hash of a detached HEAD.
# A repository in the reftable format keeps its HEAD
# where only git can read it, so it shows no branch.
#
# Globals:
#   PWD (read).
#
# Outputs:
#   Sets REPLY to the branch, or to '' when there is none to show.
#######################################
function __cdl_git_branch() {
  # Seven digits, as git shortens a commit hash by default.
  local -ir short_hash_length=7

  __cdl_find_git_dir
  local -r git_dir="${REPLY}"
  REPLY=''
  if [[ -z ${git_dir} ]]; then
    return 0
  fi

  # The braces catch the error of a missing file,
  # which zsh prints even with `2>/dev/null` on the command itself.
  local head=''
  { read -r head <"${git_dir}/HEAD"; } 2>/dev/null || true

  case ${head} in
    'ref: refs/heads/.invalid') ;;
    'ref: refs/heads/'*) REPLY="${head#ref: refs/heads/}" ;;
    '' | *[!0-9a-f]*) ;;
    *) REPLY="${head:0:${short_hash_length}}" ;;
  esac
}

#######################################
# Find the git directory of the current directory.
#
# The search walks up to the nearest .git, as git does.
# In a worktree or a submodule, .git is a file
# whose `gitdir:` line names the real directory:
# an absolute path, or one relative to the file.
#
# Globals:
#   PWD (read).
#
# Outputs:
#   Sets REPLY to the git directory, or to '' outside a repository.
#######################################
function __cdl_find_git_dir() {
  local directory="${PWD}"

  while [[ ! -e ${directory}/.git ]]; do
    if [[ -z ${directory} ]]; then
      REPLY=''
      return 0
    fi
    directory="${directory%/*}"
  done

  REPLY="${directory}/.git"
  if [[ -d ${REPLY} ]]; then
    return 0
  fi

  local line=''
  { read -r line <"${REPLY}"; } 2>/dev/null || true

  case ${line} in
    'gitdir: /'*) REPLY="${line#gitdir: }" ;;
    'gitdir: '?*) REPLY="${directory}/${line#gitdir: }" ;;
    *) REPLY='' ;;
  esac
}

# endregion

# region Tool detection

#######################################
# Find out which ls to run and which options it understands.
#
# GNU ls, uutils ls and Homebrew's gls accept the GNU options
# behind the compact listing; BSD ls does not.
# Among BSD flavors, FreeBSD and macOS color with -G,
# while OpenBSD and NetBSD have no color option at all.
#
# The probe runs once per shell session:
# cdl lists on every directory change,
# and a fork per listing would be wasted on a known answer.
#
# Globals:
#   __cdl_ls_bin (read+write), __cdl_ls_is_gnu (write),
#   __cdl_ls_color_flag (write).
#######################################
function __cdl_detect_ls() {
  if [[ -n ${__cdl_ls_bin} ]]; then
    return 0
  fi

  __cdl_ls_bin='ls'
  if command -v gls >/dev/null 2>&1; then
    __cdl_ls_bin='gls'
  fi

  __cdl_ls_is_gnu=0
  __cdl_ls_color_flag=''
  if command "${__cdl_ls_bin}" --group-directories-first --version \
    >/dev/null 2>&1; then
    __cdl_ls_is_gnu=1
  elif command "${__cdl_ls_bin}" -G -d / >/dev/null 2>&1; then
    __cdl_ls_color_flag='-G'
  fi
}

#######################################
# Pick the awk that runs the formatter.
#
# mawk lays out a large directory about twice as fast as gawk,
# so it wins when installed; any other POSIX awk works too.
# The choice is cached for the shell session.
#
# Globals:
#   __cdl_awk_bin (read+write).
#######################################
function __cdl_detect_awk() {
  if [[ -n ${__cdl_awk_bin} ]]; then
    return 0
  fi

  __cdl_awk_bin='awk'
  if command -v mawk >/dev/null 2>&1; then
    __cdl_awk_bin='mawk'
  fi
}

# endregion

# region Listing

#######################################
# Print the listing of the current directory, without moving.
#
# The stable entry point for shell setups that wrap `cd` themselves:
#   function cd() { builtin cd "$@" && cdl_list; }
#
# Arguments:
#   -a, --all: Show every entry: no cut at the terminal height.
#   -1, --one-column: One entry per row.
#
# Outputs:
#   The listing to stdout; ls errors to stderr.
#
# Returns:
#   0 on success;
#   CDL_ERR_USAGE on an unknown option;
#   CDL_ERR_SETTING on an invalid setting;
#   CDL_ERR_LIST if ls could not list the directory in full.
#######################################
function cdl_list() {
  # Run with zsh's default options whatever the user has set
  # (KSH_ARRAYS, SH_WORD_SPLIT, ...); they come back on return.
  if [[ -n ${ZSH_VERSION-} ]]; then
    emulate -L zsh
  fi

  local REPLY

  __cdl_read_settings || return "$?"
  if (($# > 0)); then
    __cdl_apply_listing_options "$@" || return "$?"
  fi

  __cdl_list_current_directory
}

#######################################
# List the current directory with the settings already read.
#
# Arguments:
#   1: Name of an entry to mark (optional).
#
# Outputs:
#   The listing to stdout; ls errors to stderr.
#
# Returns:
#   0 on success; CDL_ERR_LIST if ls failed.
#######################################
function __cdl_list_current_directory() {
  local -r mark="${1-}"

  __cdl_detect_ls
  if ((__cdl_ls_is_gnu)); then
    __cdl_print_compact_listing "${mark}"
  else
    __cdl_print_plain_listing
  fi
}

#######################################
# Print the listing of the current directory.
#
# The name cdl 1.0 documented for `cd` wrappers,
# kept so that existing ~/.bashrc and ~/.zshrc files keep working;
# new setups should call cdl_list.
#######################################
function __cdl_print_listing() {
  cdl_list "$@"
}

#######################################
# Print the compact listing through a GNU-compatible ls,
# under a header line when one is due (see "Header").
#
# Arguments:
#   1: Name of an entry to mark (optional).
#
# Globals:
#   __cdl_ls_bin, __cdl_setting_hidden, __cdl_setting_max_columns,
#   __cdl_setting_git, PWD (read).
#
# Outputs:
#   The formatted listing to stdout.
#
# Returns:
#   0 on success; CDL_ERR_LIST if ls failed.
#######################################
function __cdl_print_compact_listing() {
  local -r mark="${1-}"
  local -i color=0
  local color_mode='never'
  if __cdl_should_color; then
    color=1
    color_mode='always'
  fi

  __cdl_terminal_width
  local -r width="${REPLY}"

  # `-A` lists hidden entries, but never `.` and `..`;
  # a hidden entry to mark brings them in.
  # Sizes come in bytes: the formatter writes them like `ls -h`,
  # and adds them up for the header.
  local short_options='-l'
  if ((__cdl_setting_hidden)) || [[ ${mark} == .* ]]; then
    short_options='-Al'
  fi

  # The C locale keeps `ls -l` free of translated words
  # ("итого" for "total") and of decimal commas in sizes,
  # and sorts names by bytes.
  # COLUMNS gets the checked width,
  # because uutils ls reads it and complains about a bad one.
  # The block size, the quoting and the time style are pinned,
  # so BLOCK_SIZE, QUOTING_STYLE or TIME_STYLE in the environment
  # cannot change what the formatter parses.
  #
  # The listing is captured rather than piped,
  # so the status of ls survives for the return code,
  # and the `||` keeps a failing ls from ending a `set -e` shell.
  # `$(...)` drops the trailing newlines of the output, so the last name,
  # when it ends in a newline, shows without its final '?':
  # a sentinel line would fix that for a fork on every listing.
  local listing
  local -i ls_status=0
  listing="$(
    COLUMNS="${width}" LC_ALL=C command "${__cdl_ls_bin}" "${short_options}" \
      --group-directories-first \
      --block-size=1 \
      --quoting-style=literal \
      --time-style='+%Y-%m-%d %H:%M' \
      --color="${color_mode}"
  )" || ls_status=$?

  # A header only over a listing in full, so its counts never mislead.
  local header_path='' header_branch=''
  local -i header_lines=0
  if ((ls_status == 0)) && __cdl_should_show_header; then
    header_lines=1
    __cdl_pretty_path "${PWD}"
    header_path="${REPLY}"
    if ((__cdl_setting_git)); then
      __cdl_git_branch
      header_branch="${REPLY}"
    fi
  fi

  local link_directory=''
  if __cdl_should_link "${color}"; then
    link_directory="${PWD}"
  fi

  __cdl_max_rows "${header_lines}"
  __cdl_format_listing "${width}" "${REPLY}" "${__cdl_setting_max_columns}" \
    "${color}" "${header_path}" "${header_branch}" "${mark}" "${link_directory}" \
    <<<"${listing}"

  if ((ls_status != 0)); then
    return "${CDL_ERR_LIST}"
  fi
}

#######################################
# Print the plain `ls -Alh` listing of a BSD ls.
#
# BSD ls shapes its dates by file age
# ("Jan  2 03:04" or "Jan  2  2025"),
# so its output is shown as is instead of being reformatted.
#
# Globals:
#   __cdl_ls_bin, __cdl_ls_color_flag, __cdl_setting_hidden (read).
#
# Outputs:
#   The listing to stdout.
#
# Returns:
#   0 on success; CDL_ERR_LIST if ls failed.
#######################################
function __cdl_print_plain_listing() {
  local -a options=(-lh)
  if ((__cdl_setting_hidden)); then
    options=(-Alh)
  fi
  if [[ -n ${__cdl_ls_color_flag} ]] && __cdl_should_color; then
    options+=("${__cdl_ls_color_flag}")
  fi

  if ! command "${__cdl_ls_bin}" "${options[@]}"; then
    return "${CDL_ERR_LIST}"
  fi
}

# endregion

# region Formatter

#######################################
# Lay out `ls -l` lines as the compact listing.
#
# Reads the output of the ls call in __cdl_print_compact_listing
# and prints one "SIZE  DATE TIME  NAME" entry per cell of a grid:
# as many columns as fit the terminal, filled top to bottom like ls.
# With a row limit, the entries beyond it are cut,
# and a last line says how many, and that -a shows them.
# A marked entry shows a mark in front of its size;
# when the cut would hide it, the listing shows the rows around it,
# under a line that says how many entries come before them.
#
# Names are made safe for the terminal:
# control characters become '?', like `ls -q` would show them,
# and only the color sequences of ls itself pass through.
# With a link directory, each name and the header path
# become hyperlinks (OSC 8) to their files, which cdl writes itself.
#
# Entries are measured in screen cells, not bytes:
# escape sequences take no cells, CJK and emoji take two,
# combining marks take none.
# The program runs under LC_ALL=C and decodes UTF-8 itself,
# so mawk and other byte-oriented awks align names as well as gawk.
#
# Arguments:
#   1: Terminal width in columns.
#   2: Most rows of the grid; 0 or none: no limit.
#   3: Most columns of the grid; 0 or none: as many as fit.
#   4: 1 to style the header and the note about a cut; 0 or none: plain.
#   5: Directory for a header line; empty or none: no header.
#   6: Git branch for the header; empty or none: no branch.
#   7: Name of the entry to mark; empty or none: no mark.
#   8: Directory the names link into; empty or none: no links.
#
# Globals:
#   __cdl_awk_bin, HOSTNAME or HOST (read).
#
# Inputs:
#   `ls -l` lines on stdin.
#
# Outputs:
#   The formatted listing to stdout.
#######################################
function __cdl_format_listing() {
  local -r width="$1"
  local -r max_rows="${2:-0}"
  local -r max_columns="${3:-0}"
  local -r color="${4:-0}"
  local -r header_path="${5-}"
  local -r header_branch="${6-}"
  local -r mark_name="${7-}"
  local -r link_directory="${8-}"

  local -i utf8_output=0
  if __cdl_utf8_output; then
    utf8_output=1
  fi

  __cdl_detect_awk

  # The texts travel in the environment:
  # `-v` would read backslashes in a name as escapes.
  # A link names the host, as the OSC 8 convention asks,
  # so that a terminal opens no local file for a listing made over ssh;
  # bash calls it HOSTNAME, zsh calls it HOST.
  # The program arrives on descriptor 3, from a quoted here-document
  # that bash hands over as it is;
  # as an argument, bash would scan the whole of it on every call,
  # for about 0.3 ms more.
  CDL_HEADER_PATH="${header_path}" CDL_HEADER_BRANCH="${header_branch}" \
    CDL_MARK_NAME="${mark_name}" CDL_LINK_DIRECTORY="${link_directory}" \
    CDL_LINK_HOST="${HOSTNAME:-${HOST-}}" LC_ALL=C command "${__cdl_awk_bin}" \
    -v width="${width}" -v max_rows="${max_rows}" -v max_columns="${max_columns}" \
    -v color="${color}" -v utf8_output="${utf8_output}" -f /dev/fd/3 3<<'AWK'
    # region Layout

    BEGIN {
      GUTTER = 4               # spaces between two columns
      UNITS = "KMGTPE"         # the units of `ls -h`, in powers of 1024
      SHORTEST_ROW_CELLS = 29  # an 8-cell size, a 16-cell date, a one-letter name

      # SIZE  DATE TIME  NAME, the size right-aligned in 8 cells,
      # which fits "1023M" and the "259, 0" of a device file.
      # A marked entry has its mark in place of the space before NAME.
      ROW_FORMAT = "%8s  %s  %s"
      MARKED_ROW_FORMAT = "%8s  %s %s"

      BOLD = "\033[1m"
      DIM = "\033[2m"
      RESET = "\033[0m"
      ELLIPSIS = utf8_output ? "\342\200\246" : "..."
      SEPARATOR = utf8_output ? " \302\267 " : " | "
      MARK = utf8_output ? "\342\235\257" : ">"

      # The signs cdl writes itself take one cell each.
      # Knowing that spares an ASCII listing the load of the width table.
      cell_memo["\342\200\246"] = 1
      cell_memo["\302\267"] = 1
      cell_memo["\342\235\257"] = 1

      header_path = ENVIRON["CDL_HEADER_PATH"]
      header_branch = ENVIRON["CDL_HEADER_BRANCH"]
      mark_name = ENVIRON["CDL_MARK_NAME"]

      byte_mode = (length("\320\224") == 2)

      # A hyperlink (OSC 8) opens with LINK_START, a URI and LINK_END,
      # and closes with the same two around no URI.
      LINK_START = "\033]8;;"
      LINK_END = "\033\\"
      link_directory = ENVIRON["CDL_LINK_DIRECTORY"]
      if (link_directory != "") {
        directory_uri = "file://" ENVIRON["CDL_LINK_HOST"] uri_encode(link_directory)
        entry_uri_prefix = directory_uri (link_directory == "/" ? "" : "/")
      }

      # A cut without a mark shows no entry beyond this one,
      # so the entries after it need nothing for their links.
      last_linkable = max_rows > 0 && mark_name == "" \
        ? max_rows * int((width + GUTTER) / (SHORTEST_ROW_CELLS + GUTTER)) \
        : -1

      # Control characters: C0 and DEL as bytes, C1 (U+0080..U+009F)
      # as a UTF-8 pair, or as characters in a UTF-8 aware awk.
      CONTROL = "[\001-\037\177]|" \
        (byte_mode ? "\302[\200-\237]" : sprintf("[%c-%c]", 128, 159))
    }

    {
      # Most listings mark nothing, and skip the check for every entry.
      if (parse_entry($0)) {
        add_entry(entry_size, entry_time, sanitize(entry_name),
          mark_name != "" && is_marked(entry_name))
      } else if (entry_count > 0) {
        extend_last_entry($0)
      }
    }

    END {
      if (header_path != "") print_header()
      if (entry_count == 0) exit

      choose_layout()
      if (first_shown > 1) print_note((first_shown - 1) " before")
      print_grid()
      if (last_shown < entry_count) print_note((entry_count - last_shown) " more; -a shows all")
    }

    # Keep an entry, and count it for the header.
    # Sets entry_count, entry_text, marked,
    # directory_count, file_count and byte_total, and keep_link() its own.
    function add_entry(size, time, name, is_mark) {
      entry_count++
      if (is_mark) {
        marked = entry_count
        entry_text[entry_count] = sprintf(MARKED_ROW_FORMAT, size, time, style(BOLD, MARK) name)
      } else {
        entry_text[entry_count] = sprintf(ROW_FORMAT, size, time, name)
      }
      if (entry_uri_prefix != "" && (last_linkable < 0 || entry_count <= last_linkable))
        keep_link(name)

      if (entry_kind == "d") directory_count++
      else file_count++
      if (entry_kind == "-") byte_total += entry_bytes
    }

    # Glue on the rest of a name that holds a newline,
    # which ls printed raw: the newline shows as "?",
    # and the link, if any, gets the name in full.
    # Sets entry_text, and raw_name for a linked entry.
    function extend_last_entry(line) {
      entry_text[entry_count] = entry_text[entry_count] "?" sanitize(line)
      if (!(entry_count in name_start)) return

      if (!(entry_count in raw_name)) raw_name[entry_count] = entry_name
      raw_name[entry_count] = raw_name[entry_count] "\n" line
    }

    # Return the cells of entry i, measured on first use:
    # entries that a cut hides are never measured.
    function cells(i) {
      if (!(i in entry_cells)) entry_cells[i] = display_width(entry_text[i])
      return entry_cells[i]
    }

    # Pick the most columns that fit the terminal, up to max_columns;
    # with max_rows, more columns also show more entries.
    # Sets grid_columns, grid_rows, first_shown, last_shown and column_cells,
    # as lay_out does.
    function choose_layout(    count) {
      for (count = most_columns(); count > 1; count--)
        if (lay_out(count) && laid_out_width() < width) return
      lay_out(1)
    }

    # Return a bound for the columns:
    # as many as would fit if every entry were as short as one can be.
    function most_columns(    limit) {
      limit = int((width + GUTTER) / (SHORTEST_ROW_CELLS + GUTTER))
      if (limit > entry_count) limit = entry_count
      if (max_columns > 0 && limit > max_columns) limit = max_columns
      return limit
    }

    # Spread the shown entries over count columns, top to bottom, like ls.
    # Sets grid_columns, grid_rows, first_shown, last_shown and column_cells.
    # Returns 0 when the last column would stay empty.
    function lay_out(count,    shown, column, first, last) {
      grid_columns = count
      choose_window(count)
      shown = last_shown - first_shown + 1
      grid_rows = int((shown + count - 1) / count)
      if ((count - 1) * grid_rows >= shown) return 0

      for (column = 1; column <= count; column++) {
        first = first_shown + (column - 1) * grid_rows
        last = first + grid_rows - 1
        if (last > last_shown) last = last_shown
        column_cells[column] = widest(first, last)
      }
      return 1
    }

    # Choose the entries a grid of count columns shows:
    # all of them without max_rows, or else as many as its rows hold,
    # from the first entry on, unless the marked one would fall beyond them.
    # Then the window puts the mark in the middle row of the middle column,
    # and gives one of its rows to the line about the entries before it.
    # Sets first_shown and last_shown.
    function choose_window(count,    rows, capacity, offset) {
      first_shown = 1
      last_shown = entry_count
      if (max_rows <= 0 || entry_count <= max_rows * count) return

      if (marked <= max_rows * count) {
        last_shown = max_rows * count
        return
      }

      rows = max_rows > 1 ? max_rows - 1 : 1
      capacity = rows * count
      offset = (int((count + 1) / 2) - 1) * rows + int((rows + 1) / 2) - 1
      first_shown = marked - offset
      if (first_shown > entry_count - capacity + 1) first_shown = entry_count - capacity + 1
      last_shown = first_shown + capacity - 1
    }

    function laid_out_width(    column, total) {
      total = GUTTER * (grid_columns - 1)
      for (column = 1; column <= grid_columns; column++) total += column_cells[column]
      return total
    }

    # Return the cells of the widest entry among entries first..last.
    function widest(first, last,    i, max, c) {
      max = 0
      for (i = first; i <= last; i++) {
        c = cells(i)
        if (c > max) max = c
      }
      return max
    }

    # Print the shown entries row by row; no row ends in spaces.
    function print_grid(    row, column, i, line) {
      for (row = 1; row <= grid_rows; row++) {
        line = ""
        for (column = 1; column <= grid_columns; column++) {
          i = first_shown + (column - 1) * grid_rows + row - 1
          if (i > last_shown) break

          line = line printed(i)
          if (i + grid_rows <= last_shown)
            line = line spaces(column_cells[column] - cells(i) + GUTTER)
        }
        print line
      }
    }

    # Print the directory, its git branch and what it holds,
    # on one line that fits the terminal;
    # with links on, the directory links to itself.
    function print_header(    summary, details, room, path) {
      summary = plural(directory_count, "dir") ", " plural(file_count, "file")
      if (byte_total > 0) summary = summary ", " total_size(byte_total)

      details = (header_branch != "" ? SEPARATOR plain_text(header_branch) : "") \
        SEPARATOR summary
      room = width - 1 - display_width(details)
      path = fit_path(plain_text(header_path), room)
      if (directory_uri != "") path = hyperlink(directory_uri, path)
      print style(BOLD, path) style(DIM, details)
    }

    # Keep what printed() needs to link the entry just added,
    # whose shown name is name: where that name starts in its row,
    # and only where they differ from the row, its name as ls printed it
    # and its kind, as most names are shown as they are and few are symlinks.
    # Sets name_start, raw_name and is_symlink.
    function keep_link(name) {
      name_start[entry_count] = length(entry_text[entry_count]) - length(name) + 1
      if (name != entry_name) raw_name[entry_count] = entry_name
      if (entry_kind == "l") is_symlink[entry_count] = 1
    }

    # Return entry i as printed: with links on, its name is a hyperlink.
    function printed(i,    text, start, name, uri) {
      text = entry_text[i]
      if (entry_uri_prefix == "") return text

      start = name_start[i]
      name = i in raw_name ? raw_name[i] : substr(text, start)
      uri = entry_uri_prefix uri_encode(plain_name(name, i in is_symlink ? "l" : ""))
      return substr(text, 1, start - 1) hyperlink(uri, substr(text, start))
    }

    # Shorten a path from the left until it fits the room:
    # "~/Documents/Projects/cdl" becomes "…/Projects/cdl".
    function fit_path(path, room,    tail, slash) {
      if (display_width(path) <= room) return path

      tail = path
      while ((slash = index(substr(tail, 2), "/")) > 0) {
        tail = substr(tail, slash + 1)
        if (display_width(ELLIPSIS tail) <= room) return ELLIPSIS tail
      }
      return ELLIPSIS tail
    }

    # Return the bytes of the files the way a row writes a size,
    # but with a "B" after a bare count of bytes:
    # in the header, no column says what the number is.
    function total_size(bytes) {
      return human_size(bytes) (bytes < 1024 ? "B" : "")
    }

    function plural(count, word) {
      count += 0
      return count " " word (count == 1 ? "" : "s")
    }

    # Print a line about the entries the listing leaves out.
    function print_note(text) {
      print style(DIM, ELLIPSIS " " text)
    }

    function style(code, text) {
      return color ? code text RESET : text
    }

    function spaces(n) {
      return n > 0 ? sprintf("%" n "s", "") : ""
    }

    # endregion

    # region Parsing

    # Split one `ls -l` line into entry_kind (the type letter),
    # entry_bytes, entry_size, entry_time and entry_name.
    # The date, pinned to YYYY-MM-DD by --time-style, anchors the parse,
    # so the "major, minor" size of a device file
    # or an owner name with spaces cannot shift the other fields.
    # Returns 0 for lines that are not entries, such as "total 12K".
    function parse_entry(line,    fields, field_count, date, i) {
      field_count = split(line, fields, " ")
      date = 0
      for (i = 6; i <= field_count - 2; i++) {
        if (fields[i] ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) {
          date = i
          break
        }
      }
      if (!date) return 0

      entry_kind = substr(fields[1], 1, 1)
      entry_time = fields[date] " " fields[date + 1]
      entry_name = name_after(line, entry_time " ")

      # A device file shows "major, minor" where others show a size.
      if (fields[date - 2] ~ /,$/) {
        entry_size = fields[date - 2] " " fields[date - 1]
        entry_bytes = 0
      } else {
        entry_bytes = fields[date - 1] + 0
        entry_size = human_size(entry_bytes)
      }
      return 1
    }

    # Return a size the way `ls -h` prints it:
    # powers of 1024, rounded up, with one decimal below 10.
    # Exact up to 2^53 bytes (8 PiB), the integers a double holds.
    function human_size(bytes,    unit, value, tenths) {
      if (bytes < 1024) return bytes ""

      value = bytes
      for (unit = 0; value >= 1024 && unit < length(UNITS); unit++) value /= 1024

      tenths = ceiling(value * 10)
      if (tenths < 100) return sprintf("%.1f%s", tenths / 10, substr(UNITS, unit, 1))
      if (ceiling(value) < 1024) return sprintf("%d%s", ceiling(value), substr(UNITS, unit, 1))
      return "1.0" substr(UNITS, unit + 1, 1)
    }

    function ceiling(x) {
      return x == int(x) ? x : int(x) + 1
    }

    # Report whether an entry is the one to mark, by its name as ls printed it.
    # A name is unique in a directory, so the search ends at the first match.
    function is_marked(name) {
      if (marked || !index(name, mark_name)) return 0
      return plain_name(name, entry_kind) == mark_name
    }

    # Return a name as ls printed it, without the escapes ls adds,
    # and for a symlink (kind "l") without its " -> TARGET".
    # An escape that belongs to the name itself stays:
    # the name must still name its file.
    function plain_name(name, kind,    arrow) {
      if (index(name, "\033")) gsub(/\033\[[0-9;]*[mK]/, "", name)
      if (kind == "l" && (arrow = index(name, " -> ")) > 0) name = substr(name, 1, arrow - 1)
      return name
    }

    # Return what follows the first "DATE TIME " in line: the name.
    # The stamp comes before the name, so its first occurrence
    # is the column itself, even when the name holds a similar text;
    # the name keeps its runs of spaces, unlike fields would.
    function name_after(line, stamp) {
      return substr(line, index(line, stamp) + length(stamp))
    }

    # Replace the control characters of a name with "?",
    # keeping only the escapes ls itself adds:
    # SGR colors and erase-in-line.
    function sanitize(name,    clean, control_length) {
      if (name !~ CONTROL) return name

      clean = ""
      while (match(name, CONTROL)) {
        clean = clean substr(name, 1, RSTART - 1)
        name = substr(name, RSTART)
        control_length = RLENGTH
        if (match(name, /^\033\[[0-9;]*[mK]/)) {
          clean = clean substr(name, 1, RLENGTH)
          name = substr(name, RLENGTH + 1)
        } else {
          clean = clean "?"
          name = substr(name, control_length + 1)
        }
      }
      return clean name
    }

    # Replace every control character with "?",
    # in a text that ls did not print, such as the path of the header:
    # none of its escapes belongs to cdl.
    function plain_text(text) {
      gsub(CONTROL, "?", text)
      return text
    }

    # endregion

    # region Links

    # Return text as the hyperlink (OSC 8) to uri.
    function hyperlink(uri, text) {
      return LINK_START uri LINK_END text LINK_START LINK_END
    }

    # Return a path the way a file URI writes it:
    # bytes outside the unreserved characters of RFC 3986 and "/"
    # become %XX, so the URI holds no space, no control character
    # and nothing outside ASCII.
    function uri_encode(path,    encoded, i, char) {
      if (path ~ /^[A-Za-z0-9._~\/-]*$/) return path

      encoded = ""
      for (i = 1; i <= length(path); i++) {
        char = substr(path, i, 1)
        encoded = encoded (char ~ /^[A-Za-z0-9._~\/-]$/ ? char : percent_escape(char))
      }
      return encoded
    }

    # Return the %XX escapes of the bytes of one character, remembered:
    # a byte-oriented awk hands over a byte at a time,
    # a UTF-8 aware awk a whole character.
    function percent_escape(char) {
      if (char in escape_memo) return escape_memo[char]
      if (byte_mode || char < "\200") return escape_memo[char] = sprintf("%%%02X", byte_value(char))
      return escape_memo[char] = utf8_bytes(code_point(char), "%%%02X")
    }

    # Return the value of a byte, from a table built on first use.
    function byte_value(byte,    value) {
      if (!byte_values_ready) {
        for (value = 1; value < 256; value++) byte_values[sprintf("%c", value)] = value
        byte_values_ready = 1
      }
      return byte_values[byte]
    }

    # Return the code point of a character in a UTF-8 aware awk,
    # by binary search: UTF-8 keeps code point order under comparison.
    function code_point(char,    low, high, middle) {
      low = 128
      high = 1114111
      while (low < high) {
        middle = int((low + high) / 2)
        if (utf8(middle) < char) low = middle + 1
        else high = middle
      }
      return low
    }

    # endregion

    # region Text measurement

    # Return the screen cells that text takes.
    function display_width(text,    plain, total, i, step) {
      plain = index(text, "\033") ? strip_escapes(text) : text
      if (plain ~ /^[ -~]*$/) return length(plain)  # printable ASCII

      total = 0
      for (i = 1; i <= length(plain); i += step) {
        step = byte_mode ? sequence_length(substr(plain, i, 1)) : 1
        total += char_cells(substr(plain, i, step))
      }
      return total
    }

    # Remove CSI sequences (colors, erase-in-line)
    # and OSC sequences (hyperlinks).
    function strip_escapes(text) {
      gsub(/\033\[[0-?]*[ -\/]*[@-~]/, "", text)
      gsub(/\033\][^\007\033]*(\007|\033\\)/, "", text)
      return text
    }

    # Return the length of the UTF-8 sequence that starts with byte.
    function sequence_length(byte) {
      if (byte < "\300") return 1  # ASCII, or a stray continuation byte
      if (byte < "\340") return 2
      if (byte < "\360") return 3
      return 4
    }

    # Return the screen cells of one character,
    # by binary search in the width table.
    # UTF-8 keeps code point order under byte comparison,
    # so plain string comparison works in every awk.
    # Names repeat their letters, so each answer is remembered.
    function char_cells(char,    low, high, middle) {
      if (char < "\200") return 1
      if (char in cell_memo) return cell_memo[char]
      if (!range_count) load_width_table()

      low = 1
      high = range_count
      while (low <= high) {
        middle = int((low + high) / 2)
        if (!(middle in range_cells)) parse_range(middle)

        if (char < range_first[middle]) high = middle - 1
        else if (char > range_last[middle]) low = middle + 1
        else return cell_memo[char] = range_cells[middle]
      }
      return cell_memo[char] = 1
    }

    # Split the width table into its tokens, once, on first use.
    # Listings of plain ASCII names never get here,
    # and a token is decoded only when a search first reaches it.
    function load_width_table() {
      range_count = split(width_table(), range_token, " ")
    }

    # Decode token i into its UTF-8 bounds and its cell count.
    function parse_range(i,    parts, bounds) {
      split(range_token[i], parts, ":")
      split(parts[1], bounds, "-")
      range_first[i] = utf8(hex(bounds[1]))
      range_last[i] = utf8(hex(bounds[2] == "" ? bounds[1] : bounds[2]))
      range_cells[i] = parts[2] + 0
    }

    function hex(digits,    value, i) {
      value = 0
      for (i = 1; i <= length(digits); i++)
        value = value * 16 + index("0123456789ABCDEF", substr(digits, i, 1)) - 1
      return value
    }

    # Encode a code point as UTF-8.
    # A byte-oriented awk gets the bytes spelled out;
    # a UTF-8 aware awk encodes the code point by itself.
    function utf8(code) {
      return byte_mode ? utf8_bytes(code, "%c") : sprintf("%c", code)
    }

    # Write the UTF-8 bytes of a code point, each through format:
    # "%c" gives the bytes themselves, "%%%02X" their URI escapes.
    function utf8_bytes(code, format) {
      if (code < 128) return sprintf(format, code)
      if (code < 2048)
        return sprintf(format format, 192 + int(code / 64), 128 + code % 64)
      if (code < 65536)
        return sprintf(format format format, 224 + int(code / 4096),
          128 + int(code / 64) % 64, 128 + code % 64)
      return sprintf(format format format format, 240 + int(code / 262144),
        128 + int(code / 4096) % 64, 128 + int(code / 64) % 64, 128 + code % 64)
    }

    # endregion

    # region Width table

    # Unicode 16.0.0, generated by tools/gen-width-table.py: do not edit by hand.
    # Tokens: FIRST[-LAST]:CELLS, hex code points in ascending order.
    function width_table(    t) {
      t = t "0300-036F:0 0483-0489:0 0591-05BD:0 05BF:0 05C1-05C2:0 05C4-05C5:0 05C7:0 0600-0605:0 "
      t = t "0610-061A:0 061C:0 064B-065F:0 0670:0 06D6-06DD:0 06DF-06E4:0 06E7-06E8:0 06EA-06ED:0 "
      t = t "070F:0 0711:0 0730-074A:0 07A6-07B0:0 07EB-07F3:0 07FD:0 0816-0819:0 081B-0823:0 "
      t = t "0825-0827:0 0829-082D:0 0859-085B:0 0890-0891:0 0897-089F:0 08CA-0902:0 093A:0 093C:0 "
      t = t "0941-0948:0 094D:0 0951-0957:0 0962-0963:0 0981:0 09BC:0 09C1-09C4:0 09CD:0 "
      t = t "09E2-09E3:0 09FE:0 0A01-0A02:0 0A3C:0 0A41-0A42:0 0A47-0A48:0 0A4B-0A4D:0 0A51:0 "
      t = t "0A70-0A71:0 0A75:0 0A81-0A82:0 0ABC:0 0AC1-0AC5:0 0AC7-0AC8:0 0ACD:0 0AE2-0AE3:0 "
      t = t "0AFA-0AFF:0 0B01:0 0B3C:0 0B3F:0 0B41-0B44:0 0B4D:0 0B55-0B56:0 0B62-0B63:0 0B82:0 "
      t = t "0BC0:0 0BCD:0 0C00:0 0C04:0 0C3C:0 0C3E-0C40:0 0C46-0C48:0 0C4A-0C4D:0 0C55-0C56:0 "
      t = t "0C62-0C63:0 0C81:0 0CBC:0 0CBF:0 0CC6:0 0CCC-0CCD:0 0CE2-0CE3:0 0D00-0D01:0 "
      t = t "0D3B-0D3C:0 0D41-0D44:0 0D4D:0 0D62-0D63:0 0D81:0 0DCA:0 0DD2-0DD4:0 0DD6:0 0E31:0 "
      t = t "0E34-0E3A:0 0E47-0E4E:0 0EB1:0 0EB4-0EBC:0 0EC8-0ECE:0 0F18-0F19:0 0F35:0 0F37:0 "
      t = t "0F39:0 0F71-0F7E:0 0F80-0F84:0 0F86-0F87:0 0F8D-0F97:0 0F99-0FBC:0 0FC6:0 102D-1030:0 "
      t = t "1032-1037:0 1039-103A:0 103D-103E:0 1058-1059:0 105E-1060:0 1071-1074:0 1082:0 "
      t = t "1085-1086:0 108D:0 109D:0 1100-115F:2 1160-11FF:0 135D-135F:0 1712-1714:0 1732-1733:0 "
      t = t "1752-1753:0 1772-1773:0 17B4-17B5:0 17B7-17BD:0 17C6:0 17C9-17D3:0 17DD:0 180B-180F:0 "
      t = t "1885-1886:0 18A9:0 1920-1922:0 1927-1928:0 1932:0 1939-193B:0 1A17-1A18:0 1A1B:0 "
      t = t "1A56:0 1A58-1A5E:0 1A60:0 1A62:0 1A65-1A6C:0 1A73-1A7C:0 1A7F:0 1AB0-1ACE:0 "
      t = t "1B00-1B03:0 1B34:0 1B36-1B3A:0 1B3C:0 1B42:0 1B6B-1B73:0 1B80-1B81:0 1BA2-1BA5:0 "
      t = t "1BA8-1BA9:0 1BAB-1BAD:0 1BE6:0 1BE8-1BE9:0 1BED:0 1BEF-1BF1:0 1C2C-1C33:0 1C36-1C37:0 "
      t = t "1CD0-1CD2:0 1CD4-1CE0:0 1CE2-1CE8:0 1CED:0 1CF4:0 1CF8-1CF9:0 1DC0-1DFF:0 200B-200F:0 "
      t = t "202A-202E:0 2060-2064:0 2066-206F:0 20D0-20F0:0 231A-231B:2 2329-232A:2 23E9-23EC:2 "
      t = t "23F0:2 23F3:2 25FD-25FE:2 2614-2615:2 2630-2637:2 2648-2653:2 267F:2 268A-268F:2 "
      t = t "2693:2 26A1:2 26AA-26AB:2 26BD-26BE:2 26C4-26C5:2 26CE:2 26D4:2 26EA:2 26F2-26F3:2 "
      t = t "26F5:2 26FA:2 26FD:2 2705:2 270A-270B:2 2728:2 274C:2 274E:2 2753-2755:2 2757:2 "
      t = t "2795-2797:2 27B0:2 27BF:2 2B1B-2B1C:2 2B50:2 2B55:2 2CEF-2CF1:0 2D7F:0 2DE0-2DFF:0 "
      t = t "2E80-2E99:2 2E9B-2EF3:2 2F00-2FD5:2 2FF0-3029:2 302A-302D:0 302E-303E:2 3041-3096:2 "
      t = t "3099-309A:0 309B-30FF:2 3105-312F:2 3131-318E:2 3190-31E5:2 31EF-321E:2 3220-3247:2 "
      t = t "3250-A48C:2 A490-A4C6:2 A66F-A672:0 A674-A67D:0 A69E-A69F:0 A6F0-A6F1:0 A802:0 A806:0 "
      t = t "A80B:0 A825-A826:0 A82C:0 A8C4-A8C5:0 A8E0-A8F1:0 A8FF:0 A926-A92D:0 A947-A951:0 "
      t = t "A960-A97C:2 A980-A982:0 A9B3:0 A9B6-A9B9:0 A9BC-A9BD:0 A9E5:0 AA29-AA2E:0 AA31-AA32:0 "
      t = t "AA35-AA36:0 AA43:0 AA4C:0 AA7C:0 AAB0:0 AAB2-AAB4:0 AAB7-AAB8:0 AABE-AABF:0 AAC1:0 "
      t = t "AAEC-AAED:0 AAF6:0 ABE5:0 ABE8:0 ABED:0 AC00-D7A3:2 F900-FAFF:2 FB1E:0 FE00-FE0F:0 "
      t = t "FE10-FE19:2 FE20-FE2F:0 FE30-FE52:2 FE54-FE66:2 FE68-FE6B:2 FEFF:0 FF01-FF60:2 "
      t = t "FFE0-FFE6:2 FFF9-FFFB:0 101FD:0 102E0:0 10376-1037A:0 10A01-10A03:0 10A05-10A06:0 "
      t = t "10A0C-10A0F:0 10A38-10A3A:0 10A3F:0 10AE5-10AE6:0 10D24-10D27:0 10D69-10D6D:0 "
      t = t "10EAB-10EAC:0 10EFC-10EFF:0 10F46-10F50:0 10F82-10F85:0 11001:0 11038-11046:0 11070:0 "
      t = t "11073-11074:0 1107F-11081:0 110B3-110B6:0 110B9-110BA:0 110BD:0 110C2:0 110CD:0 "
      t = t "11100-11102:0 11127-1112B:0 1112D-11134:0 11173:0 11180-11181:0 111B6-111BE:0 "
      t = t "111C9-111CC:0 111CF:0 1122F-11231:0 11234:0 11236-11237:0 1123E:0 11241:0 112DF:0 "
      t = t "112E3-112EA:0 11300-11301:0 1133B-1133C:0 11340:0 11366-1136C:0 11370-11374:0 "
      t = t "113BB-113C0:0 113CE:0 113D0:0 113D2:0 113E1-113E2:0 11438-1143F:0 11442-11444:0 "
      t = t "11446:0 1145E:0 114B3-114B8:0 114BA:0 114BF-114C0:0 114C2-114C3:0 115B2-115B5:0 "
      t = t "115BC-115BD:0 115BF-115C0:0 115DC-115DD:0 11633-1163A:0 1163D:0 1163F-11640:0 116AB:0 "
      t = t "116AD:0 116B0-116B5:0 116B7:0 1171D:0 1171F:0 11722-11725:0 11727-1172B:0 "
      t = t "1182F-11837:0 11839-1183A:0 1193B-1193C:0 1193E:0 11943:0 119D4-119D7:0 119DA-119DB:0 "
      t = t "119E0:0 11A01-11A0A:0 11A33-11A38:0 11A3B-11A3E:0 11A47:0 11A51-11A56:0 11A59-11A5B:0 "
      t = t "11A8A-11A96:0 11A98-11A99:0 11C30-11C36:0 11C38-11C3D:0 11C3F:0 11C92-11CA7:0 "
      t = t "11CAA-11CB0:0 11CB2-11CB3:0 11CB5-11CB6:0 11D31-11D36:0 11D3A:0 11D3C-11D3D:0 "
      t = t "11D3F-11D45:0 11D47:0 11D90-11D91:0 11D95:0 11D97:0 11EF3-11EF4:0 11F00-11F01:0 "
      t = t "11F36-11F3A:0 11F40:0 11F42:0 11F5A:0 13430-13440:0 13447-13455:0 1611E-16129:0 "
      t = t "1612D-1612F:0 16AF0-16AF4:0 16B30-16B36:0 16F4F:0 16F8F-16F92:0 16FE0-16FE3:2 16FE4:0 "
      t = t "16FF0-16FF1:2 17000-187F7:2 18800-18CD5:2 18CFF-18D08:2 1AFF0-1AFF3:2 1AFF5-1AFFB:2 "
      t = t "1AFFD-1AFFE:2 1B000-1B122:2 1B132:2 1B150-1B152:2 1B155:2 1B164-1B167:2 1B170-1B2FB:2 "
      t = t "1BC9D-1BC9E:0 1BCA0-1BCA3:0 1CF00-1CF2D:0 1CF30-1CF46:0 1D167-1D169:0 1D173-1D182:0 "
      t = t "1D185-1D18B:0 1D1AA-1D1AD:0 1D242-1D244:0 1D300-1D356:2 1D360-1D376:2 1DA00-1DA36:0 "
      t = t "1DA3B-1DA6C:0 1DA75:0 1DA84:0 1DA9B-1DA9F:0 1DAA1-1DAAF:0 1E000-1E006:0 1E008-1E018:0 "
      t = t "1E01B-1E021:0 1E023-1E024:0 1E026-1E02A:0 1E08F:0 1E130-1E136:0 1E2AE:0 1E2EC-1E2EF:0 "
      t = t "1E4EC-1E4EF:0 1E5EE-1E5EF:0 1E8D0-1E8D6:0 1E944-1E94A:0 1F004:2 1F0CF:2 1F18E:2 "
      t = t "1F191-1F19A:2 1F200-1F202:2 1F210-1F23B:2 1F240-1F248:2 1F250-1F251:2 1F260-1F265:2 "
      t = t "1F300-1F320:2 1F32D-1F335:2 1F337-1F37C:2 1F37E-1F393:2 1F3A0-1F3CA:2 1F3CF-1F3D3:2 "
      t = t "1F3E0-1F3F0:2 1F3F4:2 1F3F8-1F43E:2 1F440:2 1F442-1F4FC:2 1F4FF-1F53D:2 1F54B-1F54E:2 "
      t = t "1F550-1F567:2 1F57A:2 1F595-1F596:2 1F5A4:2 1F5FB-1F64F:2 1F680-1F6C5:2 1F6CC:2 "
      t = t "1F6D0-1F6D2:2 1F6D5-1F6D7:2 1F6DC-1F6DF:2 1F6EB-1F6EC:2 1F6F4-1F6FC:2 1F7E0-1F7EB:2 "
      t = t "1F7F0:2 1F90C-1F93A:2 1F93C-1F945:2 1F947-1F9FF:2 1FA70-1FA7C:2 1FA80-1FA89:2 "
      t = t "1FA8F-1FAC6:2 1FACE-1FADC:2 1FADF-1FAE9:2 1FAF0-1FAF8:2 20000-2FFFD:2 30000-3FFFD:2 "
      t = t "E0001:0 E0020-E007F:0 E0100-E01EF:0 "
      return t
    }

    # endregion
AWK
}

# endregion

# region Public API

#######################################
# Change directory and list its contents.
#
# Arguments:
#   -h, --help: Print the usage and return.
#   -V, --version: Print the version and return.
#   -L, -P: Passed to cd: follow symlinks logically, or resolve them;
#           the last of the two wins, in bash and zsh alike.
#   -a, --all, -1, --one-column: Passed to the listing, see cdl_list.
#   --: End of options.
#   1: Optional directory; see __cdl_resolve_target for the fallbacks.
#
# Outputs:
#   The listing to stdout; errors to stderr.
#
# Returns:
#   0 on success;
#   CDL_ERR_USAGE on an unknown option, an empty or an extra operand,
#   and CDL_ERR_SETTING on an invalid setting, before the directory changes;
#   CDL_ERR_CHDIR, or a reason in its ten (CDL_ERR_NOT_FOUND,
#   CDL_ERR_DENIED, CDL_ERR_NOT_DIRECTORY), if the directory
#   cannot be entered (see __cdl_diagnose_chdir_failure);
#   CDL_ERR_LIST if it was entered but could not be listed in full.
#######################################
function cdl() {
  # Run with zsh's default options whatever the user has set
  # (KSH_ARRAYS, SH_WORD_SPLIT, ...); they come back on return.
  if [[ -n ${ZSH_VERSION-} ]]; then
    emulate -L zsh
  fi

  local REPLY
  local cd_option=''
  local -a listing_options=()

  while (($# > 0)); do
    case $1 in
      -h | --help)
        __cdl_usage
        return 0
        ;;
      -V | --version)
        printf 'cdl %s\n' "${CDL_VERSION}"
        return 0
        ;;
      -L | -P) cd_option="$1" ;;
      -a | --all | -1 | --one-column) listing_options+=("$1") ;;
      --)
        shift
        break
        ;;
      -?*)
        __cdl_error "Unknown option: '$1' (see 'cdl --help')" "${CDL_ERR_USAGE}" \
          || return "$?"
        ;;
      *) break ;;
    esac
    shift
  done

  __cdl_check_operands "$@" || return "$?"
  __cdl_read_settings || return "$?"
  if ((${#listing_options[@]} > 0)); then
    __cdl_apply_listing_options "${listing_options[@]}" || return "$?"
  fi

  __cdl_resolve_target "${1-}"
  __cdl_expand_target "${REPLY}"
  __cdl_enter "${REPLY}" "${cd_option}" || return "$?"
  __cdl_list_current_directory "${REPLY}"
}

# endregion

# region Completion

#######################################
# Complete a word of a cdl command line in bash.
#
# A word that starts with a dash gets the options of cdl,
# as words rather than file names (bash 4 and later),
# so that no file look or quoting comes with them;
# any other word gets the directories and files it begins,
# as cdl takes both, and the directories under CDPATH, as cd does.
# A word that starts with ~ gets nothing here:
# readline completes it itself (see the `complete` call below),
# and keeps the ~ that compgen would expand.
#
# Globals:
#   COMP_WORDS, COMP_CWORD, CDPATH (read); COMPREPLY (write).
#######################################
function __cdl_complete_bash() {
  local -r option_words='-a --all -1 --one-column -L -P -h --help -V --version --'
  local -r word="${COMP_WORDS[COMP_CWORD]}"
  COMPREPLY=()

  case ${word} in
    -*)
      if ((BASH_VERSINFO[0] >= 4)); then
        compopt +o filenames 2>/dev/null
      fi
      __cdl_add_completions '' -W "${option_words}" -- "${word}"
      return 0
      ;;
    '~'*) return 0 ;;
  esac

  __cdl_add_completions '' -f -- "${word}"
  if [[ -z ${CDPATH-} || ${word} == [/.]* ]]; then
    return 0
  fi

  local base
  local -a bases=()
  IFS=':' read -r -a bases <<<"${CDPATH}"
  for base in ${bases[@]+"${bases[@]}"}; do
    base="${base%/}"
    if [[ -n ${base} && ${base} != '.' ]]; then
      __cdl_add_completions "${base}/" -d -- "${base}/${word}"
    fi
  done
}

#######################################
# Add the words compgen finds to COMPREPLY, one per line.
#
# Reading lines keeps a name with spaces whole,
# and leaves bash 3.2 without mapfile no worse off.
#
# Arguments:
#   1: A prefix to take off each word ('' for none).
#   $@: Arguments for compgen.
#
# Globals:
#   COMPREPLY (write).
#######################################
function __cdl_add_completions() {
  local -r prefix="$1"
  shift

  local candidate
  while IFS= read -r candidate; do
    COMPREPLY+=("${candidate#"${prefix}"}")
  done < <(compgen "$@")
}

#######################################
# Complete a cdl command line in zsh.
#
# The options of cdl, then one directory or file:
# _files offers both, and CDPATH adds its directories,
# as it does for cd.
#######################################
function __cdl_complete_zsh() {
  _arguments -S : \
    '(- :)'{-h,--help}'[show the help]' \
    '(- :)'{-V,--version}'[show the version]' \
    '(-a --all)'{-a,--all}'[show every entry, with no cut]' \
    '(-1 --one-column)'{-1,--one-column}'[show one entry per row]' \
    '(-L -P)-L[keep symbolic links in the path]' \
    '(-L -P)-P[resolve symbolic links]' \
    ':directory or file:__cdl_complete_zsh_target'
}

#######################################
# Offer the directories and files a cdl operand can name in zsh.
#######################################
function __cdl_complete_zsh_target() {
  local -a alternatives=('files:file:_files')

  # shellcheck disable=SC2153,SC2154 # PREFIX belongs to the completion system of zsh
  if [[ -n ${CDPATH-} && ${PREFIX} != [/.~]* ]]; then
    alternatives+=('cdpath-directories:directory in CDPATH:_path_files -W cdpath -/')
  fi

  _alternative "${alternatives[@]}"
}

#######################################
# Complete a cdl_list command line in zsh: its two options.
#######################################
function __cdl_complete_zsh_list() {
  _arguments : \
    '(-a --all)'{-a,--all}'[show every entry, with no cut]' \
    '(-1 --one-column)'{-1,--one-column}'[show one entry per row]'
}

#######################################
# Register the zsh completion of cdl and cdl_list,
# and of cd when cdl replaces it (see "Replacing cd").
#
# compdef comes from compinit, or from a plugin manager
# that queues the calls until it runs compinit.
#
# Globals:
#   CDL_REPLACE_CD (read).
#
# Returns:
#   0 once registered; 1 while compdef is missing.
#######################################
function __cdl_register_zsh_completion() {
  if ! typeset -f compdef >/dev/null 2>&1; then
    return 1
  fi

  compdef __cdl_complete_zsh cdl
  compdef __cdl_complete_zsh_list cdl_list
  if [[ ${CDL_REPLACE_CD-} == 1 ]]; then
    compdef __cdl_complete_zsh cd
  fi
}

#######################################
# Give cd the completion of cdl in bash, when cdl replaces cd.
#
# Globals:
#   CDL_REPLACE_CD (read).
#######################################
function __cdl_register_bash_cd_completion() {
  if [[ ${CDL_REPLACE_CD-} != 1 ]]; then
    return 0
  fi

  complete -o filenames -o default -F __cdl_complete_bash cd
  __cdl_hand_ble_cd_completion
}

#######################################
# Let ble.sh complete cd as it completes cdl, if ble.sh is loaded.
#
# ble.sh completes cd by a function of its own, ahead of `complete`,
# and describes the options of cd from `help cd`, in a cache on disk.
# Once its modules load, the function goes,
# as the integrations that come with ble.sh take it away,
# and cd counts as a command without options of its own,
# so that neither those descriptions nor their cache come back:
# the options of cdl show as a plain list, as they do after cdl.
#######################################
function __cdl_hand_ble_cd_completion() {
  if declare -F blehook/eval-after-load >/dev/null; then
    blehook/eval-after-load complete 'builtin unset -f ble/cmdinfo/complete:cd'
  fi
  if declare -F ble-import >/dev/null; then
    ble-import -C 'ble/cmdspec/opts +no-options cd' lib/core-cmdspec.sh
  fi
}

#######################################
# Add a function to the precmd hooks of zsh, unless it is there already.
#
# Arguments:
#   1: Function name.
#
# Globals:
#   precmd_functions (read+write).
#######################################
function __cdl_add_precmd_function() {
  local -r function_name="$1"

  # Declared as a global array first, which it is,
  # so that WARN_CREATE_GLOBAL stays quiet.
  typeset -ga precmd_functions

  local hook
  for hook in ${precmd_functions[@]+"${precmd_functions[@]}"}; do
    if [[ ${hook} == "${function_name}" ]]; then
      return 0
    fi
  done
  precmd_functions+=("${function_name}")
}

#######################################
# Register the zsh completion at the first prompt, once.
#
# An rc file may source cdl.sh before it runs compinit;
# by the first prompt, compinit has run if it ever will.
# The hook takes itself off precmd_functions either way.
#
# Globals:
#   precmd_functions (read+write).
#######################################
function __cdl_register_zsh_completion_at_prompt() {
  emulate -L zsh

  local hook
  local -a kept=()
  for hook in "${precmd_functions[@]}"; do
    if [[ ${hook} != '__cdl_register_zsh_completion_at_prompt' ]]; then
      kept+=("${hook}")
    fi
  done
  precmd_functions=("${kept[@]}")

  __cdl_register_zsh_completion || true
}

# Completion needs a shell that has it: bash with `complete`, or zsh,
# now if compinit has run, or else at the first prompt.
# Either way, sourcing runs no external command.
# In bash, `-o default` hands readline the words compgen cannot take,
# a ~ or an escaped space ("My\ D"), and it completes them itself.
# A cd that cdl replaces completes as cdl does.
if [[ -n ${ZSH_VERSION-} ]]; then
  if ! __cdl_register_zsh_completion; then
    __cdl_add_precmd_function __cdl_register_zsh_completion_at_prompt
  fi
elif complete -o filenames -o default -F __cdl_complete_bash cdl 2>/dev/null; then
  complete -W '-a --all -1 --one-column' cdl_list
  __cdl_register_bash_cd_completion
fi

# endregion

# region Replacing cd

#######################################
# Change the directory as cd does, through cdl wherever that is safe.
#
# On a terminal, cdl takes the call: its options, its files, its listing;
# so it does wherever an option only cdl knows asks for it,
# as in `cd -a dir | less`.
# Anywhere else, as in `$(cd dir && pwd)` or `cd dir >/dev/null`,
# the shell's own cd takes it, so the functions of other tools
# that run cd in this shell get the cd they were written for.
# The shell's cd also takes the options cdl does not know,
# as -e of bash or -q of zsh, and the two-word cd of zsh,
# and a terminal still gets the listing after it.
# CDL_REPLACE_CD=0 gives every cd back to the shell, in a running session.
# The shell's cd runs before any emulate,
# with the options the user set for it (AUTO_PUSHD and the like).
#
# Arguments:
#   $@: Arguments of cd.
#
# Globals:
#   CDL_REPLACE_CD (read).
#
# Returns:
#   The status of cdl, or of the shell's own cd.
#######################################
function __cdl_cd() {
  if [[ ${CDL_REPLACE_CD-} != 1 ]]; then
    builtin cd "$@" || return
    return 0
  fi

  if __cdl_has_shell_option "$@" || __cdl_is_zsh_two_word_cd "$@"; then
    builtin cd "$@" || return
    if [[ -t 1 ]]; then
      cdl_list
    fi
    return
  fi

  if [[ -t 1 ]] || __cdl_has_cdl_option "$@"; then
    cdl "$@"
    return
  fi

  builtin cd "$@" || return
}

#######################################
# Tell whether a cd command line holds an option only cdl knows.
#
# The words after `--` are directories, not options.
#
# Arguments:
#   $@: Arguments of cd.
#
# Returns:
#   0 if it does; 1 otherwise.
#######################################
function __cdl_has_cdl_option() {
  local word
  for word in "$@"; do
    case ${word} in
      --) return 1 ;;
      -a | --all | -1 | --one-column | -h | --help | -V | --version) return 0 ;;
    esac
  done

  return 1
}

#######################################
# Tell whether a cd command line holds an option cdl does not know,
# as in `cd -e dir` in bash, `cd -q dir` in zsh or `cd -LP dir`;
# a place in the directory stack of zsh, as in `cd -2`, counts too.
# The shell's own cd takes such a line, with its own error for a wrong one.
#
# The words after `--` are directories, not options;
# `-` alone means the previous directory.
#
# Arguments:
#   $@: Arguments of cd.
#
# Returns:
#   0 if it does; 1 otherwise.
#######################################
function __cdl_has_shell_option() {
  local word
  for word in "$@"; do
    case ${word} in
      --) return 1 ;;
      - | -a | --all | -1 | --one-column | -h | --help | -V | --version | -L | -P) ;;
      -*) return 0 ;;
    esac
  done

  return 1
}

#######################################
# Tell whether a cd command line takes the two-word form of the cd of zsh,
# which puts the second word in place of the first in the path,
# as in `cd old new`; cdl would take it for two directories.
#
# Arguments:
#   $@: Arguments of cd.
#
# Returns:
#   0 for that form in zsh; 1 otherwise.
#######################################
function __cdl_is_zsh_two_word_cd() {
  [[ -n ${ZSH_VERSION-} ]] && (($# == 2)) && [[ $1 != -* && $2 != -* ]]
}

#######################################
# Run cdl in place of cd (see __cdl_cd); defined with CDL_REPLACE_CD=1.
#
# Arguments:
#   $@: Arguments of cd.
#######################################
function __cdl_define_cd() {
  function cd() {
    __cdl_cd "$@"
  }
}

if [[ ${CDL_REPLACE_CD-} == 1 ]]; then
  __cdl_define_cd
fi

# endregion

# region Execution guard

#######################################
# Report whether this file runs as a script instead of being sourced.
#
# Only a sourced function can change the parent shell's directory,
# so running the file directly would do nothing useful.
# Detecting "sourced vs executed" is shell-specific:
#   - zsh:  ZSH_EVAL_CONTEXT contains ':file' while a file is sourced;
#   - bash: BASH_SOURCE[0] equals $0 only when the file is executed.
#
# Returns:
#   0 if the file was executed; 1 if it was sourced.
#######################################
function __cdl_is_executed() {
  if [[ -n ${ZSH_VERSION-} ]]; then
    [[ ${ZSH_EVAL_CONTEXT-} != *:file* ]]
  else
    [[ ${BASH_SOURCE[0]} == "$0" ]]
  fi
}

if __cdl_is_executed; then
  __cdl_error "cdl.sh must be sourced, not executed. Run: source '$0'" \
    "${CDL_ERR_NOT_SOURCED}" || exit "$?"
fi

unset -f __cdl_is_executed

# endregion

### End
