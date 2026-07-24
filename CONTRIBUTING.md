# Contributing

Thanks for helping out! The short version: open an issue to talk it
through, keep commits conventional, make sure `nimble test` passes.

## Commit messages

Every commit on main follows
[Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add duration cell decoding
fix: handle empty tiles in single-row tables
docs: clarify bundle support
test: cover wide-offset tiles
chore: bump zippy
refactor: split tile walking out of buildTable
```

This is not just style - releases are cut automatically from these
messages, so a mislabeled commit means a wrong version bump.

## Versioning

[release-please](https://github.com/googleapis/release-please) watches
main and keeps a rolling release PR. The bump it picks comes straight
from the commit types:

| Commit | Bump |
| --- | --- |
| `fix:` | patch |
| `feat:` | minor |
| `feat!:` or a `BREAKING CHANGE:` footer | major |

Pre-1.0, breaking changes only bump the minor version (0.3.0 -> 0.4.0);
release-please handles that automatically for 0.x versions. Merging the
release PR tags the release, publishes the github release notes, and
updates `CHANGELOG.md` - no manual version editing, ever. The version
line in `iwork.nimble` carries an `x-release-please-version` marker and
is rewritten by the release PR.

## Code style

- NEP-1: 2-space indent, camelCase procs, PascalCase types, `func` where
  pure
- `##` doc comments on every exported symbol; inline comments lowercase
  and casual
- `std/logging` only - the library is silent by default and never echoes
- no em dashes or arrow glyphs anywhere, use `-` and `->`

## Tests

`nimble test` must pass before anything merges. Tests live in
`tests/t*.nim` and run against real fixture documents in
`tests/fixtures/`, with expected outputs pinned in `tests/golden/`. New
features need tests; bug fixes need a test that fails without the fix.
