# tests for numbers sheet/table/cell reading against real fixtures
import std/[os, tables, times, unittest]
import iwork

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

suite "numbers: csv":
  test "toCsv of the first rich table matches golden":
    let t = openDocument(fixtures / "rich.numbers").tables[0]
    check toCsv(t) == readFile(
      currentSourcePath().parentDir / "golden" / "rich.numbers.csv")

suite "numbers: wrong document kind":
  test "sheets on a keynote doc raises IworkError":
    expect IworkError:
      discard openDocument(fixtures / "simple.key").sheets
