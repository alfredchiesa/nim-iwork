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
