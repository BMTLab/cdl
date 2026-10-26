---
paths:
  - "tests/**"
---

# Tests

- A test states one rule in its name, as a sentence without "should":
  `a second operand fails with CDL_ERR_USAGE instead of being ignored`.
  It checks the rule, never the shape of the code.
- Every test opens with its locals, as every function does,
  then has the sections `# Arrange`, `# Act` and `# Assert`,
  in that order; an empty section keeps its comment with the reason
  (`# Arrange: no fixtures needed.`).
- A unit test feeds the formatter canned `ls -l` lines from `fixtures.bash`.
  An integration test builds a real directory with `make_entries`
  under the sandbox `HOME`,
  and runs cdl through `in_shell` in the shell under test.
- `make test` runs the test files at the same time where GNU parallel is
  (`BATS_JOBS`), and with 16 CPUs or more the tests of each file too;
  CI, with its few CPUs, runs only the files at the same time.
  So a test keeps its files in its sandbox under `BATS_TEST_TMPDIR`
  and shares no path, port or order with another.
  A file whose tests must run one by one
  sets `BATS_NO_PARALLELIZE_WITHIN_FILE=true`, with a comment that says why.
- A rule that holds for several inputs is one parameterized test
  (`bats_test_function` over a list of samples), not copies;
  each sample carries the description that names the test.
- A style test collects every violation first,
  and fails once with the whole list.
- The width oracle `tests/support/bin/screen-cells` stays independent
  of the width table in `cdl.sh`; extend both when the samples gain a script.
- A fixed bug gets a test that fails on the old code;
  a new behavior gets its test before the README mentions it.
- The suite runs on macOS too, where act cannot take it:
  BSD `chmod` reads a `--` after the mode as a file name,
  BSD `script` echoes the `^D` that ends its input,
  the file system ignores case, `/bin/bash` is 3.2,
  and `sh` is that bash in POSIX mode.
  A test that reads the compact listing calls `require_gnu_compatible_ls`.
- `# bats test_tags=smoke` marks the quick tests of the main paths of cdl,
  which `make smoke` runs.
  Tag a test only when it is fast and covers a path no tagged test does,
  and prefer the files that already hold one:
  every file adds to the run, so `make smoke` stays within a few seconds.
