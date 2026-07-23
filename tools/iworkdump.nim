# tiny debug cli for poking at iwork containers:
#   iworkdump ls <doc>            list iwa entries with sizes
#   iworkdump cat <doc> <entry>   write the decompressed stream to stdout
import std/[parseopt, strutils]
import iwork

proc usage(): string =
  """iworkdump - inspect iwork 2013+ documents

usage:
  iworkdump ls <doc>            list iwa entries with compressed/decompressed sizes
  iworkdump cat <doc> <entry>   write an entry's decompressed stream to stdout"""

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
    else:
      echo usage()
      quit(1)
  except IworkError as e:
    stderr.writeLine("iworkdump: " & e.msg)
    quit(1)
