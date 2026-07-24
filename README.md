# iwork

A pure [nim](https://nim-lang.org/) reader for Apple Keynote, Pages, and Numbers documents

**API docs:** [alfredchiesa.github.io/nim-iwork](https://alfredchiesa.github.io/nim-iwork/)

## What works so far

Open any iWork 2013+ document with `openDocument(path)` - the kind is
auto-detected (by extension, or by sniffing the content when there is
none) and every on-disk layout works: plain zip, zip with a nested
`Index.zip`, or a directory bundle.

From there:

- **Plain text from anything** - `doc.plainText()` pulls all text from any
  of the three formats, with attachment placeholders stripped and line
  breaks normalized
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
`IworkUnsupportedError`. Not done yet: formula ast decoding (formula
cells surface their cached display value) and rich text cells.

## Notable Updates

- **v0.1.0** (2026-07-24) - first release: keynote slides, numbers tables
  with typed cells, pages body text, plain text extraction for all three
  formats, and the `iworkdump` debug CLI

## Install

```sh
nimble install iwork
```

Or straight from the repo:

```sh
nimble install https://github.com/alfredchiesa/nim-iwork
```

Then in your project's `.nimble` file:

```nim
requires "iwork >= 0.1.0"
```

## Quick start

The snippets below run as-is from a repo checkout - they use the real
documents in `tests/fixtures/`. Swap in your own paths if you wish.

```nim
import iwork

let doc = openDocument("tests/fixtures/simple.key")
echo doc.kind                       # dkKeynote (auto-detected)
echo doc.plainText()                # all text, joined with newlines

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

or from the CLI via the bundled example:

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

Within supported documents, a few cell/content flavors are partial:

| Content | Status |
| --- | --- |
| text, numbers, currency, booleans, dates, durations | fully decoded |
| formula cells | cached display value; the formula itself shows as `=?` when no cached value exists |
| rich text cells | decode as empty text for now |
| images, movies, charts | skipped (text extraction only) |

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

## Contributing

Contributions, issues, and feature requests are all welcome! Found a bug or
have an idea? [Open an issue](https://github.com/alfredchiesa/nim-iwork/issues).
PRs are appreciated too - for bigger changes, it's worth opening an issue first
so we can talk it through. Commit messages follow
[Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`,
`docs:`, ...), since releases are cut automatically from them.
