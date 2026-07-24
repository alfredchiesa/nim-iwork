# tests for structured keynote slide reading, against real fixtures
import std/[os, sequtils, strutils, unittest]
import iwork

const fixtures = currentSourcePath().parentDir / "fixtures"

# text that only lives on the theme's master slides. plainText includes
# these because it walks every storage; slides() deliberately does not,
# so the no-text-lost checks compare modulo this fixed set
const masterLines = [
  "Presentation Title", "Slide Title", "Section Title", "Agenda Title",
  "Body Level One", "Body Level Two", "Body Level Three", "Body Level Four",
  "Body Level Five"]

proc allSlideText(slides: seq[Slide]): string =
  var pieces: seq[string]
  for slide in slides:
    if slide.title.len > 0:
      pieces.add(slide.title)
    pieces.add(slide.body)
    if slide.presenterNotes.len > 0:
      pieces.add(slide.presenterNotes)
  pieces.join("\n")

suite "keynote: simple.key":
  test "slide count is 2":
    check openDocument(fixtures / "simple.key").slides.len == 2

  test "slide 1 has title, body, and index":
    let slides = openDocument(fixtures / "simple.key").slides
    check slides[0].index == 1
    check slides[0].title == "hello keynote"
    check slides[0].body == @["first bullet"]
    check not slides[0].isSkipped

  test "slide 2 notes contain the presenter note":
    let slides = openDocument(fixtures / "simple.key").slides
    check slides[1].index == 2
    check slides[1].title == "second slide"
    check "note text here" in slides[1].presenterNotes

suite "keynote: rich.key":
  test "slide count is 4":
    check openDocument(fixtures / "rich.key").slides.len == 4

  test "slide 1 title and body text boxes":
    let slides = openDocument(fixtures / "rich.key").slides
    check slides[0].title == "Rich Presentation"
    check "Rich Subtitle" in slides[0].body
    check "Alfred July 2026" in slides[0].body

  test "quote and attribution text boxes are not lost":
    let slides = openDocument(fixtures / "rich.key").slides
    check slides[1].body.anyIt("Good enough" in it)
    check slides[3].body.anyIt("Sagan" in it)

suite "keynote: no text lost":
  test "slide text covers plainText except master templates":
    for name in ["simple.key", "rich.key"]:
      let doc = openDocument(fixtures / name)
      let slideText = allSlideText(doc.slides)
      for line in doc.plainText().splitLines:
        if line.strip.len == 0 or line in masterLines:
          continue
        check line in slideText

  test "slide text invents nothing":
    for name in ["simple.key", "rich.key"]:
      let doc = openDocument(fixtures / name)
      let plain = doc.plainText()
      for line in allSlideText(doc.slides).splitLines:
        if line.strip.len > 0:
          check line in plain

suite "keynote: wrong document kind":
  test "slides on a numbers doc raises IworkError":
    expect IworkError:
      discard openDocument(fixtures / "simple.numbers").slides
