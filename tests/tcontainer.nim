# tests for the container layer: zip, nested index.zip, and bundle layouts
import std/[os, sequtils, strutils, tables, unittest]
import zippy/ziparchives
import iwork

const fixtures = currentSourcePath().parentDir / "fixtures"

suite "container: single-file zip with Index/*.iwa":
  test "keynote doc opens with correct kind":
    let c = openContainer(fixtures / "simple.key")
    check c.kind == ckZip
    check c.docKind == dkKeynote

  test "keynote doc has iwa entries":
    let c = openContainer(fixtures / "simple.key")
    check c.iwaEntries.len > 0

  test "keynote Index/Document.iwa is readable and non-empty":
    let c = openContainer(fixtures / "simple.key")
    check c.readEntry("Index/Document.iwa").len > 0

  test "numbers doc opens with correct kind":
    let c = openContainer(fixtures / "simple.numbers")
    check c.kind == ckZip
    check c.docKind == dkNumbers
    check c.iwaEntries.len > 0
    check c.readEntry("Index/Document.iwa").len > 0

suite "container: pages zip":
  test "pages doc opens with correct kind":
    let c = openContainer(fixtures / "simple.pages")
    check c.kind == ckZip
    check c.docKind == dkPages

  test "pages iwa entries readable":
    let c = openContainer(fixtures / "simple.pages")
    check c.iwaEntries.len > 0
    check c.readEntry("Index/Document.iwa").len > 0

suite "container: metadata":
  test "metadata plist raw bytes are returned when present":
    for name in ["simple.key", "simple.pages", "simple.numbers"]:
      let c = openContainer(fixtures / name)
      check c.metadataPlist.len > 0

suite "container: dockind sniffing without extension":
  test "extensionless keynote doc is sniffed from iwa names":
    let tmp = getTempDir() / "iwork_sniff_key"
    copyFile(fixtures / "simple.key", tmp)
    defer: removeFile(tmp)
    check openContainer(tmp).docKind == dkKeynote

  test "extensionless numbers doc is sniffed from iwa names":
    let tmp = getTempDir() / "iwork_sniff_numbers"
    copyFile(fixtures / "simple.numbers", tmp)
    defer: removeFile(tmp)
    check openContainer(tmp).docKind == dkNumbers

proc zipEntries(path: string): OrderedTable[string, string] =
  let reader = openZipArchive(path)
  defer: reader.close()
  for entry in reader.walkFiles:
    result[entry] = reader.extractFile(entry)

suite "container: every supported layout opens":
  let want = openDocument(fixtures / "simple.pages").getText()
  let entries = zipEntries(fixtures / "simple.pages")

  test "zip with a nested Index.zip":
    var inner, outer: OrderedTable[string, string]
    for path, data in entries:
      if path.startsWith("Index/"): inner[path] = data
      else: outer[path] = data
    outer["Index.zip"] = createZipArchive(inner)
    let tmp = getTempDir() / "iwork_nested.pages"
    writeFile(tmp, createZipArchive(outer))
    defer: removeFile(tmp)
    let doc = openDocument(tmp)
    check doc.container.kind == ckZip
    check "Index/Document.iwa" in doc.container.iwaEntries
    check doc.getText() == want

  test "directory bundle, with and without a nested Index.zip":
    for nested in [false, true]:
      let dir = getTempDir() / "iwork_bundle.pages"
      removeDir(dir)
      defer: removeDir(dir)
      var inner: OrderedTable[string, string]
      for path, data in entries:
        if nested and path.startsWith("Index/"):
          inner[path] = data
          continue
        createDir(parentDir(dir / path))
        writeFile(dir / path, data)
      if nested:
        writeFile(dir / "Index.zip", createZipArchive(inner))
      let doc = openDocument(dir)
      check doc.container.kind == ckBundle
      check doc.getText() == want

suite "container: bad input raises IworkContainerError":
  proc raisesContainerError(path: string): bool =
    # our error, naming the document; anything else escapes and fails
    try:
      discard openContainer(path)
    except IworkContainerError as e:
      result = path in e.msg

  test "garbage, empty, and truncated zips":
    let tmp = getTempDir() / "iwork_bad.pages"
    defer: removeFile(tmp)
    writeFile(tmp, "not a zip at all")
    check raisesContainerError(tmp)
    writeFile(tmp, "")
    check raisesContainerError(tmp)
    writeFile(tmp, readFile(fixtures / "simple.pages")[0 ..< 20000])
    check raisesContainerError(tmp)

  test "the zippy error is kept as the parent":
    let tmp = getTempDir() / "iwork_bad_parent.pages"
    writeFile(tmp, "not a zip at all")
    defer: removeFile(tmp)
    try:
      discard openContainer(tmp)
      fail()
    except IworkContainerError as e:
      check e.parent != nil

  test "a corrupt nested Index.zip":
    var outer = zipEntries(fixtures / "simple.pages")
    for path in toSeq(outer.keys):
      if path.startsWith("Index/"): outer.del(path)
    outer["Index.zip"] = "not a zip either"
    let tmp = getTempDir() / "iwork_bad_nested.pages"
    writeFile(tmp, createZipArchive(outer))
    defer: removeFile(tmp)
    check raisesContainerError(tmp)

  test "a valid zip with no iwa archives":
    let tmp = getTempDir() / "iwork_no_iwa.pages"
    writeFile(tmp, createZipArchive({"readme.txt": "hi"}.toOrderedTable))
    defer: removeFile(tmp)
    check raisesContainerError(tmp)

  test "an arbitrary directory named like a document":
    let dir = getTempDir() / "iwork_not_a_bundle.pages"
    createDir(dir)
    writeFile(dir / "readme.txt", "hi")
    defer: removeDir(dir)
    check raisesContainerError(dir)

  test "pre-2013 documents still raise IworkUnsupportedError":
    let tmp = getTempDir() / "iwork_legacy.pages"
    writeFile(tmp, createZipArchive({"index.xml": "<x/>"}.toOrderedTable))
    defer: removeFile(tmp)
    expect IworkUnsupportedError:
      discard openContainer(tmp)
