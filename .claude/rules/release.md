---
paths:
  - "CHANGELOG.md"
  - "tools/ci/release.sh"
  - "tools/release-notes.sh"
  - "tests/style/test_release.bats"
---

# Versions, changelog, release

- The version lives in the `# Version:` line of the card of `cdl.sh`.
  `CHANGELOG.md` has a `## [X.Y.Z] - YYYY-MM-DD` section for it,
  dated on the day of the release (a style test checks),
  and the release tag `vX.Y.Z` sits on the commit that bumps it.
- The changelog follows Keep a Changelog: Fixed, Changed, Added.
  One entry per behavior a user can notice, written for that user,
  with the old behavior named.
- Every return code appears in the card of `cdl.sh`, in `cdl --help`
  and in the README (a style test checks).
