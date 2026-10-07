# Working in this repository

cdl is one shell file, `cdl.sh`, sourced into bash 3.2+ or zsh 5.0+,
with an awk program inside it, a bats suite around it,
the tools of the repository in `tools/`, and a thin CI in `.github/`.
This file holds the house rules for every change here,
whether a person or an agent makes it.
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
    and the release steps (`test_release.bats`).
  - `support`: the helpers every test loads through `test_helper.bash`;
    in `bin/`, the width oracle and the zsh completion driver.
- `tools/`
  - `gen-width-table.py`: generates the width table in `cdl.sh`
    from the Unicode data of Python.
  - `bench.sh`: times one cdl call against a plain `cd` and `ls`.
  - `release-notes.sh`: prints the CHANGELOG section of a version,
    the body of its GitHub release.
  - `ci/install-tools.sh`: installs the CI tools, pinned
    (see "Continuous integration").
  - `ci/common.sh`: what the CI scripts share:
    `ci_error` (a GitHub annotation and a code) and `sha256_of`.
  - `ci/report-environment.sh`: writes the tool versions of a job
    into its summary.
  - `ci/release.sh`: the release steps, one command each:
    `check`, `notes`, `assets`, `publish`, `verify`.
- `docs/demo`: the GIF of the README, which `make demo` records
  from `demo.tape`; `setup.bash` builds what it shows.
- `.github/`
  - `workflows`: `ci-main.yml` calls the reusable
    `ci-lint`, `ci-workflow-lint`, `ci-test` and `ci-release`.
  - `dependabot.yml`: weekly grouped updates of the actions
    and the hook repositories, after a seven-day cooldown.
  - `zizmor.yml`: the one zizmor finding this repository accepts.
  - `actionlint.yaml`: the runner label actionlint does not know yet.
- `Makefile`: every task; `make help` lists them.
- `.pre-commit-config.yaml`, `committed.toml`: the git hooks of `make hooks`,
  quick checks before a commit, then the rules of its message.
- `.editorconfig`, `.shellcheckrc`, `.markdownlint-cli2.jsonc`:
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
  `make hooks` once per clone makes every commit run the quick checks
  of `.pre-commit-config.yaml`, `make smoke` among them;
  they catch the common slips early and never replace `make check`.
  On macOS add the system shell, which is bash 3.2:
  `make test TEST_SHELLS='/bin/bash zsh'`.
- The width table between `# region Width table` and `# endregion` is generated.
  Change `tools/gen-width-table.py` and run `make widths`; never edit the table.
- `cdl` runs on every directory change, so it has a budget:
  nothing external runs when the file is sourced,
  one listing runs `ls` once and `awk` once, `tput` only without `COLUMNS`,
  and the `ls` and `awk` probes run once per shell session.
  Measure with `make bench` when you touch the listing path.
- The GIF of the README shows real listings:
  when the listing looks different, record it again with `make demo`.

## Language and punctuation

- English (en-US) for code, comments, messages and documentation.
- Never the em-dash (U+2014); a style test rejects it in every file.
  Use a colon, a comma or a new sentence.
- Single quotes for literal strings in shell;
  double quotes only when something inside expands
  or the text holds a single quote.
- Braces around every variable (`"${name}"`, `"${dir}/${file}"`)
  and double quotes around every expansion, even a safe one.
  ShellCheck enforces both through `.shellcheckrc`
  (`require-variable-braces`, `quote-safe-variables`);
  `shellcheck -f diff FILE | patch -p1` applies its own fixes.
- A name says what the thing is:
  `entry_size`, `__cdl_terminal_width`, `assert_two_columns_aligned`.

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
- Never split a tight unit across two lines:
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

Right:

```bash
# We pin actions to an exact tag
# so Dependabot opens a PR when a new version is released.
```

Wrong, because `a` / `PR` splits an article from its noun:

```bash
# We pin actions to an exact tag so Dependabot opens a
# PR when a new version is released.
```

The same rules hold for docstrings, Markdown, help texts and commit messages.

Markdown also follows `.markdownlint-cli2.jsonc`, which `make lint-md` applies:
prose of at most 80 columns, tables aligned so their source reads
like the rendered page, `### Fixed` and its kin repeated only per version.
A table holds short cells; a longer explanation goes below it, as a list.

## Regions

- A file longer than a screen folds
  into `# region Name` ... `# endregion` blocks,
  with one blank line inside each marker.
  The markers balance in every file; a style test checks.
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
- `local -r`, `local -i`, `local -ir` and `local -a` wherever they fit;
  a bare `local` only for a value that changes.
