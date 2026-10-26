## structured keynote reading: walk kn.documentarchive -> show -> slide
## tree -> per-slide archives and pull out titles, body text, and notes.
## type and field numbers are sourced from the keynote-parser python
## project and verified against real documents.

runnableExamples "-r:off":
  import iwork
  let doc = openDocument("deck.key")
  for slide in doc.slides:
    echo slide.index, ": ", slide.title
    for line in slide.body:
      echo "  ", line

import std/[logging, options, sets, strutils, tables]
import ./errors, ./numbers, ./objects, ./text, ./typemaps, ./wire

type
  Slide* = object
    ## one presented slide (masters are not slides)
    index*: int           ## 1-based position in the deck
    title*: string        ## title placeholder text, "" if none
    body*: seq[string]    ## every other text box on the slide
    presenterNotes*: string ## note text, "" if none
    isSkipped*: bool      ## true when the slide is skipped in the show
    tables*: seq[numbers.Table] ## tables on the slide, grouped ones
                                ## included, in drawable order
    titleId*: uint64      ## text storage behind `title`, 0 if none
    bodyIds*: seq[uint64] ## text storage behind each `body` entry
    notesId*: uint64      ## text storage behind `presenterNotes`, 0 if none

const
  # kn.documentarchive field 2 = show (source: keynote-parser kn.proto)
  docShowField = 2
  # kn.showarchive field 3 = slide tree, whose field 2 is the repeated
  # slide node references in presentation order
  showSlideTreeField = 3
  slideTreeNodesField = 2
  # kn.slidenodearchive: field 2 = slide, field 4 = isskipped
  nodeSlideField = 2
  nodeIsSkippedField = 4
  # kn.slidearchive: field 5 = title placeholder, field 6 = body
  # placeholder, field 7 = drawables on the slide, field 42 repeats the
  # placeholder list in newer keynote versions, field 27 = note.
  # field 1 is the master slide - never follow it, master text is not
  # slide text
  slideTitleField = 5
  slideBodyField = 6
  slideDrawablesField = 7
  slideNoteField = 27
  slidePlaceholdersField = 42
  # a text drawable holds its storage ref either directly at field 2
  # (tswp.shapeinfoarchive) or inside its field-1 super at field 2
  # (kn.placeholderarchive wrapping the same shape message)
  shapeStorageField = 2
  shapeSuperField = 1
  # kn.notearchive field 1 = contained storage
  noteStorageField = 1
  # tsd.grouparchive field 2 = the grouped drawables
  groupChildrenField = 2

proc drawableStorage(idx: ObjectIndex, drawable: IworkObject): Option[IworkObject] =
  # try the direct shape layout first, then the placeholder super layout;
  # anything without a storage (images, movies, charts) resolves to none
  let direct = idx.deref(drawable.message, shapeStorageField)
  if direct.isSome and direct.get.msgType == tswpStorageArchive:
    return direct
  let super = drawable.message.getMessage(shapeSuperField)
  if super.isSome:
    let nested = idx.deref(super.get, shapeStorageField)
    if nested.isSome and nested.get.msgType == tswpStorageArchive:
      return nested

proc noteText(idx: ObjectIndex, slide: IworkObject, id: var uint64): string =
  let note = idx.deref(slide.message, slideNoteField)
  if note.isSome:
    let storage = idx.deref(note.get.message, noteStorageField)
    if storage.isSome and storage.get.msgType == tswpStorageArchive:
      result = storageText(storage.get).strip(leading = false, chars = {'\n'})
      id = storage.get.id

proc collect(idx: ObjectIndex, drawable: IworkObject,
    into: var seq[IworkObject], seen: var HashSet[uint64]) =
  # groups hold their drawables at field 2 and can nest; seen keeps a
  # drawable listed under several fields (or a cycle) from showing twice
  if drawable.id in seen:
    return
  seen.incl(drawable.id)
  if drawable.msgType == tsdGroupArchive:
    for child in idx.derefAll(drawable.message, groupChildrenField):
      idx.collect(child, into, seen)
  else:
    into.add(drawable)

proc buildSlide(idx: ObjectIndex, node: IworkObject, index: int,
    warnings: var seq[ExtractionWarning]): Slide =
  result.index = index
  result.isSkipped = node.message.getUint(nodeIsSkippedField).get(0) == 1
  let slide = idx.deref(node.message, nodeSlideField)
  if slide.isNone:
    warnings.add(ExtractionWarning(kind: ewMissingReference,
      message: "slide " & $index & " has no slide archive"))
    return
  let titlePlaceholder = idx.deref(slide.get.message, slideTitleField)

  # candidates come from every field that can hold text drawables; when
  # classification is ambiguous the text lands in body - losing no text
  # beats perfect labeling
  var candidates: seq[IworkObject]
  var seen: HashSet[uint64]
  for field in [slideTitleField, slideBodyField, slideDrawablesField,
      slidePlaceholdersField]:
    for drawable in idx.derefAll(slide.get.message, field):
      idx.collect(drawable, candidates, seen)

  var seenStorages, seenTables: seq[uint64]
  for drawable in candidates:
    if drawable.msgType == tstTableInfoArchive:
      let table = idx.decodeTable(drawable, warnings)
      if table.isNone:
        warnings.add(ExtractionWarning(kind: ewMissingReference,
          message: "a table on slide " & $index & " has no table model"))
      elif table.get.id notin seenTables:
        seenTables.add(table.get.id)
        result.tables.add(table.get)
      continue
    let storage = drawableStorage(idx, drawable)
    if storage.isNone or storage.get.id in seenStorages:
      continue
    seenStorages.add(storage.get.id)
    let cleaned = storageText(storage.get)
    if cleaned.strip.len == 0:
      continue
    if titlePlaceholder.isSome and drawable.id == titlePlaceholder.get.id and
        result.title.len == 0:
      result.title = cleaned
      result.titleId = storage.get.id
    else:
      result.body.add(cleaned)
      result.bodyIds.add(storage.get.id)

  result.presenterNotes = noteText(idx, slide.get, result.notesId)

proc keynoteSlides*(idx: ObjectIndex,
    warnings: var seq[ExtractionWarning]): seq[Slide] =
  ## like `keynoteSlides`, also noting slides that don't resolve in
  ## `warnings`
  var docArchive: IworkObject
  for obj in idx.objects.values:
    if obj.msgType == knDocumentArchive:
      docArchive = obj
      break
  if docArchive.isNil:
    raise newException(IworkFormatError,
      "no kn.documentarchive object in document")
  let show = idx.deref(docArchive.message, docShowField)
  if show.isNone:
    raise newException(IworkFormatError,
      "kn.documentarchive has no show reference")
  let slideTree = show.get.message.getMessage(showSlideTreeField)
  if slideTree.isNone:
    raise newException(IworkFormatError,
      "kn.showarchive has no slide tree")
  let nodes = idx.derefAll(slideTree.get, slideTreeNodesField)
  # derefAll quietly drops refs it can't follow, so count what it lost
  let lost = slideTree.get.getRepeatedString(slideTreeNodesField).len -
    nodes.len
  if lost > 0:
    warnings.add(ExtractionWarning(kind: ewMissingReference,
      message: "slide tree: " & $lost & " references don't resolve"))
  for i, node in nodes:
    result.add(buildSlide(idx, node, i + 1, warnings))
  debug "keynote: built ", result.len, " slides"

proc keynoteSlides*(idx: ObjectIndex): seq[Slide] =
  ## walks the show's slide tree into slide objects, in deck order
  var warnings: seq[ExtractionWarning]
  idx.keynoteSlides(warnings)
