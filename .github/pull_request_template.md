## What and why

<!--
What changes, and why it is needed.
Link the issue it closes: "Closes #12".
-->

## How it was tested

<!--
The shells and systems you ran `make check` on,
for example bash 5.3 and zsh 5.9 on Ubuntu 26.04.
-->

## Checklist

- [ ] `make check` passes (lint, format check, every test in bash and zsh).
- [ ] Every fixed bug and every new behavior has a test named after its rule.
- [ ] The README, `cdl --help` and the `Unreleased` section of `CHANGELOG.md`
  describe the change.
- [ ] The code follows the house rules:
  functions with headers, named error codes,
  comments that break between phrases
  ([CLAUDE.md](https://github.com/BMTLab/cdl/blob/main/CLAUDE.md)).
- [ ] The listing path starts no new external command
  (`make bench` shows no regression).
