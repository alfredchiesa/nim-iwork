# plain text extraction: tswp.storagearchive objects carry the document
# text in field 3 as repeated string runs. we clean control placeholders
# out and return the storages in a stable order.

import std/[algorithm, strutils, tables]
import ./objects, ./typemaps, ./wire

func cleanRun(run: string): string =
  # placeholder characters spelled as utf-8 byte escapes so nothing
  # invisible hides in the source
  result = run
  # u+fffc object replacement character stands in for an inline
  # attachment (image, table, chart) - there's no text to keep, drop it
  result = result.replace("\xef\xbf\xbc", "")
  # u+fffb interlinear annotation terminator shows up around ruby text
  # and phonetic guides - also not real content
  result = result.replace("\xef\xbf\xbb", "")
  # u+2028 line separator is a soft line break inside a paragraph -
  # normalize to a plain newline
  result = result.replace("\xe2\x80\xa8", "\n")
  # u+2029 paragraph separator is a hard paragraph break - same deal
  result = result.replace("\xe2\x80\xa9", "\n")
  # old-school carriage returns also mean line breaks in tswp storages
  result = result.replace("\r\n", "\n")
  result = result.replace("\r", "\n")

proc extractText*(idx: ObjectIndex): seq[string] =
  ## cleaned text of every storage archive in the index, sorted by
  ## object id so output is deterministic
  # tswp type ids are shared across keynote, pages, and numbers,
  # so one storage archive type covers all three apps
  var ids: seq[uint64]
  for obj in idx.objects.values:
    if obj.msgType == tswpStorageArchive:
      ids.add(obj.id)
  ids.sort()
  for id in ids:
    # runs in field 3 are consecutive pieces of one text stream,
    # so they concatenate without separators
    let cleaned = cleanRun(idx.objects[id].message.getRepeatedString(3).join(""))
    if cleaned.strip.len > 0:
      result.add(cleaned)
