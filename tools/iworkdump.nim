# tiny debug cli for poking at iwork containers:
#   iworkdump ls <doc>            list iwa entries with sizes
#   iworkdump cat <doc> <entry>   write the decompressed stream to stdout
#   iworkdump objects <doc>       list every object's id, type, and fields
#   iworkdump obj <doc> <id>      pretty-print one object's field tree as json
import std/[algorithm, json, parseopt, strutils, tables]
import iwork

proc usage(): string =
  """iworkdump - inspect iwork 2013+ documents

usage:
  iworkdump ls <doc>            list iwa entries with compressed/decompressed sizes
  iworkdump cat <doc> <entry>   write an entry's decompressed stream to stdout
  iworkdump objects <doc>       list id, type, and top-level fields per object
  iworkdump obj <doc> <id>      pretty-print one object's field tree as json"""

proc cmdLs(docPath: string) =
  let c = openContainer(docPath)
  echo "kind: ", c.kind, ", docKind: ", c.docKind
  echo alignLeft("entry", 40), align("compressed", 12), align("decompressed", 14)
  for entry in c.iwaEntries:
    let raw = c.readEntry(entry)
    let decodedSize =
      try:
        $decodeIwa(raw).len
      except IworkFormatError:
        "(bad chunks)"
    echo alignLeft(entry, 40), align($raw.len, 12), align(decodedSize, 14)

proc cmdCat(docPath, entry: string) =
  stdout.write(decodeIwa(openContainer(docPath).readEntry(entry)))

proc cmdObjects(docPath: string) =
  let idx = buildIndex(openContainer(docPath))
  echo alignLeft("id", 12), align("type", 8), "  fields"
  var ids: seq[uint64]
  for id in idx.objects.keys:
    ids.add(id)
  ids.sort()
  for id in ids:
    let obj = idx.objects[id]
    var fields: seq[int]
    try:
      for field in obj.message.fields.keys:
        fields.add(field)
      fields.sort()
    except IworkFormatError:
      discard
    echo alignLeft($id, 12), align($obj.msgType, 8), "  ", fields.join(", ")

proc isPrintable(s: string): bool =
  if s.len == 0:
    return false
  for c in s:
    if c.ord < 0x20 and c notin {'\t', '\n', '\r'}:
      return false
  true

proc toJson(msg: WireMessage, depth: int): JsonNode =
  # nested bytes fields get decoded as messages when they parse,
  # shown as text when printable, hex preview otherwise
  result = newJObject()
  var fields: seq[int]
  for field in msg.fields.keys:
    fields.add(field)
  fields.sort()
  for field in fields:
    var values = newJArray()
    for value in msg.fields[field]:
      case value.kind
      of wkVarint:
        values.add(%value.varint)
      of wkFixed32:
        values.add(%*{"fixed32": value.fixed32, "float": cast[float32](value.fixed32)})
      of wkFixed64:
        values.add(%*{"fixed64": value.fixed64, "double": cast[float64](value.fixed64)})
      of wkBytes:
        if depth < 6:
          try:
            values.add(toJson(decodeMessage(value.bytes), depth + 1))
            continue
          except IworkFormatError:
            discard
        if value.bytes.isPrintable:
          values.add(%value.bytes)
        else:
          let preview = value.bytes[0 ..< min(value.bytes.len, 24)]
          values.add(%("0x" & preview.toHex.toLowerAscii &
            (if value.bytes.len > 24: "... (" & $value.bytes.len & " bytes)" else: "")))
    result[$field] = values

proc cmdObj(docPath, idArg: string) =
  let idx = buildIndex(openContainer(docPath))
  let id = uint64(parseBiggestUInt(idArg))
  if id notin idx.objects:
    stderr.writeLine("iworkdump: no object with id " & idArg)
    quit(1)
  let obj = idx.objects[id]
  echo pretty(%*{
    "id": obj.id,
    "type": obj.msgType,
    "entry": obj.entry,
    "fields": toJson(obj.message, 0)})

when isMainModule:
  var args: seq[string]
  var p = initOptParser()
  for kind, key, _ in p.getopt():
    if kind == cmdArgument:
      args.add(key)

  try:
    if args.len == 2 and args[0] == "ls":
      cmdLs(args[1])
    elif args.len == 3 and args[0] == "cat":
      cmdCat(args[1], args[2])
    elif args.len == 2 and args[0] == "objects":
      cmdObjects(args[1])
    elif args.len == 3 and args[0] == "obj":
      cmdObj(args[1], args[2])
    else:
      echo usage()
      quit(1)
  except IworkError as e:
    stderr.writeLine("iworkdump: " & e.msg)
    quit(1)
