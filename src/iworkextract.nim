# iworkextract: pull text, json, or csv out of keynote, pages, and
# numbers documents without writing any nim. installed by nimble as a bin.
import std/[json, os, parseopt, sets, strutils]
import iwork

const
  # release-please rewrites the nimble version line, so read it from there
  pkgVersion = block:
    var v = "unknown"
    for line in staticRead("../iwork.nimble").splitLines:
      if line.startsWith("version"):
        v = line.split('"')[1]
        break
    v

  usage = """iworkextract - extract text, json, or csv from iwork documents

usage:
  iworkextract [mode] [options] <document>...

modes (default --text):
  --text            all text in reading order; with several documents each
                    one starts with a "==> path <==" header line
  --json            a json array with one object per document, failures
                    included as {"path": ..., "ok": false, "error": ...}
  --csv             numbers tables as csv

csv options:
  --sheet NAME      only tables on this sheet (exact name, else a 1-based
                    number)
  --table NAME      only tables with this name (exact name, else a 1-based
                    number within each selected sheet)
  -o, --output DIR  write every selected table to
                    DIR/<document>_<sheet>_<table>.csv and print the paths
                    written; clashing names get -2, -3, ... appended.
                    without it, exactly one table from one document is
                    written to stdout
  --force           overwrite files that already exist in DIR

other options:
  --strict          fail a document on any known extraction gap instead of
                    warning about it
  -h, --help        show this help
  -v, --version     show the version

results go to stdout, warnings and errors to stderr.
exit status: 0 if every document succeeded, 1 if any failed (the rest are
still processed), 2 for usage errors."""

type
  Mode = enum
    mText, mJson, mCsv

  Options = object
    mode: Mode
    modeSet: bool
    sheet, table, outDir: string
    hasSheet, hasTable, force, strict: bool
    paths: seq[string]

  UsageError = object of CatchableError

proc diag(path, msg: string) =
  stderr.writeLine("iworkextract: " & path & ": " & msg)

func tag(e: enum): string =
  # dkPages -> pages, ewMissingReference -> missingReference
  let s = $e
  result = s[2 .. ^1]
  result[0] = result[0].toLowerAscii

proc reportWarnings(path: string, warnings: seq[ExtractionWarning],
    usedFallback = false) =
  for w in warnings:
    diag(path, "warning: " & w.message)
  if usedFallback:
    diag(path, "warning: structured extraction came up short, " &
      "fell back to raw storage text")

proc parseArgs(): Options =
  var p = initOptParser(shortNoVal = {'h', 'v'},
    longNoVal = @["help", "version", "text", "json", "csv", "force", "strict"])
  var wantOutput = false
  for kind, key, val in p.getopt():
    let flag = (if kind == cmdShortOption: "-" else: "--") & key
    case kind
    of cmdArgument:
      if wantOutput:
        # parseopt's default mode won't hand `-o DIR` its value, so the
        # next argument is the dir
        result.outDir = key
        wantOutput = false
      else:
        result.paths.add(key)
    of cmdLongOption, cmdShortOption:
      if wantOutput:
        raise newException(UsageError, "-o needs a value")
      case key
      of "h", "help":
        echo usage
        quit(0)
      of "v", "version":
        echo "iworkextract ", pkgVersion
        quit(0)
      of "text", "json", "csv":
        let m = (if key == "text": mText elif key == "json": mJson else: mCsv)
        if result.modeSet and result.mode != m:
          raise newException(UsageError, "pick one of --text, --json, --csv")
        result.mode = m
        result.modeSet = true
      of "sheet", "table", "o", "output":
        if val.len == 0 and key == "o":
          wantOutput = true
          continue
        if val.len == 0:
          raise newException(UsageError, flag & " needs a value")
        case key
        of "sheet":
          result.sheet = val
          result.hasSheet = true
        of "table":
          result.table = val
          result.hasTable = true
        else:
          result.outDir = val
      of "force": result.force = true
      of "strict": result.strict = true
      else:
        raise newException(UsageError, "unknown option: " & flag)
    of cmdEnd:
      discard
  if wantOutput:
    raise newException(UsageError, "-o needs a value")
  if result.paths.len == 0:
    raise newException(UsageError, "no documents given")
  if result.mode != mCsv and (result.hasSheet or result.hasTable or
      result.outDir.len > 0 or result.force):
    raise newException(UsageError,
      "--sheet, --table, --output, and --force only work with --csv")
  if result.mode == mCsv and result.outDir.len == 0 and result.paths.len > 1:
    raise newException(UsageError,
      "--csv with several documents needs --output DIR")

proc textOf(path: string, opts: Options): string =
  let report = openDocument(path).getTextReport(strict = opts.strict)
  reportWarnings(path, report.warnings, report.usedFallback)
  report.text

