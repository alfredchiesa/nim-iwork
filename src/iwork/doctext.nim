## reading-order text extraction: every piece of text a document holds -
## headers, body, footers, text boxes, presenter notes, table cells
## (numbers, keynote, and pages tables alike) - as one ordered sequence
## of labeled blocks. `getText` in the top-level
## module joins them into a single string for search and indexing.

runnableExamples "-r:off":
  import iwork
  let doc = openDocument("report.pages")
  for blk in doc.textBlocks:
    echo blk.kind, " ", blk.section, ": ", blk.text

import std/strutils
import ./cellstorage, ./container, ./errors, ./keynote, ./numbers, ./objects,
  ./pages

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
    ## one piece of document text with its origin. the source fields are
    ## filled in where the walk actually knows them and left zero/empty
    ## otherwise; there are no page numbers, layout isn't decoded
    kind*: TextBlockKind
    section*: string ## "slide 3", the sheet name, or "" when there's none
    text*: string    ## the text itself, trimmed
    slide*: int      ## 1-based keynote slide index, 0 elsewhere
    table*: string   ## table name for table titles and rows, "" otherwise
    row*: int        ## 1-based row within `table` for table rows, else 0
    objectId*: uint64 ## text storage or table model the text came from,
                      ## 0 when not tracked

  ExtractOptions* = object
    ## parts of a document to leave out of text extraction. the zero
    ## value leaves nothing out, which is what you get by default
    excludeNotes*: bool         ## keynote presenter notes
    excludeSkippedSlides*: bool ## keynote slides skipped in the show
    excludeHeaders*: bool       ## pages headers
    excludeFooters*: bool       ## pages footers

proc `==`*(a, b: TextBlock): bool =
  ## compares kind, section, and text only, so blocks written out by hand
  ## still match; the source fields are extra detail, not identity
  a.kind == b.kind and a.section == b.section and a.text == b.text

proc add(blocks: var seq[TextBlock], blk: TextBlock) =
  # empty and whitespace-only pieces carry nothing worth indexing
  let trimmed = blk.text.strip
  if trimmed.len > 0:
    var blk = blk
    blk.text = trimmed
    system.add(blocks, blk)

proc add(blocks: var seq[TextBlock], kind: TextBlockKind,
    section, text: string, slide = 0, objectId = 0'u64) =
  blocks.add(TextBlock(kind: kind, section: section, text: text,
    slide: slide, objectId: objectId))

proc addRows(blocks: var seq[TextBlock], table: numbers.Table,
    section: string, slide = 0) =
  var n = 0
  for row in table.rows:
    inc n
    var cells: seq[string]
    for value in row:
      cells.add(value.asString)
    blocks.add(TextBlock(kind: tbTableRow, section: section,
      text: cells.join("\t"), slide: slide, table: table.name, row: n,
      objectId: table.id))

proc keynoteBlocks(idx: ObjectIndex, warnings: var seq[ExtractionWarning],
    opts: ExtractOptions): seq[TextBlock] =
  # tables come after the slide's text boxes: drawable order says nothing
  # reliable about where things sit on the slide, so this is best effort
  for slide in idx.keynoteSlides(warnings):
    if opts.excludeSkippedSlides and slide.isSkipped:
      continue
    let section = "slide " & $slide.index
    result.add(tbTitle, section, slide.title, slide.index, slide.titleId)
    for i, body in slide.body:
      result.add(tbBody, section, body, slide.index, slide.bodyIds[i])
    for table in slide.tables:
      result.addRows(table, section, slide.index)
    if not opts.excludeNotes:
      result.add(tbNotes, section, slide.presenterNotes, slide.index,
        slide.notesId)

proc pagesBlocks(idx: ObjectIndex, warnings: var seq[ExtractionWarning],
    opts: ExtractOptions): seq[TextBlock] =
  # headers sit above the body and footers below it on every page, so
  # that's the order they're reported in; floating text boxes and tables
  # have no place in the body flow and come last
  for piece in idx.pagesPieces(warnings, headers = not opts.excludeHeaders,
      footers = not opts.excludeFooters):
    case piece.kind
    of ppHeader: result.add(tbHeader, "", piece.text, 0, piece.objectId)
    of ppBody: result.add(tbBody, "", piece.text, 0, piece.objectId)
    of ppFooter: result.add(tbFooter, "", piece.text, 0, piece.objectId)
    of ppTextBox: result.add(tbTextBox, "", piece.text, 0, piece.objectId)
    of ppTable: result.addRows(piece.table, "")

proc numbersBlocks(idx: ObjectIndex,
    warnings: var seq[ExtractionWarning]): seq[TextBlock] =
  for sheet in idx.numbersSheets(warnings):
    result.add(tbTitle, sheet.name, sheet.name)
    for box in sheet.textBoxes:
      result.add(tbTextBox, sheet.name, box)
    for table in sheet.tables:
      result.add(TextBlock(kind: tbTitle, section: sheet.name,
        text: table.name, table: table.name, objectId: table.id))
      result.addRows(table, sheet.name)

proc textBlocks*(idx: ObjectIndex, kind: DocKind,
    warnings: var seq[ExtractionWarning],
    opts = ExtractOptions()): seq[TextBlock] =
  ## like `textBlocks`, also collecting the known gaps in `warnings`
  case kind
  of dkKeynote: keynoteBlocks(idx, warnings, opts)
  of dkPages: pagesBlocks(idx, warnings, opts)
  of dkNumbers: numbersBlocks(idx, warnings)

proc textBlocks*(idx: ObjectIndex, kind: DocKind,
    opts = ExtractOptions()): seq[TextBlock] =
  ## every block of text in the document, in reading order, minus what
  ## `opts` leaves out
  var warnings: seq[ExtractionWarning]
  idx.textBlocks(kind, warnings, opts)
