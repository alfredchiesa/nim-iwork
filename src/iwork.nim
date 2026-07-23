# pure nim reader for apple keynote, pages, and numbers documents

import std/[options, strutils]
import iwork/[container, errors, objects, snappychunks, text, typemaps, wire]

export container, errors, objects, snappychunks, text, typemaps, wire

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
