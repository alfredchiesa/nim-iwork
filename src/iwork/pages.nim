## structured pages reading: the document body text as paragraphs, plus
## the section headers and footers and any floating text boxes.
## tp.documentarchive holds a direct reference to the body's text
## storage, so this is a much shorter walk than keynote or numbers.

import std/[algorithm, logging, options, sets, strutils, tables, unicode]
import ./errors, ./numbers, ./objects, ./text, ./typemaps, ./wire

type
  PagesPieceKind* = enum
    ## where a piece of a pages document sits
    ppHeader  ## page header
    ppBody    ## body paragraph
    ppFooter  ## page footer
    ppTextBox ## floating text box
    ppTable   ## table, inline in the body or floating on a page

  PagesPiece* = object
    ## one piece of a pages document, with where it came from
    kind*: PagesPieceKind
    text*: string           ## the text, "" for tables
    table*: numbers.Table   ## the decoded table, for ppTable only
    objectId*: uint64       ## text storage or table model it came from

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
  # field 9 is the attachment table, same entry layout: a utf-16
  # character index at 1 and an attachment ref at 2
  storageAttachmentsField = 9
  entryCharIndexField = 1
  entryAttachmentField = 2
  # tswp.drawableattachmentarchive field 1 = the attached drawable
  attachmentDrawableField = 1
  # tp.documentarchive field 3 = floating drawables: one group per page
  # at field 1, each holding drawable entries at 4 with the ref at 1
  docFloatingField = 3
  floatingPagesField = 1
  pageDrawablesField = 4
  pageDrawableRefField = 1
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

proc pagesBodyText*(idx: ObjectIndex,
    warnings: var seq[ExtractionWarning]): seq[string] =
  ## like `pagesBodyText`, also noting a missing body storage in `warnings`
  let storage = idx.bodyStorage
  if storage.isNone:
    debug "pages document has no body storage"
    warnings.add(ExtractionWarning(kind: ewMissingReference,
      message: "pages document has no body storage"))
    return
  # paragraph breaks are newlines after cleaning, blank lines are just
  # spacing between paragraphs
  for paragraph in storageText(storage.get).split('\n'):
    if paragraph.strip.len > 0:
      result.add(paragraph)
  debug "pages: ", result.len, " body paragraphs"

proc pagesBodyText*(idx: ObjectIndex): seq[string] =
  ## the document body split into non-empty paragraphs, in order
  runnableExamples "-r:off":
    import iwork
    let doc = openDocument("report.pages")
    for paragraph in doc.index.pagesBodyText:
      echo paragraph
  var warnings: seq[ExtractionWarning]
  idx.pagesBodyText(warnings)

type Sourced = seq[tuple[text: string, id: uint64]]

proc addTexts(idx: ObjectIndex, archive: IworkObject, field: int,
    into: var Sourced) =
  # headers and footers repeat across page variants, so the same wording
  # shows up in several storages - keep the first of each
  for storage in idx.derefAll(archive.message, field):
    if storage.msgType != tswpStorageArchive:
      continue
    let cleaned = storageText(storage).strip
    var dupe = false
    for seen in into:
      dupe = dupe or seen.text == cleaned
    if cleaned.len > 0 and not dupe:
      into.add((cleaned, storage.id))

proc headersFooters(idx: ObjectIndex): tuple[headers, footers: Sourced] =
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

proc pagesHeadersFooters*(idx: ObjectIndex): tuple[headers, footers: seq[string]] =
  ## the header and footer text of every section, in section order,
  ## with repeated wording reported once
  let hf = idx.headersFooters
  for h in hf.headers:
    result.headers.add(h.text)
  for f in hf.footers:
    result.footers.add(f.text)

proc textBoxes(idx: ObjectIndex): Sourced =
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
      result.add((cleaned, storage.get.id))
  debug "pages: ", result.len, " text boxes"

proc pagesTextBoxes*(idx: ObjectIndex): seq[string] =
  ## text of every floating text box, in object id order; the body,
  ## header and footer storages shapes point back at are left out
  for box in idx.textBoxes:
    result.add(box.text)

proc byteOffset(s: string, utf16: int): int =
  # tswp character indexes count utf-16 code units, nim strings are utf-8
  var units = 0
  while result < s.len and units < utf16:
    units += (if int32(s.runeAt(result)) > 0xffff: 2 else: 1)
    result += s.runeLenAt(result)

