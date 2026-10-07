# Contributing to cdl

Thank you for helping. Bug reports, fixes and ideas are all welcome.

## Reporting a bug

Open an [issue](https://github.com/BMTLab/cdl/issues/new/choose)
with the bug report form. The most useful reports name:

- the version of cdl (`cdl --version`);
- the shell and its version (`bash --version`, `zsh --version`);
- the `ls` in use (`ls --version`, or "BSD ls" on macOS) and the `awk`;
- the smallest sequence of commands that shows the problem.

Report security issues privately, as [SECURITY.md](./SECURITY.md) explains.

## Setting up

You need bash, zsh, [bats-core](https://github.com/bats-core/bats-core) 1.11+,
[ShellCheck](https://www.shellcheck.net), [shfmt](https://github.com/mvdan/sh)
and [markdownlint-cli2](https://github.com/DavidAnson/markdownlint-cli2)
(`npm install --global markdownlint-cli2`);
Python 3 runs the generator of the width table and its tests.
[pre-commit](https://pre-commit.com) runs the git hooks
(`pipx install pre-commit` or `uv tool install pre-commit`).
`make demo` records the GIF of the README
with [vhs](https://github.com/charmbracelet/vhs),
which also needs ttyd and ffmpeg.

```bash
make deps     # shows what is installed and what is missing
make hooks    # installs the git hooks, once per clone
make check    # lint, Markdown lint, format check and every test, as CI runs it
```

Before each commit, the hooks lint the staged files
and run the style tests and `make smoke`, in a few seconds;
then they check the commit message.
`make check` stays the full gate.

## How cdl is built

`cdl.sh` is one file, sourced into bash or zsh,
and its `# region` blocks read top to bottom:

1. **Version and error codes** and the **shell check**:
   POSIX code, so `sh` stops cleanly.
2. **Session state**, **Messages** and **Settings**:
   what the probes learned, the help and the errors,
   and the `CDL_*` variables, read and checked on every call.
3. **Input**, **Paths** and **Navigation**: pick the target
   (operand, piped path, `$HOME`), read a `file://` URI or a leading `~`,
   and enter it with `builtin cd`, or the directory of a file.
4. **Terminal**, **Header** and **Tool detection**:
   width, height and colors, the directory and git branch for the header,
   and which `ls` and `awk` to run, probed once per shell session.
5. **Listing**: run `ls -l` with a pinned time style in the C locale.
6. **Formatter**: an awk program that parses each line,
   makes names safe for the terminal, measures them in screen cells,
   writes the header and the hyperlinks,
   and lays the entries out in as many columns as fit.
7. **Public API**, **Completion** and **Replacing cd**:
   `cdl`, `cdl_list`, their Tab completion in bash and zsh,
   and the `cd` of `CDL_REPLACE_CD`, then the **execution guard**.

The width table at the end of the formatter is generated:
edit `tools/gen-width-table.py`, never the table,
and run `make widths` to rewrite it from Python's Unicode database.

## Tests

The suite lives in `tests/`:

| Directory           | What it covers                                                      |
|---------------------|---------------------------------------------------------------------|
| `tests/unit`        | The formatter, fed with canned `ls -l` lines.                       |
| `tests/integration` | cdl end to end: navigation, pipes, listing, `ls` flavors, rc files. |
| `tests/style`       | The code style rules and the facts several files share.             |
| `tests/support`     | Helpers loaded by every test (see `test_helper.bash`).              |

Every unit and integration test runs once per shell in `TEST_SHELLS`:
`make test TEST_SHELLS='bash zsh /bin/bash'`.
Each test starts from a sandbox (its own `HOME`, `PATH`, locale and terminal),
where fakes stand in for BSD `ls`, `gls` and other awks
(see `tests/support/fakes.bash`).

A good test states one rule in its name
(`a second operand fails with CDL_ERR_USAGE instead of being ignored`)
and follows the Arrange, Act and Assert sections.
Prefer one parameterized test over copies:
see `bats_test_function` in `tests/unit/test_formatter.bats`.

A few quick tests, one or two for each main path of cdl,
carry the tag `# bats test_tags=smoke`.
`make smoke` runs only them, in every shell of `TEST_SHELLS`,
and so does the pre-commit hook.

## Commit messages

The commit-msg hook holds every message to the same form,
the rules of `committed.toml` and of the message hooks
in `.pre-commit-config.yaml`:

- a subject of at most 72 characters, capitalized, without a full stop,
  starting with a verb in the imperative mood:
  "Fix", never "Fixed", "Fixes" or "Fixing";
- a blank line, then a body wrapped at 72 columns
  that says what changed and why;
  a longer URL ends its line, since only a last word may run over;
- no WIP or `fixup!` commits, and no em-dash.

```text
Fix the width of Hangul names in the listing

The width table missed the Hangul Jamo Extended-B block,
so names with those letters pushed the next column to the right.
```

## Code style

[CLAUDE.md](./CLAUDE.md) holds the full house rules,
for people and coding agents alike. In short:

- English for code, comments and messages; no em-dash anywhere.
- Single quotes unless a string expands something.
- `function name() { ... }` declarations, each with a documentation header.
- `local -r`, `local -i` and friends wherever they fit.
- Errors go through `__cdl_error` with a named `CDL_ERR_*` code.
- The return codes of cdl go by tens: the tens digit names what failed,
  and the units digit why. Every tool of the repository owns
  a block of ten exit codes that no other tool uses.
  CLAUDE.md has both, under "Exit codes".
- Long files fold into `# region` and `# endregion` blocks.
- Comments explain why, and break lines between phrases, never inside one.

`make format` applies `.editorconfig` through shfmt,
`make lint` applies `.shellcheckrc` through ShellCheck,
and `make lint-md` applies `.markdownlint-cli2.jsonc` through markdownlint.
The style tests check the rest.

## Pull requests

1. Fork the repository and branch from `main`.
2. Add a test for every fixed bug and every new behavior.
3. Update the README and the `Unreleased` section of `CHANGELOG.md`.
4. Run `make check`, and commit with the hooks installed.
5. Open the pull request; the template lists what reviewers look for.

By contributing, you agree that your work is licensed
under the [MIT License](./LICENSE).
