# iwork

Pure [nim](https://nim-lang.org/) reader for Apple Keynote, Pages, and Numbers documents

## What works so far

- Opening iWork 2013+ document containers via `openContainer(path)`:
  - single-file zip documents with `Index/*.iwa` entries
  - zip documents holding a nested `Index.zip` with the iwa files
  - directory bundles with the same layout
- Document kind detection (`dkKeynote`, `dkPages`, `dkNumbers`) from the file
  extension, with content sniffing as a fallback for extensionless input
- Listing `.iwa` entries (`iwaEntries`) and reading raw entry bytes
  (`readEntry`), plus `metadataPlist` for `Metadata/Properties.plist`
- Legacy pre-2013 documents (`index.xml` / `index.apxl`) are detected and
  rejected with `IworkUnsupportedError`
- Decoding the `.iwa` snappy chunk format via `decodeIwa` (raw snappy blocks,
  no stream framing), with `IworkFormatError` on malformed input
- A generic protobuf wire-format decoder (`decodeMessage` plus typed getters)
  with no proto files or codegen - messages decode into a field-number tree
- The full object graph: `buildIndex` parses every `.iwa` into a
  `Table[uint64, IworkObject]`, and `deref` / `derefAll` resolve
  `TSP.Reference` chains between objects

Not yet implemented: typed archives on top of the generic tree, text
extraction, or any higher-level document model.

## Notable Updates

## Install

## Quick start

### Examples

`tools/iworkdump.nim` is a small debug CLI built on the library:

```sh
nim c tools/iworkdump.nim

# list iwa entries with compressed/decompressed sizes
tools/iworkdump ls deck.key

# write an entry's decompressed stream to stdout
tools/iworkdump cat deck.key Index/Document.iwa > document.bin

# list every object's id, registry type, and top-level field numbers
tools/iworkdump objects deck.key

# pretty-print one object's field tree as json
tools/iworkdump obj deck.key 1
```

## Supported File Types

## Testing

## Contributing

Contributions, issues, and feature requests are all welcome! Found a bug or
have an idea? [Open an issue](https://github.com/alfredchiesa/nim-iwork/issues).
PRs are appreciated too - for bigger changes, it's worth opening an issue first
so we can talk it through. Commit messages follow
[Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`,
`docs:`, ...), since releases are cut automatically from them.
