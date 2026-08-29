## pure nim reader for apple keynote, pages, and numbers documents.
##
## everything a user needs is importable from plain `import iwork`:
## open a document with `openDocument`, then use `getText` on any kind,
## `slides` for keynote, `sheets`/`tables` for numbers, and `bodyText`
## for pages.

runnableExamples "-r:off":
  let doc = openDocument("deck.key") # auto-detects keynote/pages/numbers
  echo doc.kind                      # dkKeynote
  echo doc.getText()                 # all text, in reading order

  for slide in doc.slides:           # keynote only
    echo slide.title, " | ", slide.presenterNotes

  let book = openDocument("budget.numbers")
  for table in book.tables:          # numbers only
    for row in table.rows:
      for cell in row:
        echo cell.asString

import std/[options, strutils]
import iwork/[cellstorage, container, doctext, errors, keynote, numbers,
  objects, pages, snappychunks, text, typemaps, wire]

export cellstorage, container, doctext, errors, keynote, numbers, objects,
  pages, snappychunks, text, typemaps, wire

type
  IworkDocument* = ref object
    ## an opened iwork document with a lazily built object index
    container*: IworkContainer ## the underlying container, for low-level use
    indexCache: Option[ObjectIndex]

proc openDocument*(path: string): IworkDocument =
  ## opens a keynote, pages, or numbers document,
  ## auto-detecting the application from extension or content
  runnableExamples "-r:off":
    let doc = openDocument("report.pages")
    echo doc.kind # dkPages
  IworkDocument(container: openContainer(path))

proc kind*(doc: IworkDocument): DocKind =
  ## which application the document belongs to
  doc.container.docKind

proc index*(doc: IworkDocument): ObjectIndex =
  ## the document's object index, built on first access and cached
  if doc.indexCache.isNone:
    doc.indexCache = some(buildIndex(doc.container))
  doc.indexCache.get

proc plainText*(doc: IworkDocument): string =
  ## all document text, storages joined with newlines
  doc.index.extractText.join("\n")

proc textBlocks*(doc: IworkDocument): seq[TextBlock] =
  ## every piece of text in the document in reading order, each labeled
  ## with what it is (header, body, footer, text box, notes, table row)
  ## and which slide or sheet it came from
  runnableExamples "-r:off":
    let doc = openDocument("deck.key")
    for blk in doc.textBlocks:
      echo blk.section, " ", blk.kind, ": ", blk.text
  doc.index.textBlocks(doc.kind)

proc getText*(doc: IworkDocument): string =
  ## all of the document's text in reading order - headers, body,
  ## footers, text boxes, presenter notes and table rows - joined with
  ## newlines. falls back to `plainText` for documents whose structure
  ## doesn't decode, so there's always something to index
  runnableExamples "-r:off":
    echo openDocument("report.pages").getText()
  var parts: seq[string]
  try:
    for blk in doc.textBlocks:
      parts.add(blk.text)
  except IworkFormatError:
    return doc.plainText()
  parts.join("\n")

proc slides*(doc: IworkDocument): seq[Slide] =
  ## the presented slides of a keynote document, in deck order;
  ## raises IworkError for pages and numbers documents
  if doc.kind != dkKeynote:
    raise newException(IworkError,
      "slides() only works on keynote documents, this is a " & $doc.kind)
  doc.index.keynoteSlides

proc sheets*(doc: IworkDocument): seq[Sheet] =
  ## the sheets of a numbers document with their decoded tables;
  ## raises IworkError for keynote and pages documents
  if doc.kind != dkNumbers:
    raise newException(IworkError,
      "sheets() only works on numbers documents, this is a " & $doc.kind)
  doc.index.numbersSheets

proc tables*(doc: IworkDocument): seq[numbers.Table] =
  ## every table across all sheets, flattened in sheet order
  for sheet in doc.sheets:
    result.add(sheet.tables)

proc bodyText*(doc: IworkDocument): seq[string] =
  ## the body paragraphs of a pages document, in order;
  ## raises IworkError for keynote and numbers documents
  if doc.kind != dkPages:
    raise newException(IworkError,
      "bodyText() only works on pages documents, this is a " & $doc.kind)
  doc.index.pagesBodyText