- A result travels in `REPLY` and the caller declares `local REPLY`;
  `$(...)` costs a fork, which the listing path cannot afford.
- External commands run through `command`,
  so aliases and functions of the user cannot replace them;
  `cd` is always `builtin cd --`.
- Errors go through `__cdl_error` with a named `CDL_ERR_*` code,
  never through a bare `echo >&2` or a bare number.
  Every path that can fail returns a code the file header documents.
- `cdl.sh` runs in bash 3.2 and zsh 5.0, so it avoids
  `local -n`, `declare -A`, `mapfile`, `${var,,}`, `${var^}`, `|&`, `;;&`,
  negative array indexes and `EPOCHREALTIME`.
  Under zsh an entry point starts with `emulate -L zsh`;
  nothing else sets options.
  The sourced file never uses `set -e`, `set -u` or `set -o pipefail`:
  it survives whatever options the shell of the user runs with,
  and changes none of them.
- The strict mode opens every standalone script
  (`tools/*.sh`, `tests/support/bin/*`):
  `set -o errexit -o nounset -o pipefail`.
- Sourcing runs no external command and is safe to repeat:
  the `readonly` codes are guarded, the probes start fresh.

### awk

- POSIX awk only,
  because the program runs under gawk, mawk, busybox awk and BSD awk:
  no `gensub`, `strftime`, `length(array)`, `\x` escapes
  or regex intervals (`{n}`).
- Byte mode: `cdl.sh` runs awk under `LC_ALL=C` and decodes UTF-8 by hand.
- The locals of a function come after four spaces in its parameter list:
  `function widest(first, last,    i, max)`.
- A function that sets globals names them in its comment.

### Python (`tools/`)

- Standard library only; runs on Python 3.10 and later.
- Type hints on every signature, numpydoc docstrings, `# region` markers,
  and the same `# Name / # Author / # License / # Description` header
  as a shell file.
- Clean under ruff with the ScriptsLib profile
  (every rule group, preview, line length 99, numpy docstrings)
  and under `mypy --strict`.
- Constants at the top, exit codes named (see "Exit codes" below),
  output through `sys.stdout.write` and errors through `sys.stderr.write`;
  a wrong command line exits with the first code of the block.

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
owns a block of ten exit codes, which no other tool uses,
so a code in a CI log names its script and its reason at once.
A tool names its codes after itself (`RELEASE_ERR_VERSION`),
gives the first of its block to a wrong command line when it has one,
and documents every code in its header.
A style test holds the rule: no code named twice, no file across two blocks,
no block shared.

| Codes | File                                | Names                   |
|------:|-------------------------------------|-------------------------|
| 10-19 | `tools/ci/install-tools.sh`         | `INSTALL_ERR_*`         |
| 20-29 | `tools/ci/release.sh`               | `RELEASE_ERR_*`         |
| 30-39 | `tools/release-notes.sh`            | `NOTES_ERR_*`           |
| 40-49 | `tools/bench.sh`                    | `BENCH_ERR_*`           |
| 50-59 | `tools/gen-width-table.py`          | `EXIT_*`                |
| 60-69 | `tests/support/bin/zsh-completions` | `ZSH_COMPLETIONS_ERR_*` |
| 70-79 | `Makefile`                          | `MAKE_ERR_*`            |

The codes of the Makefile belong to its recipes.
A new tool takes the next free block, 80-89, and a line in this table.
Codes stay below 126, where the shell's own codes begin.
make itself exits with 2 whenever a recipe fails;
the code of the recipe shows in its error line (`Error 71`).

## Tests

- A test states one rule in its name, as a sentence without "should":
  `a second operand fails with CDL_ERR_USAGE instead of being ignored`.
  It checks the rule, never the shape of the code.
- Every test has the sections `# Arrange`, `# Act` and `# Assert`,
  in that order; an empty section keeps its comment with the reason
  (`# Arrange: no fixtures needed.`).
- A unit test feeds the formatter canned `ls -l` lines from `fixtures.bash`.
  An integration test builds a real directory with `make_entries`
  under the sandbox `HOME`,
  and runs cdl through `in_shell` in the shell under test.
- A rule that holds for several inputs is one parameterized test
  (`bats_test_function` over a list of samples), not copies;
  each sample carries the description that names the test.
- A style test collects every violation first,
  and fails once with the whole list.
