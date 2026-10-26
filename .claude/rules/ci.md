---
paths:
  - ".github/**"
  - "tools/ci/**"
---

# Continuous integration

## Map

- `tools/ci/install-tools.sh`: installs the CI tools, pinned
  (see "Rules").
- `tools/ci/common.sh`: what the CI scripts share:
  `ci_error` (a GitHub annotation and a code) and `sha256_of`.
- `tools/ci/report-environment.sh`: writes the tool versions of a job
  into its summary.
- `tools/ci/release.sh`: the release steps, one command each:
  `check`, `notes`, `assets`, `publish`, `verify`.
- `.github/workflows`: `ci-main.yml` calls the reusable
  `ci-lint`, `ci-workflow-lint`, `ci-test` and `ci-release`.
- `.github/dependabot.yml`: weekly grouped updates of the actions
  and the hook repositories, after a seven-day cooldown.
- `.github/zizmor.yml`: the one zizmor finding this repository accepts.
- `.github/actionlint.yaml`: the runner label actionlint does not know yet.

## Rules

- The YAML is thin. A step is one line that calls a script in `tools/ci`
  or a `make` target; the logic lives in the script, with the same shape
  as every other shell file here: a documentation header, functions,
  named exit codes from its own block (see `tools.md`), one job per function.
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
- A job keeps its tools and packages in a cache (`actions/cache`),
  keyed by the runner image, the package list
  and the hash of `tools/ci/install-tools.sh`.
  A cached download is used only while it matches its pinned digest;
  a package the image has already is not installed;
  the .deb files of the others install from the cache with `dpkg`,
  without `apt-get update`, which on a miss gets two minutes
  and three attempts, since it stalls at times on Ubuntu 22.04.
  The release job uses no cache.
- The test matrix covers what cdl promises: Ubuntu 26.04 (uutils ls),
  24.04 (GNU ls), 22.04 (the oldest bash and zsh), and macOS 26 twice,
  with the BSD ls and `/bin/bash` 3.2, then with Homebrew's gls.
  Lint runs on Ubuntu 26.04 because its Python ships the Unicode version
  the width table was generated from, so `--check` really compares there.
- Every job names its image, never `ubuntu-latest`,
  so the image of a job changes only with a commit.
- actionlint and zizmor check the workflows on every run; keep both silent.
- The lint job installs rumdl through `rvben/rumdl`, pinned by its commit,
  at the version that CONTRIBUTING.md gives a laptop,
  and runs `make lint-md` as a laptop does, so the two judge alike;
  the action checks the binary against the digest of the release.
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
