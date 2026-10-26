---
paths:
  - "tools/**"
  - "tests/support/bin/*"
  - "Makefile"
---

# Tools

Every script of the repository but `cdl.sh` is a tool:
the scripts of `tools/` and `tests/support/bin/`, and the Makefile.

## The guard

- Every standalone script (`tools/*.sh`, `tests/support/bin/*`)
  ends with the execution guard of the style,
  so a test can source it for its functions:
  strict mode, the traps and the call of `main` all sit inside it.
  Its ERR trap names an unplanned failure with the line and the command,
  and ends with the internal code of the tool, the last of its block;
  a code of the block passes on unchanged, as a helper has reported it.
- The bash 3.2 of macOS runs `install-tools.sh` before Homebrew brings
  a newer bash, so the guard turns on `inherit_errexit` only where it exists,
  and the scripts keep to bash 3.2: `printf -v ... '%q'`, never `${x@Q}`.

## Exit codes

A tool owns a block of ten exit codes, which no other tool uses,
so a code in a CI log names its script and its reason at once.
A tool names its codes after itself (`RELEASE_ERR_VERSION`),
gives the first of its block to a wrong command line when it has one,
the last of its block to a bug, which the ERR trap of its guard reports
(`RELEASE_ERR_INTERNAL`, 29),
and documents every code in its header.
A style test holds the rule: no code named twice, no file across two blocks,
no block shared.

| Codes | File                                | Names                      |
| ----: | ----------------------------------- | -------------------------- |
| 10-19 | `tools/ci/install-tools.sh`         | `INSTALL_ERR_*`            |
| 20-29 | `tools/ci/release.sh`               | `RELEASE_ERR_*`            |
| 30-39 | `tools/release-notes.sh`            | `NOTES_ERR_*`              |
| 40-49 | `tools/bench.sh`                    | `BENCH_ERR_*`              |
| 50-59 | `tools/gen-width-table.py`          | `EXIT_*`                   |
| 60-69 | `tests/support/bin/zsh-completions` | `ZSH_COMPLETIONS_ERR_*`    |
| 70-79 | `Makefile`                          | `MAKE_ERR_*`               |
| 80-89 | `tests/support/bin/screen-cells`    | `SCREEN_CELLS_ERR_*`       |
| 90-99 | `tools/ci/report-environment.sh`    | `REPORT_ENVIRONMENT_ERR_*` |

The codes of the Makefile belong to its recipes.
A new tool takes the next free block, 100-109, and a line in this table.
Codes stay below 126, where the shell's own codes begin.
make itself exits with 2 whenever a recipe fails;
the code of the recipe shows in its error line (`Error 71`).
