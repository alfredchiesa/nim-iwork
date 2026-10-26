# tests for numbers sheet/table/cell reading against real fixtures
import std/[math, os, strutils, tables, times, unittest]
import iwork
import ./iwabuild

const fixtures = currentSourcePath().parentDir / "fixtures"

proc u32(v: uint32): string =
  for i in 0 ..< 4:
    result.add(char((v shr (i * 8)) and 0xff))

proc f64(v: float64): string =
  let bits = cast[uint64](v)
  for i in 0 ..< 8:
    result.add(char((bits shr (i * 8)) and 0xff))

proc record(cellType: int, flags: uint32, payload: string): string =
  # hand-built v5 record: version, type, reserved, extras, flags, fields
  "\x05" & char(cellType) & "\x00\x00" & u32(0) & u32(flags) & payload

suite "numbers: simple.numbers":
  # note: the real fixture content is a,b,C / 1,2,3 / x,y,Z -
  # autocapitalization got the C and Z when the doc was made
  test "one sheet with one 3x3 table":
    let doc = openDocument(fixtures / "simple.numbers")
    check doc.sheets.len == 1
    check doc.sheets[0].name == "Sheet 1"
    check doc.sheets[0].tables.len == 1
    let t = doc.sheets[0].tables[0]
    check t.name == "Table 1"
    check t.numRows == 3
    check t.numCols == 3

  test "text cells decode with exact values":
    let t = openDocument(fixtures / "simple.numbers").tables[0]
    for (row, col, want) in [(0, 0, "a"), (0, 1, "b"), (0, 2, "C"),
        (2, 0, "x"), (2, 1, "y"), (2, 2, "Z")]:
      let v = t.cell(row, col)
      check v.kind == ckText
      check v.text == want

  test "number cells decode with exact values":
    let t = openDocument(fixtures / "simple.numbers").tables[0]
    for (col, want) in [(0, 1.0), (1, 2.0), (2, 3.0)]:
      let v = t.cell(1, col)
      check v.kind == ckNumber
      check v.number == want

  test "rows iterator yields the whole grid":
    let t = openDocument(fixtures / "simple.numbers").tables[0]
    var count = 0
    for row in t.rows:
      check row.len == 3
      inc count
    check count == 3

suite "numbers: rich.numbers":
  # the fixture is apple's net worth template: 3 sheets, 8 tables,
  # text plus currency values plus cached formula totals
  test "sheet and table structure":
    let doc = openDocument(fixtures / "rich.numbers")
    check doc.sheets.len == 3
    check doc.sheets[0].name == "Overview"
    check doc.sheets[1].name == "Assets"
    check doc.sheets[2].name == "Liabilities"
    check doc.tables.len == 8

  test "mixed types decode without raising":
    for t in openDocument(fixtures / "rich.numbers").tables:
      for row in t.rows:
        for v in row:
          check v.kind in {ckText, ckNumber, ckEmpty}

  test "empty cell decodes as empty":
    let doc = openDocument(fixtures / "rich.numbers")
    # long-term liabilities has an intentionally blank header cell
    check doc.sheets[2].tables[0].name == "Long-Term Liabilities"
    check doc.sheets[2].tables[0].cell(0, 0).kind == ckEmpty

  test "currency values decode exactly":
    let t = openDocument(fixtures / "rich.numbers").tables[0]
    check t.name == "Total Assets"
    check t.cell(1, 1).number == 337500.0
    check t.cell(2, 1).number == 66435.0
    check t.cell(3, 1).number == 53550.0

  test "formula cell yields its cached display value":
    # the totals are sum formulas; we surface the cached result
    let t = openDocument(fixtures / "rich.numbers").tables[0]
    check t.cell(4, 1).kind == ckNumber
    check t.cell(4, 1).number == 457485.0

