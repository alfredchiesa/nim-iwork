# prints an iwork document's plain text to stdout
import std/os
import iwork

when isMainModule:
  if paramCount() != 1:
    stderr.writeLine("usage: extract_text <document>")
    quit(1)
  try:
    echo openDocument(paramStr(1)).plainText()
  except IworkError as e:
    stderr.writeLine("extract_text: " & e.msg)
    quit(1)
