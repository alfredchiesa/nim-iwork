# tests for the container layer: zip, nested index.zip, and bundle layouts
import std/[os, unittest]
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

suite "container: zip with nested Index.zip":
  test "pages doc opens with correct kind":
    let c = openContainer(fixtures / "simple.pages")
    check c.kind == ckZip
    check c.docKind == dkPages

  test "iwa entries come from the nested index zip":
    let c = openContainer(fixtures / "simple.pages")
    check c.iwaEntries.len > 0
    check c.readEntry("Index/Document.iwa").len > 0

suite "container: directory bundle":
  test "bundle opens with correct kind":
    let c = openContainer(fixtures / "simple_bundle.pages")
    check c.kind == ckBundle
    check c.docKind == dkPages

  test "bundle iwa entries readable":
    let c = openContainer(fixtures / "simple_bundle.pages")
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

suite "container: legacy documents":
  test "pre-2013 doc raises IworkUnsupportedError":
    let legacy = fixtures / "legacy.pages"
    if not fileExists(legacy):
      skip()
    else:
      expect IworkUnsupportedError:
        discard openContainer(legacy)
