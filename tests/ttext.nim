# tests for plain text extraction via the public document api
import std/[os, strutils, unittest]
import iwork
import ./iwabuild

const fixtures = currentSourcePath().parentDir / "fixtures"

suite "text: pages":
  test "plainText contains the document's paragraphs":
    let text = openDocument(fixtures / "simple.pages").plainText()
    check "hello pages" in text
    check "second paragraph with some words" in text

suite "text: keynote":
  test "plainText contains slide content":
    let text = openDocument(fixtures / "simple.key").plainText()
    check "hello keynote" in text
    check "second slide" in text

  test "attachment placeholders are stripped":
    # simple.key has storages that are just u+fffc; none may leak through
    let text = openDocument(fixtures / "simple.key").plainText()
    check "￼" notin text

suite "text: golden output":
  # golden files were generated from actual output and human-reviewed:
  # pages is the two known paragraphs, keynote is the user content plus
  # the master-slide template texts, with all placeholder chars gone
  const golden = currentSourcePath().parentDir / "golden"

  test "simple.pages matches golden":
    check openDocument(fixtures / "simple.pages").plainText() ==
      readFile(golden / "simple.pages.txt")

  test "simple.key matches golden":
    check openDocument(fixtures / "simple.key").plainText() ==
      readFile(golden / "simple.key.txt")

suite "text: document api":
  test "openDocument detects kind":
    check openDocument(fixtures / "simple.key").kind == dkKeynote
    check openDocument(fixtures / "simple.pages").kind == dkPages
    check openDocument(fixtures / "simple.numbers").kind == dkNumbers

  test "extraction is deterministic":
    let a = openDocument(fixtures / "simple.key").plainText()
    let b = openDocument(fixtures / "simple.key").plainText()
    check a == b

suite "text: reading order":
  test "keynote getText follows deck order and skips master text":
    check openDocument(fixtures / "simple.key").getText() ==
      "hello keynote\nfirst bullet\nsecond slide\nnote text here"

  test "keynote blocks are labeled by slide":
    let blocks = openDocument(fixtures / "simple.key").textBlocks
    check blocks[0] == TextBlock(kind: tbTitle, section: "slide 1",
      text: "hello keynote")
    check blocks[^1] == TextBlock(kind: tbNotes, section: "slide 2",
      text: "note text here")

  test "pages getText keeps paragraphs in order":
    let text = openDocument(fixtures / "simple.pages").getText()
    check text.find("hello pages") < text.find("second paragraph")

  test "numbers getText reaches text plainText can't":
    # numbers keeps cell text in the binary cell storage, not in text
    # storages, so the storage-level extraction sees none of it
    let book = openDocument(fixtures / "rich.numbers")
    check book.plainText().find("Mortgage") < 0
    let text = book.getText()
    check "Mortgage" in text            # a table cell
    check "Total Net Worth" in text     # a table name
    check "Liabilities" in text         # a sheet name
    check "HOW TO USE" in text          # a text box on the sheet

  test "numbers rows come out as tab-joined blocks":
    let blocks = openDocument(fixtures / "simple.numbers").textBlocks
    check TextBlock(kind: tbTableRow, section: "Sheet 1",
      text: "a\tb\tC") in blocks

  test "getText works on every kind and is deterministic":
    for name in ["simple.key", "simple.pages", "simple.numbers",
        "rich.key", "rich.numbers"]:
      let doc = openDocument(fixtures / name)
      check doc.getText().len > 0
      check doc.getText() == openDocument(fixtures / name).getText()

proc synthetic(name, stream: string): IworkDocument =
  let dir = getTempDir() / "iwork_synth_" & name
  removeDir(dir)
  writeBundle(dir, stream)
  # entries load eagerly, so the bundle can go right away
  result = openDocument(dir)
  removeDir(dir)

proc storage(id: uint64, text: string): string =
  iwaObject(id, tswpStorageArchive, pbBytes(3, text))

suite "text: getTextReport":
  test "real fixtures report clean, matching getText, even when strict":
    for name in ["simple.key", "simple.pages", "simple.numbers",
        "rich.key", "rich.numbers"]:
      let doc = openDocument(fixtures / name)
      let report = doc.getTextReport(strict = true)
      check report.warnings.len == 0
      check not report.usedFallback
      check report.text == doc.getText()

  test "a missing body reference falls back instead of going blank":
    for body in ["", pbRef(4, 99)]: # absent, then dangling
      let doc = synthetic("nobody.pages",
        iwaObject(1, tpDocumentArchive, body) &
        storage(2, "Recoverable document text"))
      check doc.plainText() == "Recoverable document text"
      check doc.getText() == "Recoverable document text"
      let report = doc.getTextReport()
      check report.text == "Recoverable document text"
      check report.usedFallback
      check report.warnings.len == 1
      check report.warnings[0].kind == ewMissingReference
      expect IworkFormatError:
        discard doc.getTextReport(strict = true)

  test "an intentionally blank document is blank, not a failure":
    let doc = synthetic("blank.pages",
      iwaObject(1, tpDocumentArchive, pbRef(4, 2)) & storage(2, ""))
    check doc.getText() == ""
    let report = doc.getTextReport(strict = true)
    check report.text == ""
    check report.warnings.len == 0
    check not report.usedFallback

  test "a structure error falls back like getText always has":
    let doc = synthetic("noroot.pages", storage(2, "orphan text"))
    check doc.getText() == "orphan text"
    let report = doc.getTextReport()
    check report.usedFallback
    check report.warnings.len == 1
    check report.warnings[0].kind == ewStructureError
    expect IworkFormatError:
      discard doc.getTextReport(strict = true)

  test "partial keynote text is kept, without master or orphan storages":
    # slide tree points at one real node and one dangling one; storage 7
    # stands in for master-slide text nothing on a slide references
    let doc = synthetic("partial.key",
      iwaObject(1, knDocumentArchive, pbRef(2, 2)) &
      iwaObject(2, knShowArchive, pbBytes(3, pbRef(2, 3) & pbRef(2, 99))) &
      iwaObject(3, knSlideNodeArchive, pbRef(2, 4)) &
      iwaObject(4, knSlideArchive, pbRef(7, 5)) &
      iwaObject(5, tswpShapeInfoArchive, pbRef(2, 6)) &
      storage(6, "slide text") &
      storage(7, "Master Title"))
    check doc.slides.len == 1
    let report = doc.getTextReport()
    check report.text == "slide text"
    check not report.usedFallback
    check report.warnings.len == 1
    check report.warnings[0].kind == ewMissingReference
    check doc.getText() == "slide text"
    expect IworkFormatError:
      discard doc.getTextReport(strict = true)
