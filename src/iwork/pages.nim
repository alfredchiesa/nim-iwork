## structured pages reading: the document body text as paragraphs.
## tp.documentarchive holds a direct reference to the body's text
## storage, so this is a much shorter walk than keynote or numbers.

import std/[logging, strutils, tables]
import ./errors, ./objects, ./text, ./typemaps, ./wire

const
  # tp.documentarchive field 4 = body storage ref
  # (verified against real documents)
  docBodyStorageField = 4

proc pagesBodyText*(idx: ObjectIndex): seq[string] =
  ## the document body split into non-empty paragraphs, in order
  runnableExamples "-r:off":
    import iwork
    let doc = openDocument("report.pages")
    for paragraph in doc.index.pagesBodyText:
      echo paragraph
  var docArchive: IworkObject
  for obj in idx.objects.values:
    if obj.msgType == tpDocumentArchive:
      docArchive = obj
      break
  if docArchive.isNil:
    raise newException(IworkFormatError,
      "no tp.documentarchive object in document")
  let storage = idx.deref(docArchive.message, docBodyStorageField)
  if storage.isNone or storage.get.msgType != tswpStorageArchive:
    debug "pages document has no body storage"
    return
  # paragraph breaks are newlines after cleaning, blank lines are just
  # spacing between paragraphs
  for paragraph in storageText(storage.get).split('\n'):
    if paragraph.strip.len > 0:
      result.add(paragraph)
  debug "pages: ", result.len, " body paragraphs"
