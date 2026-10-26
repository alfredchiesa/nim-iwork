## structured numbers reading: tn.documentarchive -> sheets -> table
## infos -> table models -> tiles -> decoded cell grids. field numbers
## verified against real documents with numbers-parser as the reference.

runnableExamples "-r:off":
  import iwork
  let book = openDocument("budget.numbers")
  for sheet in book.sheets:
    for table in sheet.tables:
      echo sheet.name, " / ", table.name
      echo toCsv(table)

import std/[logging, options, strutils, tables]
import ./cellstorage, ./errors, ./objects, ./text, ./typemaps, ./wire

type
  Table* = object
    ## one table's decoded cell grid
    name*: string
    id*: uint64 ## the table model's object id
    numRows*: int
    numCols*: int
    grid: seq[seq[CellValue]]

  Sheet* = object
    ## one sheet and the tables on it
    name*: string
    tables*: seq[Table]
    textBoxes*: seq[string] ## text of the sheet's text boxes, in
                            ## drawable order

const
  # tn.documentarchive field 1 = repeated sheet refs
  docSheetsField = 1
  # tn.sheetarchive: field 1 = name, field 2 = drawable refs
  sheetNameField = 1
  sheetDrawablesField = 2
  # tst.tableinfoarchive field 2 = table model ref
  infoModelField = 2
  # tswp.shapeinfoarchive field 2 = the shape's text storage
  shapeStorageField = 2
  # tst.tablemodelarchive: 4 = data store, 6 = rows, 7 = cols, 8 = name
  modelDataStoreField = 4
  modelRowsField = 6
  modelColsField = 7
  modelNameField = 8
  # tst.datastore: field 3 = tile storage {entries at 1: {1: tileid,
  # 2: tile ref}}, field 4 = shared string list ref, field 17 = rich
  # text payload list ref
  storeTilesField = 3
  storeStringsField = 4
  storeRichTextField = 17
  tileStorageEntriesField = 1
  tileEntryIdField = 1
  tileEntryRefField = 2
  # rows per tile: tables are tiled in row chunks of this size
  tileRowStride = 256
  # tst.tabledatalist: field 3 = entries {1: key, 3: string}
  dataListEntriesField = 3
  entryKeyField = 1
  entryStringField = 3
  # rich text list entries hold a payload ref at 9, and the
  # tst.richtextpayloadarchive keeps its text storage ref at 1
  entryRichPayloadField = 9
  payloadStorageField = 1
  # tst.tile field 5 = repeated row infos: {1: row index in tile,
  # 5: storage version, 6: cell storage buffer, 7: cell offsets,
  # 8: has_wide_offsets}
  tileRowInfosField = 5
  rowInfoIndexField = 1
  rowInfoBufferField = 6
  rowInfoOffsetsField = 7
  rowInfoWideOffsetsField = 8

proc stringTable(idx: ObjectIndex, dataStore: WireMessage): tables.Table[uint32, string] =
  # text cells store a key into the table's shared string list
  let listObj = idx.deref(dataStore, storeStringsField)
  if listObj.isNone:
    return
  for entry in listObj.get.message.getRepeatedMessage(dataListEntriesField):
    let key = entry.getUint(entryKeyField)
    let s = entry.getString(entryStringField)
    if key.isSome and s.isSome:
      result[uint32(key.get)] = s.get

proc richTextTable(idx: ObjectIndex, dataStore: WireMessage): tables.Table[uint32, string] =
  # rich text cells store a key into this list, which points at a payload
  # wrapping a regular text storage. styling is ignored, plain text only
  let listObj = idx.deref(dataStore, storeRichTextField)
  if listObj.isNone:
    return
  for entry in listObj.get.message.getRepeatedMessage(dataListEntriesField):
    let key = entry.getUint(entryKeyField)
    let payload = idx.deref(entry, entryRichPayloadField)
    if key.isNone or payload.isNone or
        payload.get.msgType != tstRichTextPayloadArchive:
      continue
    let storage = idx.deref(payload.get.message, payloadStorageField)
    if storage.isSome and storage.get.msgType == tswpStorageArchive:
      result[uint32(key.get)] = storageText(storage.get)

