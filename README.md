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

Not yet implemented: protobuf decoding of the decompressed streams, or any
higher-level document model.

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
