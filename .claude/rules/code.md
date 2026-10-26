---
paths:
  - "cdl.sh"
  - "cdl.plugin.zsh"
  - "tools/**"
  - "tests/**"
  - "docs/demo/setup.bash"
  - "Makefile"
---

# Code

The rules of every script of the repository:
`cdl.sh` with its awk program, the tools, the tests and the Makefile.

## Quotes and names

- Single quotes for literal strings in shell;
  double quotes only when something inside expands
  or the text holds a single quote.
- Braces around every variable (`"${name}"`, `"${directory}/${file}"`)
  and double quotes around every expansion, even a safe one.
  ShellCheck enforces both through `.shellcheckrc`
  (`require-variable-braces`, `quote-safe-variables`);
  `shellcheck -f diff FILE | patch -p1` applies its own fixes.
- The same holds where ShellCheck cannot see:
  inside `[[ ]]`, in the subject of `case`,
  and in the code strings that tests and tools hand to a shell.
  The right side of `==`, `!=` or `=~` stays unquoted
  only when it is a pattern on purpose.
- A name says in full what the thing is, however long that makes it:
  `entry_size`, `__cdl_terminal_width`, `assert_two_columns_aligned`;
  `directory`, never `dir`. Common terms keep their short form
  (ID, URL, JSON, MIME, PID, hex), and a name that mirrors a public one
  keeps its words, as `__cdl_setting_max_rows` does `CDL_MAX_ROWS`.
- A function that answers yes or no with its status, and a flag of 0 or 1,
  open their names with the question: `is_`, `has_`, `can_` or `should_`,
  right after the prefix (`__cdl_is_gnu_ls`, `is_colored`).

## File headers

- A script opens with a card, which a reader judges at a glance:
  one sentence in the imperative mood, what the script does,
  then the keys that apply, in this order, a line each:
  `Usage:`, `Effects:`, `Dependencies:`, `Settings:`, `Exit codes:`, `See:`.
  `How it works:` follows, only for what the code does not show,
  and `# Version:` closes the card.
- `Effects:` lists every change outside the script,
  and how to run it without one, or that there is no such way.
  `Settings:` holds the variables a user sets, with their defaults;
  a variable it only reads to learn where it runs belongs in How it works.
  `Exit codes:` names each code;
  a tool without `--help` and a README of its own says there what it means.
- A test file or a support module opens with one sentence,
  what it tests or gives, and a short paragraph where a reader needs one;
  it takes no keys and no version.
- Nothing else goes into a header: git knows the author and the date,
  the path names the file, and LICENSE holds the license.
  A style test checks both kinds.

## Regions

- A file longer than a screen folds
  into `# region Name` ... `# endregion Name` blocks,
  with one blank line inside each marker.
  The end repeats the name, so a reader who lands on it knows what closes there.
  The markers balance and their names match in every file; a style test checks.
- One region holds one concern.
  New code goes into the region of its concern,
  or into a new region placed where a reader meets the concern first.
- The awk program inside `cdl.sh` uses the same markers for its own regions.
  The Width table region holds only the generated block.

## Functions

- One function, one job, named by that job.
  A function whose summary needs a paragraph is two functions.
- A blank line separates the logical parts of a body:
  the declarations, then each step, then the result.
  A `return` that follows a block gets a blank line before it.
  The simple cases return early, at the top.
- Helpers instead of nesting: a condition or a loop body that needs a name
  becomes a function with that name, rather than one more level of indentation.
- Constants instead of magic numbers:
  `TWO_COLUMN_MIN_WIDTH = 100`, never a bare `100`.
- Every function carries a documentation header:
  the fenced Google-style block in shell
  (summary, Arguments, Globals, Inputs, Outputs, Returns, those that apply),
  a numpydoc docstring in Python,
  a comment line above an awk function.

### Shell

- `function name() { ... }`, never `name() { ... }`.
- The `local` declarations open the body, as one block;
  under zsh, an entry point runs `emulate -L zsh` before them.
  `local -r`, `local -i`, `local -ir` and `local -a` wherever they fit;
  a bare `local` only for a value that changes.
  A value that a later step makes, from `$(...)` or from `REPLY`,
  is declared in the block and assigned in its step,
  since `local` would hide the status of a command.
- A result travels in `REPLY` and the caller declares `local REPLY`;
  `$(...)` costs a fork, which the listing path cannot afford.
- External commands run through `command`,
  so aliases and functions of the user cannot replace them;
  `cd` is always `builtin cd --`.
- Errors go through `__cdl_error` with a named `CDL_ERR_*` code,
  in place of a bare `echo >&2` or a bare number.
  Every path that can fail returns a code the file header documents.
- `cdl.sh` runs in bash 3.2 and zsh 5.0, so it avoids
  `local -n`, `declare -A`, `mapfile`, `${var,,}`, `${var^}`, `|&`, `;;&`,
  negative array indexes and `EPOCHREALTIME`.
  Under zsh an entry point starts with `emulate -L zsh`;
  nothing else sets options.
  The sourced file never uses `set -e`, `set -u` or `set -o pipefail`:
  it survives whatever options the shell of the user runs with,
  and changes none of them.
- Sourcing runs no external command and is safe to repeat:
  the `readonly` codes are guarded, the probes start fresh.

### awk

- POSIX awk only,
  because the program runs under gawk, mawk, busybox awk (1.34 and later,
  as the parser of 1.30 loses functions) and BSD awk:
  no `gensub`, `strftime`, `length(array)`, `\x` escapes
  or regex intervals (`{n}`).
- Byte mode: `cdl.sh` runs awk under `LC_ALL=C` and decodes UTF-8 by hand.
- The locals of a function come after four spaces in its parameter list:
  `function widest(first, last,    i, max)`.
- A function that sets globals names them in its comment.

### Python (`tools/`)

- Standard library only; runs on Python 3.10 and later.
- Type hints on every signature, numpydoc docstrings, `# region` markers,
  and the same card as a script (see "File headers").
- Clean under ruff with every rule group, preview,
  a line length of 99 and numpy docstrings,
  and under `mypy --strict`.
- Constants at the top, exit codes named (see `tools.md`),
  output through `sys.stdout.write` and errors through `sys.stderr.write`;
  a wrong command line exits with the first code of the block.
