# opening an iwork document container and exposing its entries.
# handles three layouts: a plain zip with Index/*.iwa, a zip holding a
# nested Index.zip, and a directory bundle with the same structure.

import std/[logging, os, strutils, tables, tempfiles]
import zippy/ziparchives
import ./errors

export errors

type
  ContainerKind* = enum
    ckZip    ## single-file zip document
    ckBundle ## directory bundle

  DocKind* = enum
    dkKeynote, dkPages, dkNumbers

  IworkContainer* = ref object
    path*: string
    kind*: ContainerKind
    docKind*: DocKind
    entries: OrderedTable[string, string]

const metadataPlistPath = "Metadata/Properties.plist"

proc loadZip(path: string): OrderedTable[string, string] =
  # eagerly pull every entry into memory; iwork docs are small enough
  let reader = openZipArchive(path)
  try:
    for entryPath in reader.walkFiles:
      result[entryPath] = reader.extractFile(entryPath)
  finally:
    reader.close()

proc explodeNestedIndex(entries: var OrderedTable[string, string]) =
  # some documents ship their iwa files inside a nested Index.zip.
  # zippy only opens archives from disk, so bounce through a temp file.
  if "Index.zip" notin entries:
    return
  let (tmpFile, tmpPath) = createTempFile("iwork_index_", ".zip")
  try:
    tmpFile.write(entries["Index.zip"])
    tmpFile.close()
    for innerPath, data in loadZip(tmpPath):
      # normalize so callers always address iwa files as Index/<name>
      let key =
        if innerPath.startsWith("Index/"): innerPath
        else: "Index/" & innerPath
      entries[key] = data
    entries.del("Index.zip")
  finally:
    removeFile(tmpPath)

proc loadBundle(path: string): OrderedTable[string, string] =
  for filePath in walkDirRec(path, relative = true):
    result[filePath.replace(DirSep, '/')] = readFile(path / filePath)

proc hasIwaEntries(entries: OrderedTable[string, string]): bool =
  for entryPath in entries.keys:
    if entryPath.endsWith(".iwa"):
      return true

proc checkLegacy(entries: OrderedTable[string, string], path: string) =
  # pre-2013 documents keep their content in index.xml / index.apxl
  # and have no .iwa entries at all
  const legacyMarkers = ["index.xml", "index.apxl", "index.apxl.gz"]
  if entries.hasIwaEntries:
    return
  for entryPath in entries.keys:
    if entryPath.toLowerAscii in legacyMarkers:
      raise newException(IworkUnsupportedError,
        path & " looks like a pre-2013 iwork document (found " & entryPath &
        "). only the iwork 2013+ format with .iwa archives is supported.")

proc sniffDocKind(entries: OrderedTable[string, string]): DocKind =
  # heuristic for extensionless input: keynote docs carry slide archives,
  # numbers docs carry the calculation engine, pages is the fallback
  for entryPath in entries.keys:
    if entryPath.startsWith("Index/Slide") or
        entryPath.startsWith("Index/MasterSlide"):
      return dkKeynote
  if "Index/CalculationEngine.iwa" in entries:
    return dkNumbers
  dkPages

proc detectDocKind(path: string, entries: OrderedTable[string, string]): DocKind =
  case path.splitFile.ext.toLowerAscii
  of ".key": dkKeynote
  of ".pages": dkPages
  of ".numbers": dkNumbers
  else: sniffDocKind(entries)

proc openContainer*(path: string): IworkContainer =
  ## opens a keynote, pages, or numbers document (zip or directory bundle)
  if not fileExists(path) and not dirExists(path):
    raise newException(IworkContainerError, "no such document: " & path)
  result = IworkContainer(path: path)
  var layout: string
  if dirExists(path):
    result.kind = ckBundle
    result.entries = loadBundle(path)
    layout = "directory bundle"
  else:
    result.kind = ckZip
    result.entries = loadZip(path)
    layout = "zip"
  if "Index.zip" in result.entries:
    explodeNestedIndex(result.entries)
    layout &= " with nested Index.zip"
  checkLegacy(result.entries, path)
  result.docKind = detectDocKind(path, result.entries)
  debug "opened ", path, ": kind=", result.kind, " docKind=", result.docKind,
    " entries=", result.entries.len, " layout=", layout

proc readEntry*(c: IworkContainer, path: string): string =
  ## returns the raw bytes of an entry, or raises IworkContainerError if missing
  if path notin c.entries:
    raise newException(IworkContainerError, "no entry " & path & " in " & c.path)
  c.entries[path]

proc iwaEntries*(c: IworkContainer): seq[string] =
  ## paths of all .iwa entries in the container
  for entryPath in c.entries.keys:
    if entryPath.endsWith(".iwa"):
      result.add(entryPath)

proc metadataPlist*(c: IworkContainer): string =
  ## raw bytes of Metadata/Properties.plist, or "" if the entry is absent
  c.entries.getOrDefault(metadataPlistPath, "")
