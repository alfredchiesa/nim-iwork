# iwork

[![CI](https://github.com/alfredchiesa/nim-iwork/actions/workflows/ci.yml/badge.svg)](https://github.com/alfredchiesa/nim-iwork/actions/workflows/ci.yml)
[![Docs](https://github.com/alfredchiesa/nim-iwork/actions/workflows/docs.yml/badge.svg)](https://alfredchiesa.github.io/nim-iwork/)

A pure [nim](https://nim-lang.org/) reader for Apple Keynote, Pages, and Numbers documents

## What works so far

Open any iWork 2013+ document with `openDocument(path)` - the kind is
auto-detected (by extension, or by sniffing the content when there is
none) and every on-disk layout works: plain zip, zip with a nested
`Index.zip`, or a directory bundle.

From there:

- **All the text, in reading order** - `doc.getText()` returns everything
  the document says, from any of the three formats: page headers and
  footers, body paragraphs, slide titles and text boxes, presenter
  notes, and table rows. `doc.textBlocks` gives the same thing as
  labeled pieces (`tbHeader`, `tbBody`, `tbNotes`, ...) tagged with the
  slide or sheet they came from
- **Knowing when text is incomplete** - `doc.getTextReport()` returns the
  same text plus `warnings` (known gaps, like a reference the walk
  couldn't follow) and `usedFallback` (the text came from `plainText`
  because the structured walk failed or came up empty). A blank document
  comes back with no warnings. Pass `strict = true` to raise
  `IworkFormatError` on any known gap instead. It only flags gaps it
  knows to look for, not every unsupported construct
- **Raw storage text** - `doc.plainText()` dumps every text storage in
  object order instead, master slides and all, with attachment
  placeholders stripped and line breaks normalized
- **Keynote** - `doc.slides` gives you each slide's title, body text
  boxes, presenter notes, and skip flag, in deck order
- **Numbers** - `doc.sheets` / `doc.tables` decode the binary cell storage
  into typed values (text, number, bool, date, duration, formula, error),
  with `toCsv` for quick export
- **Pages** - `doc.bodyText` returns the document body as paragraphs

And when the high-level api isn't enough, the layers it's built on are
all exported too:

- container access: list `.iwa` entries, read raw bytes, grab the
  metadata plist
- `decodeIwa` for the snappy chunk format, `decodeMessage` for a generic
  protobuf wire decoder (no proto files, no codegen)
- the full object graph: `buildIndex` maps every object by id, and
  `deref` / `derefAll` follow references between them

Pre-2013 documents are detected and rejected with a clear
`IworkUnsupportedError`. Corrupt or unreadable archives, and zips or
folders with no `.iwa` archives inside, raise `IworkContainerError`
naming the path, with the underlying error kept as `parent`. Not done yet: formula ast decoding (formula
cells surface their cached display value) and rich text cells.

## Notable Updates

- **Unreleased (on main)** - the `iworkextract` CLI, `getTextReport()`
  with extraction warnings and strict mode, wide-offset numbers tables,
  and clearer container errors. These ship in the next release
- **v1.2.0** (2026-08-29) - `getText()` returns all document text in
  reading order
- **v1.1.7** (2026-07-24) - first release: keynote slides, numbers tables
  with typed cells, pages body text, plain text extraction for all three
  formats, and the `iworkdump` debug CLI

See [CHANGELOG.md](CHANGELOG.md) for the full list.

## Install

iwork isn't in the nimble package registry yet, so install it straight
from the repo. This gets the latest tagged release:

```sh
nimble install https://github.com/alfredchiesa/nim-iwork
```

Then in your project's `.nimble` file (1.2.0 is the first release with
`getText()`):

```nim
requires "https://github.com/alfredchiesa/nim-iwork >= 1.2.0"
```

`getTextReport()` and the `iworkextract` CLI are on main but not in a
tagged release yet. Until then, install from head:

```sh
nimble install "https://github.com/alfredchiesa/nim-iwork@#head"
```

```nim
requires "https://github.com/alfredchiesa/nim-iwork#head"
```

Once the package is registered (see [Publishing](#publishing)),
`nimble install iwork` and `requires "iwork >= 1.2.0"` will work too.

## Quick start

The snippets below run as-is from a repo checkout - they use the real
documents in `tests/fixtures/`. Swap in your own paths if you wish.

```nim
import iwork

let doc = openDocument("tests/fixtures/simple.key")
echo doc.kind                       # dkKeynote (auto-detected)
echo doc.getText()                  # all text, in reading order

for blk in doc.textBlocks:          # the same text, labeled
  echo blk.section, " ", blk.kind, ": ", blk.text

for slide in doc.slides:            # keynote only
  echo slide.index, ": ", slide.title
  for line in slide.body:
    echo "  ", line
  if slide.presenterNotes.len > 0:
    echo "  notes: ", slide.presenterNotes

let book = openDocument("tests/fixtures/rich.numbers")
for sheet in book.sheets:           # numbers only
  for table in sheet.tables:
    echo sheet.name, " / ", table.name
    echo toCsv(table)

let report = openDocument("tests/fixtures/simple.pages")
for paragraph in report.bodyText:   # pages only
  echo paragraph
```

## Command line: iworkextract

Installing the package also installs `iworkextract` into nimble's bin
directory (usually `~/.nimble/bin`), so you can pull text, json, or csv
out of documents without writing any nim:

```sh
# all text, in reading order
iworkextract tests/fixtures/simple.pages

# several documents: each one starts with a "==> path <==" header
iworkextract tests/fixtures/simple.pages tests/fixtures/simple.key

# a json array with one object per document: kind, text, labeled blocks,
# warnings, usedFallback, and for numbers every sheet's tables as rows
iworkextract --json tests/fixtures/simple.key tests/fixtures/rich.numbers

# one numbers table as csv on stdout, picked by name or 1-based number
iworkextract --csv --sheet Assets --table "Liquid Assets" tests/fixtures/rich.numbers
iworkextract --csv --sheet 2 --table 2 tests/fixtures/rich.numbers

# every table to its own file, DIR/<document>_<sheet>_<table>.csv; the
# paths written are printed, clashing names get -2, -3, ... and existing
# files are left alone unless you pass --force
iworkextract --csv -o out/ tests/fixtures/rich.numbers tests/fixtures/simple.numbers
```

Results go to stdout, warnings and errors to stderr. Known extraction
gaps are reported as warnings, and `--strict` turns them into failures.
A failed document doesn't stop the batch. The exit status is 0 when every
document succeeded, 1 when any failed, and 2 for usage errors. Without
`--output`, `--csv` needs exactly one document and one matching table.
`iworkextract --help` has the details.

From a checkout it builds with `nimble build` (or
`nim c src/iworkextract.nim`). The bundled `examples/extract_text.nim`
is a tiny version of the same thing, as a starting point for your own
code:

```sh
nim c examples/extract_text.nim
examples/extract_text tests/fixtures/simple.pages
```

### Examples

`tools/iworkdump.nim` is a small debug CLI built on the library:

```sh
nim c tools/iworkdump.nim

# list iwa entries with compressed/decompressed sizes
tools/iworkdump ls tests/fixtures/simple.key

# write an entry's decompressed stream to stdout
tools/iworkdump cat tests/fixtures/simple.key Index/Document.iwa > document.bin

# list every object's id, registry type, and top-level field numbers
tools/iworkdump objects tests/fixtures/rich.numbers

# pretty-print one object's field tree as json
tools/iworkdump obj tests/fixtures/simple.key 1
```

## Supported File Types

Everything from the iWork 2013+ format family, in any of its three
on-disk layouts (plain zip, zip with a nested `Index.zip`, or a directory
bundle):

| Format | Extensions | Supported | Notes |
| --- | --- | --- | --- |
| Keynote | `.key` | yes | slides with titles, body text boxes, presenter notes, skip flag |
| Pages | `.pages` | yes | body paragraphs and plain text |
| Numbers | `.numbers` | yes | sheets, tables, typed cell values, csv export |
| iWork '09 and earlier | `.key`, `.pages`, `.numbers` | no | pre-2013 XML format (`index.xml` / `index.apxl`) - detected and rejected with `IworkUnsupportedError` |
| Password-protected documents | any | no | encrypted containers can't be read |
| Writing / creating documents | any | no | this is a reader, and writing isn't planned |

Within supported documents, a few cell/content flavors are partial:

| Content | Status |
| --- | --- |
| text, numbers, currency, booleans, dates, durations | fully decoded |
| formula cells | cached display value; the formula itself shows as `=?` when no cached value exists |
| rich text cells | decode as empty text for now |
| images, movies, charts | skipped (text extraction only) |

## How the format works

The short version of what this library actually parses:

1. an iwork document is a zip (or a directory bundle) holding
   `Index/*.iwa` files plus metadata and media
2. each `.iwa` is a sequence of chunks: a tiny 4-byte header, then a raw
   snappy block (no framing, no crc)
3. the decompressed stream is protobuf: repeated `[varint length,
   archive info, object payload]` records, each carrying an object id
   and a per-application type number
4. objects reference each other by id, forming one big graph - document
   to show to slides in keynote, document to sheets to tables in numbers
5. numbers cells are one more layer down: a custom binary record format
   packed inside the tile protobufs, with a flags word saying which
   fields are present

The type and field numbers aren't published by Apple - they come from
the community reverse-engineering credited below, re-verified against
real documents as this library was built.

## Testing

The whole suite runs with one command:

```sh
nimble test
```

Tests live in `tests/t*.nim` and run against real documents in
`tests/fixtures/`, with expected outputs pinned in `tests/golden/`. To run
a single test file:

```sh
nim c -r tests/tnumbers.nim
```

```sh
# regenerate docs locally and browse them
nimble docs && open htmldocs/index.html

# compile everything that should compile
for f in examples/*.nim tools/*.nim; do nim c --hints:off "$f"; done
```

## Publishing

Releases are automated: conventional commits on main feed
[release-please](https://github.com/googleapis/release-please), which
keeps a rolling release PR. Merging that PR bumps the version, updates
`CHANGELOG.md`, tags `vX.Y.Z`, and publishes a github release. Nimble
installs by git tag, so once the package is registered every merged
release PR is automatically live.

The registration itself is a one-time step, and hasn't happened yet:
as of 2026-10-26 there's no `iwork` entry in nim-lang/packages, which is
why [Install](#install) uses the repo url.

1. create a github personal access token with `repo` scope and export it
   as `GITHUB_TOKEN` (or let the prompt ask for it)
2. run `nimble publish` from the repo root - it forks
   [nim-lang/packages](https://github.com/nim-lang/packages), adds the
   iwork entry to `packages.json`, and opens the PR for you. prefer doing
   it by hand? fork nim-lang/packages and add:

   ```json
   {
     "name": "iwork",
     "url": "https://github.com/alfredchiesa/nim-iwork",
     "method": "git",
     "tags": ["iwork", "keynote", "pages", "numbers", "apple", "parser"],
     "description": "Pure Nim reader for Apple Keynote, Pages, and Numbers documents",
     "license": "MIT",
     "web": "https://github.com/alfredchiesa/nim-iwork",
     "doc": "https://alfredchiesa.github.io/nim-iwork/"
   }
   ```

3. once that PR merges, `nimble install iwork` resolves to the latest git
   tag and the package shows up on
   [nimble.directory](https://nimble.directory/) with a link to the docs

See [CONTRIBUTING.md](CONTRIBUTING.md) for the commit-to-version-bump
rules.

## Credits

The iwork format is undocumented; this library stands on the
reverse-engineering work of:

- [keynote-parser](https://github.com/psobot/keynote-parser) - the
  reference for keynote type and field numbers
- [numbers-parser](https://github.com/masaccio/numbers-parser) - the
  reference for the numbers cell storage format, and the source of the
  large-table test fixtures (MIT, see
  `tests/fixtures/NOTICE-numbers-parser.txt`)
- [iWorkFileFormat](https://github.com/obriensp/iWorkFileFormat) - the
  original deep dive into the container, snappy, and protobuf layers

## Contributing

Contributions, issues, and feature requests are all welcome! Found a bug or
have an idea? [Open an issue](https://github.com/alfredchiesa/nim-iwork/issues).
PRs are appreciated too - for bigger changes, it's worth opening an issue first
so we can talk it through. Commit messages follow
[Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`,
`docs:`, ...), since releases are cut automatically from them. See
[CONTRIBUTING.md](CONTRIBUTING.md) for the details.
