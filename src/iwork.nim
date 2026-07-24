# pure nim reader for apple keynote, pages, and numbers documents

import std/[options, strutils]
import iwork/[cellstorage, container, errors, keynote, numbers, objects,
  snappychunks, text, typemaps, wire]

export cellstorage, container, errors, keynote, numbers, objects,
  snappychunks, text, typemaps, wire

type
  IworkDocument* = ref object
    ## an opened iwork document with a lazily built object index
    container*: IworkContainer
    indexCache: Option[ObjectIndex]

proc openDocument*(path: string): IworkDocument =
  ## opens a keynote, pages, or numbers document,
  ## auto-detecting the application from extension or content
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