suite "numbers: cell record decoding":
  # rich.numbers has no date/bool/duration cells, so these decode paths
  # are pinned with synthetic v5 records built byte-by-byte above
  let noStrings = initTable[uint32, string]()

  test "date cell has the right calendar date":
    # 2026-07-04 12:00:00 utc is 804859200 seconds after 2001-01-01
    let v = decodeCellAt(record(5, 0x4, f64(804859200.0)), 0, noStrings)
    check v.kind == ckDate
    check v.date.year == 2026
    check v.date.month == mJul
    check v.date.monthday == 4

  test "boolean cell decodes from the double field":
    let t = decodeCellAt(record(6, 0x2, f64(1.0)), 0, noStrings)
    check t.kind == ckBool
    check t.boolean == true
    let f = decodeCellAt(record(6, 0x2, f64(0.0)), 0, noStrings)
    check f.boolean == false

  test "duration cell decodes seconds":
    let v = decodeCellAt(record(7, 0x2, f64(3600.0)), 0, noStrings)
    check v.kind == ckDuration
    check v.durationSeconds == 3600.0

  test "unknown cell type becomes an error value, not a crash":
    let v = decodeCellAt(record(42, 0, ""), 0, noStrings)
    check v.kind == ckError

  test "truncated record becomes an error value, not a crash":
    let v = decodeCellAt("\x05\x03", 0, noStrings)
    check v.kind == ckError

proc d128(coefficient: uint64, exponent: int, highBit = false,
    negative = false): string =
  # decimal128 as numbers writes it: coefficient in bytes 0-13 plus the
  # low bit of byte 14, then a 14-bit exponent biased by 0x1820 and a sign
  result = newString(16)
  for i in 0 ..< 8:
    result[i] = char((coefficient shr (i * 8)) and 0xff)
  let biased = exponent + 0x1820
  result[14] = char(((biased and 0x7f) shl 1) or ord(highBit))
  result[15] = char((biased shr 7) or (if negative: 0x80 else: 0))

suite "numbers: decimal128 cells":
  let noStrings = initTable[uint32, string]()

  test "ordinary coefficients decode":
    check decodeCellAt(record(2, 0x1, d128(337500, 0)), 0,
      noStrings).number == 337500.0
    check almostEqual(decodeCellAt(record(2, 0x1, d128(12345, -2)), 0,
      noStrings).number, 123.45)
    check decodeCellAt(record(2, 0x1, d128(42, 3, negative = true)), 0,
      noStrings).number == -42000.0

  test "the coefficient's high bit is worth 2^112":
    let v = decodeCellAt(record(2, 0x1, d128(0, 0, highBit = true)), 0,
      noStrings)
    check v.kind == ckNumber
    check v.number == pow(2.0, 112)
    let w = decodeCellAt(record(2, 0x1, d128(0, -30, highBit = true)), 0,
      noStrings)
    check almostEqual(w.number, pow(2.0, 112) * 1e-30)

suite "numbers: cell offsets":
  test "ordinary offsets are byte offsets":
    check cellOffsets("\x00\x00\x10\x00\x24\x00") == @[0, 16, 36]

  test "wide offsets count 4-byte units":
    check cellOffsets("\x00\x00\x04\x00\x09\x00", wide = true) == @[0, 16, 36]

  test "0xffff stays the empty-cell sentinel either way":
    check cellOffsets("\xff\xff\x04\x00") == @[-1, 4]
    check cellOffsets("\xff\xff\x04\x00", wide = true) == @[-1, 16]

proc textCell(id: uint32): string = record(3, 0x8, u32(id))

proc rowInfo(tileRow: int, cells: seq[string], wide: bool): string =
  # "" is an empty cell; every record is a multiple of 4 bytes long, so
  # wide offsets can address them all
  var buf, offsets: string
  for c in cells:
    var o = 0xffff
    if c.len > 0:
      o = if wide: buf.len div 4 else: buf.len
      buf.add(c)
    offsets.add(char(o and 0xff) & char(o shr 8))
  pbUint(1, uint64(tileRow)) & pbBytes(6, buf) & pbBytes(7, offsets) &
    (if wide: pbUint(8, 1) else: "")

proc writeSyntheticBook(dir: string, dropSecondTile = false) =
  # one 257x3 table split over two 256-row tiles: row 0 uses ordinary
  # offsets, rows 255 and 256 sit either side of the tile boundary and
  # use wide ones
  var strings: string
  for (key, s) in [(1, "a"), (2, "b"), (3, "c"), (4, "d"), (5, "e")]:
    strings.add(pbBytes(3, pbUint(1, uint64(key)) & pbBytes(3, s)))
  let tile0 =
    pbBytes(5, rowInfo(0, @[textCell(1), "", record(10, 0x2, f64(2.5))],
      wide = false)) &
    pbBytes(5, rowInfo(255, @["", textCell(2), textCell(3)], wide = true))
  let tile1 =
    pbBytes(5, rowInfo(0, @[textCell(4), textCell(5), ""], wide = true))
  let tileStorage =
    pbBytes(1, pbUint(1, 0) & pbRef(2, 5)) &
    pbBytes(1, pbUint(1, 1) & pbRef(2, if dropSecondTile: 99 else: 6))
  let model = pbBytes(4, pbBytes(3, tileStorage) & pbRef(4, 7)) &
    pbUint(6, 257) & pbUint(7, 3) & pbBytes(8, "T")
  writeBundle(dir,
    iwaObject(1, tnDocumentArchive, pbRef(1, 2)) &
    iwaObject(2, tnSheetArchive, pbBytes(1, "S") & pbRef(2, 3)) &
    iwaObject(3, tstTableInfoArchive, pbRef(2, 4)) &
    iwaObject(4, tstTableModelArchive, model) &
    iwaObject(5, tstTileArchive, tile0) &
    iwaObject(6, tstTileArchive, tile1) &
    iwaObject(7, tstTableDataList, strings))

