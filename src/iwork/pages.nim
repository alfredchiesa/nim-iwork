## structured pages reading: the document body text as paragraphs, plus
## the section headers and footers and any floating text boxes.
## tp.documentarchive holds a direct reference to the body's text
## storage, so this is a much shorter walk than keynote or numbers.

import std/[algorithm, logging, options, strutils, tables]
import ./errors, ./objects, ./text, ./typemaps, ./wire

const
  # tp.documentarchive field 4 = body storage ref
  # (verified against real documents)
  docBodyStorageField = 4
  # the body storage's field 17 is the section table: entries at field 1
  # hold a character index (field 1) and a section ref (field 2), in
  # document order
  storageSectionsField = 17
  sectionTableEntriesField = 1
  entrySectionField = 2
  # a section keeps one headers/footers archive per page variant:
  # first page, even pages, odd pages
  sectionHeadersFootersFields = [23, 24, 25]
  # tp.headersfootersarchive: field 1 = the three header storages,
  # field 2 = the three footer storages (left, center, right)
  headersField = 1
  footersField = 2
  # tswp.shapeinfoarchive field 2 = the shape's text storage
  shapeStorageField = 2

proc docArchive(idx: ObjectIndex): IworkObject =
  for obj in idx.objects.values:
    if obj.msgType == tpDocumentArchive:
      return obj
  raise newException(IworkFormatError,
    "no tp.documentarchive object in document")

proc bodyStorage(idx: ObjectIndex): Option[IworkObject] =
  let storage = idx.deref(idx.docArchive.message, docBodyStorageField)
  if storage.isSome and storage.get.msgType == tswpStorageArchive:
    result = storage

proc pagesBodyText*(idx: ObjectIndex): seq[string] =
  ## the document body split into non-empty paragraphs, in order
  runnableExamples "-r:off":
    import iwork
    let doc = openDocument("report.pages")
    for paragraph in doc.index.pagesBodyText:
      echo paragraph
  let storage = idx.bodyStorage
  if storage.isNone:
    debug "pages document has no body storage"
    return
  # paragraph breaks are newlines after cleaning, blank lines are just
  # spacing between paragraphs
  for paragraph in storageText(storage.get).split('\n'):
    if paragraph.strip.len > 0:
      result.add(paragraph)
  debug "pages: ", result.len, " body paragraphs"

proc addTexts(idx: ObjectIndex, archive: IworkObject, field: int,
    into: var seq[string]) =
  # headers and footers repeat across page variants, so the same wording
  # shows up in several storages - keep the first of each
  for storage in idx.derefAll(archive.message, field):
    if storage.msgType != tswpStorageArchive:
      continue
    let cleaned = storageText(storage).strip
    if cleaned.len > 0 and cleaned notin into:
      into.add(cleaned)

proc pagesHeadersFooters*(idx: ObjectIndex): tuple[headers, footers: seq[string]] =
  ## the header and footer text of every section, in section order,
  ## with repeated wording reported once
  let storage = idx.bodyStorage
  if storage.isNone:
    return
  let sections = storage.get.message.getMessage(storageSectionsField)
  if sections.isNone:
    return
  for entry in sections.get.getRepeatedMessage(sectionTableEntriesField):
    let section = idx.deref(entry, entrySectionField)
    if section.isNone or section.get.msgType != tpSectionArchive:
      continue
    for field in sectionHeadersFootersFields:
      let archive = idx.deref(section.get.message, field)
      if archive.isNone or archive.get.msgType != tpHeadersFootersArchive:
        continue
      idx.addTexts(archive.get, headersField, result.headers)
      idx.addTexts(archive.get, footersField, result.footers)
  debug "pages: ", result.headers.len, " headers, ", result.footers.len,
    " footers"

proc pagesTextBoxes*(idx: ObjectIndex): seq[string] =
  ## text of every floating text box, in object id order; the body,
  ## header and footer storages shapes point back at are left out
  var skip: seq[uint64]
  let body = idx.bodyStorage
  if body.isSome:
    skip.add(body.get.id)
  for obj in idx.objects.values:
    if obj.msgType != tpHeadersFootersArchive:
      continue
    for field in [headersField, footersField]:
      for storage in idx.derefAll(obj.message, field):
        skip.add(storage.id)
  var ids: seq[uint64]
  for obj in idx.objects.values:
    if obj.msgType == tswpShapeInfoArchive:
      ids.add(obj.id)
  ids.sort()
  var seen: seq[uint64]
  for id in ids:
    let storage = idx.deref(idx.objects[id].message, shapeStorageField)
    if storage.isNone or storage.get.msgType != tswpStorageArchive or
        storage.get.id in skip or storage.get.id in seen:
      continue
    seen.add(storage.get.id)
    let cleaned = storageText(storage.get).strip
    if cleaned.len > 0:
      result.add(cleaned)
  debug "pages: ", result.len, " text boxes"