proc jsonOf(path: string, opts: Options): JsonNode =
  let doc = openDocument(path)
  let report = doc.getTextReport(strict = opts.strict)
  reportWarnings(path, report.warnings, report.usedFallback)
  var warnings = newJArray()
  for w in report.warnings:
    warnings.add(%*{"kind": tag(w.kind), "message": w.message})
  var blocks = newJArray()
  if not report.usedFallback:
    for blk in doc.textBlocks:
      blocks.add(%*{"kind": tag(blk.kind), "section": blk.section,
        "text": blk.text})
  result = %*{"path": path, "ok": true, "kind": tag(doc.kind),
    "text": report.text, "usedFallback": report.usedFallback,
    "warnings": warnings, "blocks": blocks}
  if doc.kind == dkNumbers and not report.usedFallback:
    var sheets = newJArray()
    for sheet in doc.sheets:
      var tables = newJArray()
      for t in sheet.tables:
        var rows = newJArray()
        for row in t.rows:
          var cells = newJArray()
          for v in row:
            cells.add(%v.asString)
          rows.add(cells)
        tables.add(%*{"name": t.name, "rows": rows})
      sheets.add(%*{"name": sheet.name, "textBoxes": sheet.textBoxes,
        "tables": tables})
    result["sheets"] = sheets

proc pick(names: seq[string], sel: string, useSel: bool): seq[int] =
  # exact name matches win, otherwise a 1-based number
  for i, n in names:
    if not useSel or n == sel:
      result.add(i)
  if useSel and result.len == 0:
    try:
      let n = parseInt(sel)
      if n in 1 .. names.len:
        result.add(n - 1)
    except ValueError:
      discard

func safeName(s: string): string =
  for c in s:
    result.add(if c in {'\0' .. '\x1f', '/', '\\', ':', '*', '?', '"', '<',
      '>', '|'}: '_' else: c)
  # no hidden files and no "..", ever
  result = result.strip(chars = {' ', '.'})
  if result.len == 0:
    result = "untitled"

proc csvOf(path: string, opts: Options, used: var HashSet[string]) =
  let doc = openDocument(path)
  if doc.kind != dkNumbers:
    raise newException(IworkError,
      "--csv needs a numbers document, this is " & tag(doc.kind))
  var warnings: seq[ExtractionWarning]
  let sheets = doc.index.numbersSheets(warnings)
  reportWarnings(path, warnings)
  if opts.strict and warnings.len > 0:
    raise newException(IworkFormatError,
      "incomplete extraction (--strict): " & warnings[0].message)

  var available: seq[string]
  var chosen: seq[tuple[sheet, table: int]]
  var sheetNames: seq[string]
  for s in sheets:
    sheetNames.add(s.name)
    for t in s.tables:
      available.add(s.name & " / " & t.name)
  for si in pick(sheetNames, opts.sheet, opts.hasSheet):
    var tableNames: seq[string]
    for t in sheets[si].tables:
      tableNames.add(t.name)
    for ti in pick(tableNames, opts.table, opts.hasTable):
      chosen.add((si, ti))
  if chosen.len == 0:
    raise newException(IworkError, "no table matches the selection; " &
      "available: " & (if available.len > 0: available.join(", ")
      else: "none"))

  if opts.outDir.len == 0:
    if chosen.len > 1:
      var names: seq[string]
      for c in chosen:
        names.add(sheets[c.sheet].name & " / " &
          sheets[c.sheet].tables[c.table].name)
      raise newException(IworkError, $chosen.len & " tables match (" &
        names.join(", ") & "); pick one with --sheet/--table or write " &
        "them all with --output DIR")
    echo toCsv(sheets[chosen[0].sheet].tables[chosen[0].table])
    return

  # work out every target first so a clash fails the document before
  # anything is written
  var taken = used
  var targets: seq[string]
  let stem = safeName(path.normalizedPath.extractFilename.changeFileExt(""))
  for c in chosen:
    let base = stem & "_" & safeName(sheets[c.sheet].name) & "_" &
      safeName(sheets[c.sheet].tables[c.table].name)
    var name = base & ".csv"
    var n = 2
    # case-insensitive, macos and windows filesystems usually are
    while name.toLowerAscii in taken:
      name = base & "-" & $n & ".csv"
      inc n
    taken.incl(name.toLowerAscii)
    let target = opts.outDir / name
    if fileExists(target) and not opts.force:
      raise newException(IOError,
        "refusing to overwrite " & target & " (use --force)")
    targets.add(target)
  createDir(opts.outDir)
  for i, c in chosen:
    writeFile(targets[i], toCsv(sheets[c.sheet].tables[c.table]) & "\n")
    echo targets[i]
  used = taken

proc main(): int =
  let opts =
    try:
      parseArgs()
    except UsageError as e:
      stderr.writeLine("iworkextract: " & e.msg)
      stderr.writeLine("try 'iworkextract --help'")
      return 2
  var
    failed = 0
    results = newJArray()
    used: HashSet[string]
    printed = false
  for path in opts.paths:
    try:
      case opts.mode
      of mText:
        let text = textOf(path, opts)
        if opts.paths.len > 1:
          if printed:
            echo ""
          echo "==> ", path, " <=="
        echo text
        printed = true
      of mJson:
        results.add(jsonOf(path, opts))
      of mCsv:
        csvOf(path, opts, used)
    except CatchableError as e:
      inc failed
      diag(path, e.msg)
      if opts.mode == mJson:
        results.add(%*{"path": path, "ok": false, "error": e.msg})
  if opts.mode == mJson:
    echo results.pretty
  if failed > 0: 1 else: 0

when isMainModule:
  quit(main())
