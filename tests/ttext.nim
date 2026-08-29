# tests for plain text extraction via the public document api
import std/[os, strutils, unittest]
import iwork

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
