# prints an iwork document's text, in reading order, to stdout
import std/os
import iwork

when isMainModule:
  if paramCount() != 1:
    stderr.writeLine("usage: extract_text <document>")
    quit(1)
  try:
    echo openDocument(paramStr(1)).getText()
  except IworkError as e:
    stderr.writeLine("extract_text: " & e.msg)
    quit(1)
