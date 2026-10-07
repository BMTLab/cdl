# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog][keepachangelog],
and this project adheres to [Semantic Versioning][semver].

## [Unreleased]

## [2.0.0] - 2026-10-07

### Fixed

- Columns stay aligned with names in any script.
  Widths are measured in screen cells instead of bytes:
  Cyrillic letters take one cell, CJK characters and emoji take two,
  and combining marks take none.
  The rule holds in gawk, mawk and busybox awk alike.
- `cdl -- DIR` enters `DIR`; it used to go to `$HOME` instead.
- A second operand is an error now, and an option after the directory
  says that options go first;
  an unquoted path with a space used to lose its second half without a word.
- An empty operand, as from an empty substitution
  like `cdl "$(xclip -o)"` with nothing in the clipboard,
  is an error now instead of a jump to `$HOME`.
- `cdl` without an operand reads a path from stdin only when stdin is a pipe.
  It used to read any stdin that was not a terminal,
  so inside a `while read` loop it swallowed the lines of the loop.
- The listing has no escape sequences when it goes to a file or a pipe,
  and `NO_COLOR` turns colors off.
- Errors say why `cd` failed, and which part of the path is to blame:
  no such directory, not a directory, or permission denied.
  They used to share one message.
- A path piped into cdl gets the real terminal width;
  `tput` saw no terminal there and fell back to 80 columns.
- Device files (`/dev`) show their "major, minor" numbers as the size;
  the extra field used to shift the date into the name.
- Names keep their runs of spaces; they used to collapse into one.
- Control characters in names show as `?`, like `ls -q` shows them,
  so a crafted file name cannot drive the terminal.
  A name holding a newline stays on one row.
- `QUOTING_STYLE` in the environment no longer changes how names show;
  it used to wrap names with spaces in quotes.
- A shell running with `set -e` no longer dies when `tput` fails.
- `sh cdl.sh` stops with a message and `CDL_ERR_NOT_SOURCED`;
  it used to print `[[: not found` and return 0.
- An unreadable directory (searchable, but not readable) is entered
  and reported with the new `CDL_ERR_LIST`; cdl used to return 0.
- The README described `cdl ~` as a jump to the previous directory
  (that is `cdl -`) and claimed there were no external dependencies
  (cdl needs `awk`, and `tput` without `COLUMNS`).
  It also said a piped path never changes the directory,
  which is true for bash but not for zsh.

### Changed

- The listing takes as many columns as fit the terminal,
  filled top to bottom like `ls`;
  it used to show two columns at most, and only from 100 columns up.
- Return codes go by tens: the tens digit names what failed,
  and the units digit why,
  so a new reason never moves the codes a script checks.
  Each reason cdl cannot enter a directory has a code of its own,
  where 1.0 returned 2, `CDL_ERR_CHDIR`, for all of them:

  | Code | Name                    | Reason                                          |
  |------|-------------------------|-------------------------------------------------|
  | 30   | `CDL_ERR_CHDIR`         | `cd` refused the directory for another reason   |
  | 31   | `CDL_ERR_NOT_FOUND`     | No such directory; `cdl -` with no previous one |
  | 32   | `CDL_ERR_DENIED`        | It, or a directory above it, may not be entered |
  | 33   | `CDL_ERR_NOT_DIRECTORY` | A file where the path needs a directory         |

  `$(( $? / 10 ))` is 3 for all four.
  `CDL_ERR_NOT_SOURCED` is 50 instead of 3,
  and `CDL_ERR_GENERAL` (1) is gone.
- Error messages start with `cdl:` instead of `ERROR:`.
- Sizes read like those of GNU `ls -h` with any `ls`:
  cdl writes them from the byte counts.
  uutils `ls`, the default of Ubuntu 26.04, wrote `1024K`
  for a file just under 1 MiB, where GNU writes `1.0M`.
- Names sort by bytes (uppercase first) with every `ls`,
  as they already did with GNU `ls`; the README says so now.
