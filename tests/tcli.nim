# tests for the iworkextract cli: builds it once, then runs it the way a
# user would and checks stdout, stderr, and exit codes separately
import std/[json, os, osproc, streams, strutils, unittest]
import iwork
import ./iwabuild

const
  root = currentSourcePath().parentDir.parentDir
  fixtures = root / "tests" / "fixtures"

let
  work = getTempDir() / "iwork_cli_test"
  exe = work / "iworkextract".addFileExt(ExeExt)

removeDir(work)
createDir(work)
let build = execCmdEx(getCurrentCompilerExe().quoteShell &
  " c --hints:off -o:" & exe.quoteShell & " " &
  quoteShell(root / "src" / "iworkextract.nim"))
doAssert build.exitCode == 0, build.output

proc run(args: varargs[string]): tuple[output, errors: string, code: int] =
  let p = startProcess(exe, args = @args, options = {})
  # outputs here are small, so reading one pipe then the other is fine
  result.output = p.outputStream.readAll
  result.errors = p.errorStream.readAll
  result.code = p.waitForExit
  p.close()

suite "cli: basics":
  test "--help and --version exit 0 on stdout":
    let help = run("--help")
    check help.code == 0
    check "usage:" in help.output
    check "exit status" in help.output
    check help.errors == ""
    let nimble = readFile(root / "iwork.nimble")
    let version = nimble.split("version")[1].split('"')[1]
    check run("-v").output.strip == "iworkextract " & version

  test "usage errors exit 2 with a hint on stderr":
    for args in [@[], @["--bogus", "x.key"], @["--json", "--csv", "x.key"],
        @["--sheet", "S", "x.numbers"], @["--csv", "-o"],
        @["--csv", "a.numbers", "b.numbers"]]:
      let r = run(args)
      check r.code == 2
      check r.output == ""
      check "--help" in r.errors

suite "cli: text":
  test "one document prints its text":
    let r = run(fixtures / "simple.pages")
    check r.code == 0
    check r.output == openDocument(fixtures / "simple.pages").getText() & "\n"
    check r.errors == ""

  test "several documents keep their boundaries":
    let r = run("--text", fixtures / "simple.pages", fixtures / "simple.key")
    check r.code == 0
    let pagesAt = r.output.find("==> " & fixtures / "simple.pages" & " <==")
    let keyAt = r.output.find("==> " & fixtures / "simple.key" & " <==")
    check pagesAt == 0
    check keyAt > r.output.find("hello pages")
    check r.output.find("hello keynote") > keyAt

  test "a bad document fails alone, the batch carries on":
    let junk = work / "junk.pages"
    writeFile(junk, "not a zip")
    let r = run(junk, fixtures / "simple.key")
    check r.code == 1
    check "hello keynote" in r.output
    check junk in r.errors
    check "can't read zip" in r.errors

  test "warnings go to stderr, --strict turns them into failures":
    let dir = work / "nobody.pages"
    removeDir(dir)
    writeBundle(dir, iwaObject(1, tpDocumentArchive, "") &
      iwaObject(2, tswpStorageArchive, pbBytes(3, "Recoverable text")))
    let loose = run(dir)
    check loose.code == 0
    check loose.output == "Recoverable text\n"
    check "warning: pages document has no body storage" in loose.errors
    let strict = run("--strict", dir)
    check strict.code == 1
    check strict.output == ""
    check "incomplete text extraction" in strict.errors

suite "cli: json":
  test "one array entry per document, failures included":
    let junk = work / "junk.key"
    writeFile(junk, "")
    let r = run("--json", fixtures / "simple.pages", junk,
      fixtures / "rich.numbers")
    check r.code == 1
    let docs = parseJson(r.output)
    check docs.len == 3
    check docs[0]["path"].getStr == fixtures / "simple.pages"
    check docs[0]["ok"].getBool
    check docs[0]["kind"].getStr == "pages"
    check docs[0]["text"].getStr ==
      openDocument(fixtures / "simple.pages").getText()
    check docs[0]["blocks"][0]["kind"].getStr == "body"
    check docs[0]["warnings"].len == 0
    check not docs[0]["usedFallback"].getBool
    check not docs[1]["ok"].getBool
    check docs[1]["error"].getStr.len > 0
    check docs[2]["sheets"][0]["name"].getStr == "Overview"
    check docs[2]["sheets"][0]["tables"][0]["rows"][1][1].getStr == "337500"

suite "cli: csv":
  let rich = fixtures / "rich.numbers"
  let book = openDocument(rich)

  test "a selected table goes to stdout, by name or by number":
    let byName = run("--csv", "--sheet", "Assets", "--table", "Liquid Assets",
      rich)
    check byName.code == 0
    check byName.output == toCsv(book.sheets[1].tables[1]) & "\n"
    check run("--csv", "--sheet=2", "--table=2", rich).output == byName.output

  test "selection errors list what's available":
    let r = run("--csv", "--sheet", "Nope", rich)
    check r.code == 1
    check r.output == ""
    check "available: Overview / Total Assets" in r.errors

  test "several matching tables need --output":
    let r = run("--csv", rich)
    check r.code == 1
    check "8 tables match" in r.errors

  test "csv on a non-numbers document fails":
    check run("--csv", fixtures / "simple.key").code == 1

  test "--output writes one file per table without clobbering":
    let dir = work / "csv"
    removeDir(dir)
    let simple = fixtures / "simple.numbers"
    let r = run("--csv", "-o", dir, rich, simple, simple)
    check r.code == 0
    let written = r.output.strip.splitLines
    check written.len == 10
    check dir / "rich_Overview_Total Assets.csv" in written
    check dir / "simple_Sheet 1_Table 1.csv" in written
    check dir / "simple_Sheet 1_Table 1-2.csv" in written
    check readFile(dir / "rich_Overview_Total Assets.csv") ==
      toCsv(book.tables[0]) & "\n"
    let again = run("--csv", "--output", dir, simple)
    check again.code == 1
    check "refusing to overwrite" in again.errors
    check run("--csv", "--output", dir, "--force", simple).code == 0

removeDir(work)