proc paragraphEnd(s: string, at: int): int =
  # the first line or paragraph break at or after `at`, or the end
  result = at
  while result < s.len:
    if s[result] in {'\n', '\r'} or (s[result] == '\xe2' and
        result + 2 < s.len and s[result + 1] == '\x80' and
        s[result + 2] in {'\xa8', '\xa9'}):
      return
    inc result

proc addTable(idx: ObjectIndex, drawable: IworkObject, where: string,
    into: var seq[PagesPiece], seen: var HashSet[uint64],
    warnings: var seq[ExtractionWarning]): bool =
  # true when the drawable was a table we hadn't seen yet
  if drawable.msgType != tstTableInfoArchive:
    return
  let table = idx.decodeTable(drawable, warnings)
  if table.isNone:
    warnings.add(ExtractionWarning(kind: ewMissingReference,
      message: "a table " & where & " has no table model"))
  elif table.get.id notin seen:
    seen.incl(table.get.id)
    into.add(PagesPiece(kind: ppTable, table: table.get,
      objectId: table.get.id))
    result = true

proc bodyPieces(idx: ObjectIndex, storage: IworkObject,
    seen: var HashSet[uint64],
    warnings: var seq[ExtractionWarning]): seq[PagesPiece] =
  # tables anchored in the body come right after the paragraph holding
  # their anchor, so cut the raw text at those paragraph ends
  let raw = storage.message.getRepeatedString(3).join("")
  var cuts: seq[tuple[at: int, table: PagesPiece]]
  let attachments = storage.message.getMessage(storageAttachmentsField)
  if attachments.isSome:
    for entry in attachments.get.getRepeatedMessage(sectionTableEntriesField):
      let attachment = idx.deref(entry, entryAttachmentField)
      if attachment.isNone:
        continue
      let drawable = idx.deref(attachment.get.message, attachmentDrawableField)
      var found: seq[PagesPiece]
      if drawable.isSome and
          idx.addTable(drawable.get, "in the body", found, seen, warnings):
        let at = int(entry.getUint(entryCharIndexField).get(0))
        cuts.add((paragraphEnd(raw, byteOffset(raw, at)), found[0]))
  cuts.sort(proc (a, b: tuple[at: int, table: PagesPiece]): int =
    cmp(a.at, b.at))
  var start = 0
  for i in 0 .. cuts.len:
    let stop = if i < cuts.len: cuts[i].at else: raw.len
    # paragraph breaks are newlines after cleaning, blank lines are just
    # spacing between paragraphs
    for paragraph in cleanRun(raw[start ..< stop]).split('\n'):
      if paragraph.strip.len > 0:
        result.add(PagesPiece(kind: ppBody, text: paragraph,
          objectId: storage.id))
    if i < cuts.len:
      result.add(cuts[i].table)
      start = stop

proc pagesPieces*(idx: ObjectIndex, warnings: var seq[ExtractionWarning],
    headers = true, footers = true): seq[PagesPiece] =
  ## everything `textBlocks` reads from a pages document, in reading
  ## order: headers, body paragraphs with each anchored table right after
  ## its paragraph, footers, text boxes, then tables floating on pages.
  ## page numbers aren't known, so pieces aren't tied to pages
  let hf = idx.headersFooters
  if headers:
    for h in hf.headers:
      result.add(PagesPiece(kind: ppHeader, text: h.text, objectId: h.id))
  var seen: HashSet[uint64]
  let body = idx.bodyStorage
  if body.isNone:
    debug "pages document has no body storage"
    warnings.add(ExtractionWarning(kind: ewMissingReference,
      message: "pages document has no body storage"))
  else:
    result.add(idx.bodyPieces(body.get, seen, warnings))
  if footers:
    for f in hf.footers:
      result.add(PagesPiece(kind: ppFooter, text: f.text, objectId: f.id))
  for box in idx.textBoxes:
    result.add(PagesPiece(kind: ppTextBox, text: box.text, objectId: box.id))
  let floating = idx.deref(idx.docArchive.message, docFloatingField)
  if floating.isSome and floating.get.msgType == tpFloatingDrawablesArchive:
    for page in floating.get.message.getRepeatedMessage(floatingPagesField):
      for entry in page.getRepeatedMessage(pageDrawablesField):
        let drawable = idx.deref(entry, pageDrawableRefField)
        if drawable.isSome:
          discard idx.addTable(drawable.get, "on a page", result, seen,
            warnings)