- A call is faster, for all the new work it does:
  on a small directory, 5.2 ms instead of 7.0 in bash,
  and 6.1 ms instead of 6.9 in zsh.
  cdl probes `ls` once per shell session instead of once per call,
  reads the terminal width from `COLUMNS`,
  lays the listing out with `mawk` when it is installed,
  and hands its awk program over in a here-document.

### Added

- Settings in environment variables, checked before cdl moves:
  `CDL_COLOR` (`auto`, `always`, `never`), `CDL_HIDDEN` (`1`, `0`)
  and `CDL_WIDTH`.
  `CDL_COLOR=always` keeps the colors in `cdl | less -R`
  and wins over `NO_COLOR`, as no-color.org asks.
- `cdl --version` (`-V`), and `-L` and `-P`, passed to `cd`;
  the last of `-L` and `-P` wins, in bash and zsh alike.
- A long listing on a terminal is cut at the terminal height,
  with a last line that says how many entries were left out;
  `-a` (`--all`) shows everything, and a file or a pipe is never cut.
- `-1` (`--one-column`), `CDL_MAX_ROWS` and `CDL_MAX_COLUMNS`
  shape the grid.
- A header line over the listing on a terminal:
  the directory, with `~` for HOME, its git branch,
  read from `.git/HEAD` without running git,
  and how many directories, files and bytes it holds.
  `CDL_HEADER` (`auto`, `always`, `never`) and `CDL_GIT` (`1`, `0`) control it.
- A file as the operand: cdl enters the directory that holds it
  and marks it in the listing, which moves to show it when a cut would hide it.
  It used to fail.
- `file://` URIs, as file managers copy them, and a leading `~`
  that the shell did not expand, as in a quoted or piped path.
- Names as hyperlinks (OSC 8) to their files on a terminal with colors,
  and the header path to its directory;
  `CDL_LINKS` (`auto`, `always`, `never`) controls them.
- `cdl_list` lists the current directory without moving:
  the stable entry point for shell setups that wrap `cd`.
  It takes `-a` and `-1` too.
  `__cdl_print_listing`, the name the 1.0 README used, still works.
- `CDL_REPLACE_CD=1`, set before sourcing, makes `cd` run cdl on a terminal,
  with its options, files, listing and Tab completion.
  Where `cd` writes to no terminal, as in `$(cd dir && pwd)`,
  it stays the shell's own, and so do the forms only zsh knows,
  `cd -2` and `cd old new`.
- Tab completion for `cdl` and `cdl_list` in bash and zsh:
  the options, then the directories and files a word begins,
  and the directories under `CDPATH`.
- `cdl.plugin.zsh`, the file zsh plugin managers load.
- Return codes `CDL_ERR_USAGE` (10) for a bad option or operand,
  `CDL_ERR_SETTING` (20) for an invalid setting,
  and `CDL_ERR_LIST` (40) for a directory entered but not listed in full.
- A test suite that runs cdl in bash and zsh,
  with GNU, uutils and BSD `ls`, and with gawk, mawk and busybox awk;
  a Makefile; continuous integration on Linux and macOS;
  git hooks that check each commit and its message (`make hooks`).
- The width table comes from the Unicode database of Python
  through `tools/gen-width-table.py`.

## [1.0.1] - 2026-07-05

### Added

- zsh support: executing the file under zsh is rejected
  with `CDL_ERR_NOT_SOURCED`, as it already was under bash.

### Changed

- The shebang is `#!/usr/bin/env bash`.

## [1.0.0] - 2025-11-21

### Added

- First release: `cdl` changes directory and prints a compact listing,
  in two columns when they fit the terminal.

[keepachangelog]: https://keepachangelog.com/en/1.1.0/
[semver]: https://semver.org/spec/v2.0.0.html
[Unreleased]: https://github.com/BMTLab/cdl/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/BMTLab/cdl/compare/5f79e8d...v2.0.0
[1.0.1]: https://github.com/BMTLab/cdl/compare/v1.0.0...5f79e8d
[1.0.0]: https://github.com/BMTLab/cdl/releases/tag/v1.0.0