proc buildTable(idx: ObjectIndex, model: IworkObject,
    warnings: var seq[ExtractionWarning]): Table =
  let msg = model.message
  result.name = msg.getString(modelNameField).get("")
  result.id = model.id
  result.numRows = int(msg.getUint(modelRowsField).get(0))
  result.numCols = int(msg.getUint(modelColsField).get(0))
  result.grid = newSeq[seq[CellValue]](result.numRows)
  for row in result.grid.mitems:
    row = newSeq[CellValue](result.numCols)

  let dataStore = msg.getMessage(modelDataStoreField)
  if dataStore.isNone:
    debug "table ", result.name, " has no data store"
    warnings.add(ExtractionWarning(kind: ewMissingReference,
      message: "table " & result.name & " has no data store"))
    return
  let strings = stringTable(idx, dataStore.get)
  let richTexts = richTextTable(idx, dataStore.get)
  var richMissing = 0

  let tileStorage = dataStore.get.getMessage(storeTilesField)
  if tileStorage.isNone:
    return
  for entry in tileStorage.get.getRepeatedMessage(tileStorageEntriesField):
    let tileId = int(entry.getUint(tileEntryIdField).get(0))
    let tile = idx.deref(entry, tileEntryRefField)
    if tile.isNone:
      warnings.add(ExtractionWarning(kind: ewMissingReference,
        message: "table " & result.name & " is missing tile " & $tileId))
      continue
    for rowInfo in tile.get.message.getRepeatedMessage(tileRowInfosField):
      let rowIndex = tileId * tileRowStride +
        int(rowInfo.getUint(rowInfoIndexField).get(0))
      if rowIndex >= result.numRows:
        debug "tile row ", rowIndex, " outside table ", result.name
        continue
      let buf = rowInfo.getString(rowInfoBufferField).get("")
      let offsets = cellOffsets(rowInfo.getString(rowInfoOffsetsField).get(""),
        wide = rowInfo.getUint(rowInfoWideOffsetsField).get(0) != 0)
      for col in 0 ..< min(result.numCols, offsets.len):
        if offsets[col] < 0:
          continue # 0xffff, empty cell
        var missing = false
        result.grid[rowIndex][col] = decodeCellAt(buf, offsets[col], strings,
          richTexts, missing)
        if missing:
          inc richMissing
  if richMissing > 0:
    warnings.add(ExtractionWarning(kind: ewMissingReference,
      message: "table " & result.name & ": " & $richMissing &
        " rich text cells don't resolve"))
  debug "built table ", result.name, ": ", result.numRows, "x", result.numCols

proc decodeTable*(idx: ObjectIndex, info: IworkObject,
    warnings: var seq[ExtractionWarning]): Option[Table] =
  ## decodes the table behind a tst.tableinfoarchive drawable. the table
  ## engine is shared, so this works for keynote and pages tables too;
  ## none when the info has no table model
  let model = idx.deref(info.message, infoModelField)
  if model.isSome and model.get.msgType == tstTableModelArchive:
    result = some(buildTable(idx, model.get, warnings))

proc lostRefs(msg: WireMessage, field, found: int, what: string,
    warnings: var seq[ExtractionWarning]) =
  # derefAll quietly drops refs it can't follow, so count what it lost
  let lost = msg.getRepeatedString(field).len - found
  if lost > 0:
    warnings.add(ExtractionWarning(kind: ewMissingReference,
      message: what & ": " & $lost & " references don't resolve"))

proc numbersSheets*(idx: ObjectIndex,
    warnings: var seq[ExtractionWarning]): seq[Sheet] =
  ## like `numbersSheets`, also noting sheets, drawables, and table parts
  ## that don't resolve in `warnings`
  var docArchive: IworkObject
  for obj in idx.objects.values:
    if obj.msgType == tnDocumentArchive:
      docArchive = obj
      break
  if docArchive.isNil:
    raise newException(IworkFormatError,
      "no tn.documentarchive object in document")
  let sheetObjs = idx.derefAll(docArchive.message, docSheetsField)
  lostRefs(docArchive.message, docSheetsField, sheetObjs.len,
    "document sheets", warnings)
  for sheetObj in sheetObjs:
    var sheet = Sheet(name: sheetObj.message.getString(sheetNameField).get(""))
    let drawables = idx.derefAll(sheetObj.message, sheetDrawablesField)
    lostRefs(sheetObj.message, sheetDrawablesField, drawables.len,
      "sheet " & sheet.name & " drawables", warnings)
    for drawable in drawables:
      case drawable.msgType
      of tstTableInfoArchive:
        let table = idx.decodeTable(drawable, warnings)
        if table.isSome:
          sheet.tables.add(table.get)
        else:
          warnings.add(ExtractionWarning(kind: ewMissingReference,
            message: "a table on sheet " & sheet.name & " has no table model"))
      of tswpShapeInfoArchive:
        let storage = idx.deref(drawable.message, shapeStorageField)
        if storage.isSome and storage.get.msgType == tswpStorageArchive:
          let cleaned = storageText(storage.get).strip
          if cleaned.len > 0:
            sheet.textBoxes.add(cleaned)
      else:
        discard
    result.add(sheet)
  debug "numbers: built ", result.len, " sheets"

proc numbersSheets*(idx: ObjectIndex): seq[Sheet] =
  ## walks the numbers document into sheets with decoded tables
  var warnings: seq[ExtractionWarning]
  idx.numbersSheets(warnings)

proc cell*(t: Table, row, col: int): CellValue =
  ## the decoded value at a 0-based row/column position
  if row < 0 or row >= t.numRows or col < 0 or col >= t.numCols:
    raise newException(IworkError,
      "cell " & $row & "," & $col & " outside " & $t.numRows & "x" & $t.numCols)
  t.grid[row][col]

iterator rows*(t: Table): seq[CellValue] =
  ## yields each row of the grid in order
  for row in t.grid:
    yield row

func csvEscape(s: string): string =
  if '"' in s or ',' in s or '\n' in s:
    "\"" & s.replace("\"", "\"\"") & "\""
  else:
    s

proc toCsv*(t: Table): string =
  ## the whole grid as csv, one line per row
  var lines: seq[string]
  for row in t.rows:
    var cells: seq[string]
    for v in row:
      cells.add(csvEscape(v.asString))
    lines.add(cells.join(","))
  lines.join("\n")