suite "numbers: synthetic tiles and offsets":
  let dir = getTempDir() / "iwork_synth_tiles.numbers"
  removeDir(dir)
  writeSyntheticBook(dir)
  let t = openDocument(dir).tables[0]

  test "ordinary offsets decode, empty cells stay empty":
    check t.cell(0, 0).text == "a"
    check t.cell(0, 1).kind == ckEmpty
    check t.cell(0, 2).number == 2.5

  test "wide offsets decode on the last row of a tile":
    check t.cell(255, 0).kind == ckEmpty
    check t.cell(255, 1).text == "b"
    check t.cell(255, 2).text == "c"

  test "wide offsets decode on the first row of the next tile":
    check t.cell(256, 0).text == "d"
    check t.cell(256, 1).text == "e"
    check t.cell(256, 2).kind == ckEmpty

  test "rows without a row info are empty":
    check t.cell(1, 0).kind == ckEmpty
    check t.cell(254, 2).kind == ckEmpty

  test "a missing tile is reported, the rest still decodes":
    let broken = getTempDir() / "iwork_synth_missing_tile.numbers"
    removeDir(broken)
    writeSyntheticBook(broken, dropSecondTile = true)
    defer: removeDir(broken)
    let doc = openDocument(broken)
    check doc.tables[0].cell(255, 2).text == "c"
    check doc.tables[0].cell(256, 0).kind == ckEmpty
    let report = doc.getTextReport()
    check report.warnings.len == 1
    check report.warnings[0].kind == ewMissingReference
    check not report.usedFallback
    check "b\tc" in report.text.splitLines

  removeDir(dir)

suite "numbers: numbers-parser large fixtures":
  # upstream fixtures with expectations from numbers-parser's
  # tests/test_large.py, see fixtures/NOTICE-numbers-parser.txt
  proc textOrEmpty(v: CellValue): string =
    check v.kind in {ckText, ckEmpty}
    if v.kind == ckText: v.text else: ""

  test "600-row and 600-column tables decode every cell":
    let doc = openDocument(fixtures / "numbers-parser-test-3.numbers")
    check doc.sheets[0].name == "Sheet_1"
    let tall = doc.sheets[0].tables[0]
    check tall.numRows == 600
    check tall.numCols == 1
    for r in 0 ..< 600:
      check tall.cell(r, 0).textOrEmpty == "ROW" & $(r + 1)
    check doc.sheets[1].name == "Sheet_2"
    let wide = doc.sheets[1].tables[0]
    check wide.numRows == 1
    check wide.numCols == 600
    for c in 0 ..< 600:
      check wide.cell(0, c).textOrEmpty == "COLUMN" & $(c + 1)

  test "90x270 sparse table decodes every cell":
    let t = openDocument(fixtures / "numbers-parser-test-6.numbers").tables[0]
    check t.numRows == 90
    check t.numCols == 270
    for r in 0 ..< 90:
      for c in 0 ..< 270:
        let want =
          if c mod 90 == r: "CELL [" & $(r + 1) & "," & $(c + 1) & "]"
          else: ""
        check t.cell(r, c).textOrEmpty == want

suite "numbers: csv":
  test "toCsv of the first rich table matches golden":
    let t = openDocument(fixtures / "rich.numbers").tables[0]
    check toCsv(t) == readFile(
      currentSourcePath().parentDir / "golden" / "rich.numbers.csv")

suite "numbers: wrong document kind":
  test "sheets on a keynote doc raises IworkError":
    expect IworkError:
      discard openDocument(fixtures / "simple.key").sheets
