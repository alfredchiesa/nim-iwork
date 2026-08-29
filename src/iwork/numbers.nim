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
  # 2: tile ref}}, field 4 = shared string list ref
  storeTilesField = 3
  storeStringsField = 4
  tileStorageEntriesField = 1
  tileEntryIdField = 1
  tileEntryRefField = 2
  # rows per tile: tables are tiled in row chunks of this size
  tileRowStride = 256
  # tst.tabledatalist: field 3 = entries {1: key, 3: string}
  dataListEntriesField = 3
  entryKeyField = 1
  entryStringField = 3
  # tst.tile field 5 = repeated row infos: {1: row index in tile,
  # 5: storage version, 6: cell storage buffer, 7: cell offsets}
  tileRowInfosField = 5
  rowInfoIndexField = 1
  rowInfoBufferField = 6
  rowInfoOffsetsField = 7

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

proc buildTable(idx: ObjectIndex, model: IworkObject): Table =
  let msg = model.message
  result.name = msg.getString(modelNameField).get("")
  result.numRows = int(msg.getUint(modelRowsField).get(0))
  result.numCols = int(msg.getUint(modelColsField).get(0))
  result.grid = newSeq[seq[CellValue]](result.numRows)
  for row in result.grid.mitems:
    row = newSeq[CellValue](result.numCols)

  let dataStore = msg.getMessage(modelDataStoreField)
  if dataStore.isNone:
    debug "table ", result.name, " has no data store"
    return
  let strings = stringTable(idx, dataStore.get)

  let tileStorage = dataStore.get.getMessage(storeTilesField)
  if tileStorage.isNone:
    return
  for entry in tileStorage.get.getRepeatedMessage(tileStorageEntriesField):
    let tileId = int(entry.getUint(tileEntryIdField).get(0))
    let tile = idx.deref(entry, tileEntryRefField)
    if tile.isNone:
      continue
    for rowInfo in tile.get.message.getRepeatedMessage(tileRowInfosField):
      let rowIndex = tileId * tileRowStride +
        int(rowInfo.getUint(rowInfoIndexField).get(0))
      if rowIndex >= result.numRows:
        debug "tile row ", rowIndex, " outside table ", result.name
        continue
      let buf = rowInfo.getString(rowInfoBufferField).get("")
      let offsets = cellOffsets(rowInfo.getString(rowInfoOffsetsField).get(""))
      for col in 0 ..< min(result.numCols, offsets.len):
        if offsets[col] < 0:
          continue # 0xffff, empty cell
        result.grid[rowIndex][col] = decodeCellAt(buf, offsets[col], strings)
  debug "built table ", result.name, ": ", result.numRows, "x", result.numCols

proc numbersSheets*(idx: ObjectIndex): seq[Sheet] =
  ## walks the numbers document into sheets with decoded tables
  var docArchive: IworkObject
  for obj in idx.objects.values:
    if obj.msgType == tnDocumentArchive:
      docArchive = obj
      break
  if docArchive.isNil:
    raise newException(IworkFormatError,
      "no tn.documentarchive object in document")
  for sheetObj in idx.derefAll(docArchive.message, docSheetsField):
    var sheet = Sheet(name: sheetObj.message.getString(sheetNameField).get(""))
    for drawable in idx.derefAll(sheetObj.message, sheetDrawablesField):
      case drawable.msgType
      of tstTableInfoArchive:
        let model = idx.deref(drawable.message, infoModelField)
        if model.isSome and model.get.msgType == tstTableModelArchive:
          sheet.tables.add(buildTable(idx, model.get))
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