- The width oracle `tests/support/bin/screen-cells` stays independent
  of the width table in `cdl.sh`; extend both when the samples gain a script.
- A fixed bug gets a test that fails on the old code;
  a new behavior gets its test before the README mentions it.
- `# bats test_tags=smoke` marks the quick tests of the main paths of cdl,
  which `make smoke` and the pre-commit hook run.
  Tag a test only when it is fast and covers a path no tagged test does,
  and prefer the files that already hold one:
  every file adds to the run, so `make smoke` stays within a few seconds.

## Continuous integration

- The YAML is thin. A step is one line that calls a script in `tools/ci`
  or a `make` target; the logic lives in the script, with the same shape
  as every other shell file here: a documentation header, functions,
  named exit codes from its own block (see "Exit codes"), one job per function.
  A step that works on a laptop works in CI, and a failure names itself.
- `ci-main.yml` is the entry point: pushes to `main`, version tags,
  pull requests, a weekly run that catches a drifting runner image,
  and manual runs.
  It calls the reusable workflows with `./`, which nektos/act understands;
  zizmor's `self-repository` audit is ignored for that one file
  in `.github/zizmor.yml`.
- Every action is pinned to a commit, with its version in a comment,
  for example:
  `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1`.
  Dependabot moves the commit and the comment together,
  and does the same for the hook repositories of `.pre-commit-config.yaml`.
  A new action gets the same treatment, and `permissions` stay empty at the top
  and minimal per job.
- The tools a job uses are pinned too: shellcheck, shfmt and actionlint
  by version and SHA-256 for both Linux architectures,
  bats-core by tag and commit;
  a download reaches the PATH only after its digest matches.
  To move one, change the version,
  and take the new digests from the release page.
- The test matrix covers what cdl promises: Ubuntu 26.04 (uutils ls),
  24.04 (GNU ls), 22.04 (the oldest bash and zsh), and macOS 26 twice,
  with the BSD ls and `/bin/bash` 3.2, then with Homebrew's gls.
  Lint runs on Ubuntu 26.04 because its Python ships the Unicode version
  the width table was generated from, so `--check` really compares there.
- actionlint and zizmor check the workflows on every run; keep both silent.
- The lint job runs markdownlint through `DavidAnson/markdownlint-cli2-action`,
  which bundles its dependencies, pinned by its commit;
  a laptop runs markdownlint-cli2 with the same markdownlint inside
  (`markdownlint-cli2 --help` names it), so the two judge alike.
  actionlint runs as a pinned binary, not through reviewdog,
  so it also works for pull requests from forks.
- A release publishes through `gh`, then verifies its own build provenance.
- Run the workflows locally with `act` before pushing CI changes
  (`act -W .github/workflows/ci-main.yml -j lint`;
  job names repeat across files).
  act ignores the `runs-on` of a matrix and runs every leg in a Linux container,
  where the macOS legs fail for want of zsh and mark the whole matrix failed;
  so pick the Ubuntu legs, as in `-j test --matrix 'name:Ubuntu 24.04, GNU ls'`
  (one `--matrix` per leg). act cannot upload artifacts;
  everything else must pass.

## Versions, changelog, release

- The version lives in the `# Version:` and `# Date:` lines of `cdl.sh`.
  `CHANGELOG.md` has a `## [X.Y.Z] - YYYY-MM-DD` section for it
  (a style test checks),
  and the release tag `vX.Y.Z` sits on the commit that bumps them.
- The changelog follows Keep a Changelog: Fixed, Changed, Added.
  One entry per behavior a user can notice, written for that user,
  with the old behavior named.
- Every return code appears in the file header, in `cdl --help`
  and in the README (a style test checks).

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
  a body wrapped at 72, no WIP or `fixup!` commits, no em-dash.
  A URL longer than that ends its line: only a last word may run over.
  Never skip the hooks with `--no-verify`; fix what they name.
- Nothing is committed with a red `make check`,
  and `.idea/` or other generated noise is never committed.

## Review checklist

Before a change is called done, and when one is reviewed:

1. `make check` is green in every shell of `TEST_SHELLS`.
2. Every new rule of behavior has a test named after that rule.
3. Comments explain why, break at phrase boundaries
   and match the code beside them.
4. Functions are small and documented,
   and separate their logical parts with blank lines.
5. The listing path gained no fork; `make bench` shows no regression.
6. The file header, `--help`, the README and the CHANGELOG agree with the code.
7. The width table was regenerated if the generator changed.
