# tests for structured pages reading
import std/[os, strutils, unittest]
import iwork

const fixtures = currentSourcePath().parentDir / "fixtures"

suite "pages: body text":
  test "bodyText yields the document paragraphs in order":
    let paragraphs = openDocument(fixtures / "simple.pages").bodyText
    check paragraphs.len == 2
    check paragraphs[0] == "hello pages"
    check "second paragraph with some words" in paragraphs[1]

  test "paragraphs contain no blank entries":
    for p in openDocument(fixtures / "simple.pages").bodyText:
      check p.strip.len > 0

suite "pages: wrong document kind":
  test "bodyText on a keynote doc raises IworkError":
    expect IworkError:
      discard openDocument(fixtures / "simple.key").bodyText
