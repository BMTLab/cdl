# Working in this repository

cdl is one shell file, `cdl.sh`, sourced into bash 3.2+ or zsh 5.0+,
with an awk program inside it, a bats suite around it,
the tools of the repository in `tools/`, and a thin CI in `.github/`.
This file holds the house rules for every change here,
whether a person or an agent makes it.
The rules of one part of the repository live in `.claude/rules/`,
and Claude Code loads each one when a session reads a file of that part.
CONTRIBUTING.md is the short public version of the same rules.

## Map

- `cdl.sh`: the helper; its regions follow this list.
- `cdl.plugin.zsh`: the file zsh plugin managers load,
  one line that sources `cdl.sh`.
- `tests/`
  - `unit`: the formatter, fed with canned `ls -l` lines.
  - `integration`: cdl end to end, once per shell in `TEST_SHELLS`;
    `test_budget.bats` counts the commands of a call.
  - `style`: the rules a machine can check, the facts several files share,
    the release steps (`test_release.bats`),
    and the command lines and the guard of the tools (`test_tools.bats`).
  - `support`: the helpers every test loads through `test_helper.bash`;
    in `bin/`, the width oracle and the zsh completion driver.
- `tools/`
  - `gen-width-table.py`: generates the width table in `cdl.sh`
    from the Unicode data of Python.
  - `bench.sh`: times one cdl call against a plain `cd` and `ls`.
  - `release-notes.sh`: prints the CHANGELOG section of a version,
    the body of its GitHub release.
  - `ci/`: the scripts that the jobs of CI run,
    which `.claude/rules/ci.md` names.
- `docs/demo`: the GIF of the README, which `make demo` records
  from `demo.tape`; `setup.bash` builds what it shows.
- `.github/`: the workflows, Dependabot, zizmor and actionlint,
  which `.claude/rules/ci.md` names.
- `.claude/rules/`: the rules of one part each,
  with the paths in its header that load it:
  `code.md` for every script, `tests.md`, `tools.md`, `ci.md`, `release.md`.
- `Makefile`: every task; `make help` lists them.
- `.pre-commit-config.yaml`, `committed.toml`: the git hooks of `make hooks`,
  which check only what a commit adds and its message.
- `.editorconfig`, `.shellcheckrc`, `.rumdl.toml`:
  the sources of the formatting and lint rules,
  for editors, `make` and CI alike.

The regions of `cdl.sh` read top to bottom:

1. Version and error codes
2. Shell check
3. Session state
4. Messages
5. Settings
6. Input
7. Paths
8. Navigation
9. Terminal
10. Header
11. Tool detection
12. Listing
13. Formatter, an awk program with regions of its own:
    Layout, Parsing, Links, Text measurement, Width table
14. Public API
15. Completion
16. Replacing cd
17. Execution guard

## Before and after a change

- Run `make check`: it must be green before you start and after you finish.
  `make hooks` once per clone makes every commit check what it adds
  and its message; the linters and the tests stay in `make check`.
  On macOS add the system shell, which is bash 3.2:
  `make test TEST_SHELLS='/bin/bash zsh'`.
- The width table between `# region Width table`
  and `# endregion Width table` is generated.
  Change `tools/gen-width-table.py` and run `make widths`; never edit the table.
- `cdl` runs on every directory change, so it has a budget:
  nothing external runs when the file is sourced,
  one listing runs `ls` once and `awk` once, `tput` only without `COLUMNS`,
  and the `ls` and `awk` probes run once per shell session.
  Measure with `make bench` when you touch the listing path.
- The GIF of the README shows real listings:
  when the listing looks different, record it again with `make demo`.
- Every new rule of behavior has a test named after that rule,
  and every fixed bug a test that fails on the old code
  (`.claude/rules/tests.md`).
- The file header, `cdl --help`, the README and the CHANGELOG
  agree with the code (`.claude/rules/release.md`).

## Language and punctuation

- English (en-US) for code, comments, messages and documentation.
- Never the em-dash (U+2014); a style test rejects it in every file.
  Use a colon, a comma or a new sentence.

## Comments

Comments are prose.
They explain why and what is not obvious; the code already says what it does.

- Write complete sentences.
  A function summary starts in the imperative mood
  ("Return the screen cells", not "Returns").
- Keep a comment beside the code it describes and change both together.
- Break a line only where a reader would pause:
  after a sentence; after a comma, a semicolon or a colon;
  before a conjunction (and, or, but, so, because, while, if);
  before a relative pronoun (that, which, who);
  or before a preposition that opens a phrase (with, into, for, by).
- Break a line before or after a tight unit, never inside one:
  an article and its noun (`the` / `token`), an adjective and its noun,
  a subject and its verb (`the run summary` / `makes`),
  a verb and its object (`references` / `the file`),
  an auxiliary and its verb (`must not` / `go`),
  a multi-word preposition (`instead` / `of`).
  A line never ends on a preposition or a conjunction
  (`published by` /, `and` /).
- Keep the lines of one comment about as wide as each other:
  shell files sit around 50 to 72 columns, Python up to 99,
  Markdown prose up to 80.

The same rules hold for docstrings, Markdown, help texts and commit messages.

Markdown also follows `.rumdl.toml`, which `make lint-md` applies:
prose of at most 80 columns, tables aligned so their source reads
like the rendered page, `### Fixed` and its kin repeated only per version.
A table holds short cells; a longer explanation goes below it, as a list.

## Exit codes

The return codes of `cdl.sh` are a public API, apart from the tools.
The tens digit names what failed, and the units digit why:
`CDL_ERR_CHDIR` (30) when a directory cannot be entered,
`CDL_ERR_NOT_FOUND` (31) when that is because it does not exist.
A new reason takes the next free code in the ten of its category,
and a new category the next free ten, below 126;
a code keeps its value within a major version.
The file header, `cdl --help` and the README document every code,
and a style test holds the scheme.
Every other script of the repository, a tool,
owns a block of ten exit codes (`.claude/rules/tools.md`).

## Git

- One branch, `main`.
  A work branch exists only to open a pull request,
  and is deleted after the merge.
- Commits are signed.
  The message says what changed and why, in the imperative mood,
  with a first line of at most 72 characters.
- The commit-msg hook checks the form of every message
  against `committed.toml` and the message hooks of `.pre-commit-config.yaml`:
  a capitalized subject without a full stop, a blank line after it,
  a body wrapped at 72, trailers that git parses,
  no WIP or `fixup!` commits, no em-dash.
  A URL longer than that ends its line: only a last word may run over.
  Never skip the hooks with `--no-verify`; fix what they name.
- Nothing is committed with a red `make check`,
  and `.idea/` or other generated noise is never committed.
