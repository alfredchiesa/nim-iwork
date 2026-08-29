## reading-order text extraction: every piece of text a document holds -
## headers, body, footers, text boxes, presenter notes, table cells -
## as one ordered sequence of labeled blocks. `getText` in the top-level
## module joins them into a single string for search and indexing.

runnableExamples "-r:off":
  import iwork
  let doc = openDocument("report.pages")
  for blk in doc.textBlocks:
    echo blk.kind, " ", blk.section, ": ", blk.text

import std/strutils
import ./cellstorage, ./container, ./keynote, ./numbers, ./objects, ./pages

type
  TextBlockKind* = enum
    ## where a block of text sits in the document
    tbTitle    ## a slide title, sheet name, or table name
    tbBody     ## body text: pages paragraphs, keynote slide text
    tbHeader   ## page header
    tbFooter   ## page footer
    tbTextBox  ## a floating text box on a page or sheet
    tbNotes    ## keynote presenter notes
    tbTableRow ## one table row, cells joined with tabs

  TextBlock* = object
    ## one piece of document text with its origin
    kind*: TextBlockKind
    section*: string ## "slide 3", the sheet name, or "" when there's none
    text*: string    ## the text itself, trimmed

proc add(blocks: var seq[TextBlock], kind: TextBlockKind,
    section, text: string) =
  # empty and whitespace-only pieces carry nothing worth indexing
  let trimmed = text.strip
  if trimmed.len > 0:
    blocks.add(TextBlock(kind: kind, section: section, text: trimmed))

proc keynoteBlocks(idx: ObjectIndex): seq[TextBlock] =
  for slide in idx.keynoteSlides:
    let section = "slide " & $slide.index
    result.add(tbTitle, section, slide.title)
    for body in slide.body:
      result.add(tbBody, section, body)
    result.add(tbNotes, section, slide.presenterNotes)

proc pagesBlocks(idx: ObjectIndex): seq[TextBlock] =
  # headers sit above the body and footers below it on every page, so
  # that's the order they're reported in; floating text boxes have no
  # place in the body flow and come last
  let hf = idx.pagesHeadersFooters
  for header in hf.headers:
    result.add(tbHeader, "", header)
  for paragraph in idx.pagesBodyText:
    result.add(tbBody, "", paragraph)
  for footer in hf.footers:
    result.add(tbFooter, "", footer)
  for box in idx.pagesTextBoxes:
    result.add(tbTextBox, "", box)

proc numbersBlocks(idx: ObjectIndex): seq[TextBlock] =
  for sheet in idx.numbersSheets:
    result.add(tbTitle, sheet.name, sheet.name)
    for box in sheet.textBoxes:
      result.add(tbTextBox, sheet.name, box)
    for table in sheet.tables:
      result.add(tbTitle, sheet.name, table.name)
      for row in table.rows:
        var cells: seq[string]
        for value in row:
          cells.add(value.asString)
        result.add(tbTableRow, sheet.name, cells.join("\t"))

proc textBlocks*(idx: ObjectIndex, kind: DocKind): seq[TextBlock] =
  ## every block of text in the document, in reading order
  case kind
  of dkKeynote: keynoteBlocks(idx)
  of dkPages: pagesBlocks(idx)
  of dkNumbers: numbersBlocks(idx)
