# the iwork object layer: a decompressed iwa stream is a sequence of
# [varint length][tsp.archiveinfo][payloads...], where archiveinfo carries
# the object identifier (field 1) and one messageinfo (field 2) per payload
# describing its registry type (field 1) and byte length (field 3).

import std/[logging, options, tables]
import ./container, ./errors, ./snappychunks, ./wire

type
  IworkObject* = ref object
    ## one archived object from an iwa stream
    id*: uint64       ## tsp identifier, unique across the document
    msgType*: uint32  ## per-application registry type number
    raw*: string      ## undecoded payload bytes
    entry*: string    ## container entry the object came from
    decodedMsg: Option[WireMessage]

  ObjectIndex* = object
    ## every object in a document, keyed by identifier
    objects*: Table[uint64, IworkObject]

proc message*(obj: IworkObject): WireMessage =
  ## the object's payload decoded as a generic wire message,
  ## decoded on first access and cached
  if obj.decodedMsg.isNone:
    obj.decodedMsg = some(decodeMessage(obj.raw))
  obj.decodedMsg.get

proc parseIwaStream(stream, entry: string,
    into: var Table[uint64, IworkObject]) =
  var offset = 0
  while offset < stream.len:
    let infoLen = int(readVarint(stream, offset))
    if offset + infoLen > stream.len:
      raise newException(IworkFormatError,
        "truncated archiveinfo in " & entry & " at offset " & $offset &
        " (need " & $infoLen & " bytes, have " & $(stream.len - offset) & ")")
    let info = decodeMessage(stream[offset ..< offset + infoLen])
    offset += infoLen
    let id = info.getUint(1)
    var isFirst = true
    for msgInfo in info.getRepeatedMessage(2):
      let payloadLen = int(msgInfo.getUint(3).get(0))
      if offset + payloadLen > stream.len:
        raise newException(IworkFormatError,
          "truncated object payload in " & entry & " at offset " & $offset &
          " (need " & $payloadLen & " bytes, have " &
          $(stream.len - offset) & ")")
      # the first messageinfo is the object itself; the rest are
      # auxiliary payloads we skip over but must still consume
      if isFirst and id.isSome:
        into[id.get] = IworkObject(
          id: id.get,
          msgType: uint32(msgInfo.getUint(1).get(0)),
          raw: stream[offset ..< offset + payloadLen],
          entry: entry)
      isFirst = false
      offset += payloadLen

proc buildIndex*(c: IworkContainer): ObjectIndex =
  ## parses every .iwa in the container into one id-keyed object table
  for entry in c.iwaEntries:
    parseIwaStream(decodeIwa(c.readEntry(entry)), entry, result.objects)
  debug "built object index: ", result.objects.len, " objects from ",
    c.iwaEntries.len, " iwa entries"

proc refTarget(msg: WireMessage, field: int): Option[uint64] =
  # a tsp.reference is a nested message whose field 1 is the target id;
  # anything that doesn't parse that way just resolves to none
  let refMsg =
    try:
      msg.getMessage(field)
    except IworkFormatError:
      none(WireMessage)
  if refMsg.isSome:
    result = refMsg.get.getUint(1)

proc deref*(idx: ObjectIndex, msg: WireMessage, field: int): Option[IworkObject] =
  ## resolves a tsp.reference held in a field into the target object,
  ## or none if the field is absent, malformed, or dangling
  let target = refTarget(msg, field)
  if target.isSome and target.get in idx.objects:
    result = some(idx.objects[target.get])

proc derefAll*(idx: ObjectIndex, msg: WireMessage, field: int): seq[IworkObject] =
  ## resolves every tsp.reference in a repeated field, skipping
  ## malformed or dangling ones
  let refMsgs =
    try:
      msg.getRepeatedMessage(field)
    except IworkFormatError:
      return
  for refMsg in refMsgs:
    let target = refMsg.getUint(1)
    if target.isSome and target.get in idx.objects:
      result.add(idx.objects[target.get])
