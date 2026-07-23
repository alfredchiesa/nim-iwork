# minimal protobuf wire-format decoder. no proto files, no codegen:
# every message decodes into a generic field-number -> values tree and
# callers pull typed values out with the getters below.

import std/[options, tables]
import ./errors

export options

type
  WireKind* = enum
    wkVarint  ## wire type 0
    wkFixed64 ## wire type 1
    wkBytes   ## wire type 2 (length-delimited)
    wkFixed32 ## wire type 5

  WireValue* = object
    ## one decoded field occurrence
    case kind*: WireKind
    of wkVarint: varint*: uint64
    of wkFixed64: fixed64*: uint64
    of wkBytes: bytes*: string
    of wkFixed32: fixed32*: uint32

  WireMessage* = object
    ## a decoded message: field number to every occurrence of that field
    fields*: Table[int, seq[WireValue]]

proc readVarint*(data: string, offset: var int): uint64 =
  ## reads one varint starting at offset, advancing it past the bytes read
  var shift = 0
  while true:
    if offset >= data.len:
      raise newException(IworkFormatError,
        "truncated varint at offset " & $offset)
    if shift >= 64:
      raise newException(IworkFormatError,
        "varint longer than 10 bytes at offset " & $offset)
    let b = data[offset].ord
    inc offset
    result = result or (uint64(b and 0x7f) shl shift)
    if (b and 0x80) == 0:
      break
    shift += 7

proc decodeMessage*(data: string): WireMessage =
  ## decodes a whole message into the generic field tree,
  ## raising IworkFormatError on malformed wire data
  var offset = 0
  while offset < data.len:
    let keyOffset = offset
    let key = readVarint(data, offset)
    let field = int(key shr 3)
    let wire = int(key and 7)
    if field == 0:
      raise newException(IworkFormatError,
        "field number 0 at offset " & $keyOffset)
    var value: WireValue
    case wire
    of 0:
      value = WireValue(kind: wkVarint, varint: readVarint(data, offset))
    of 1:
      if offset + 8 > data.len:
        raise newException(IworkFormatError,
          "truncated fixed64 at offset " & $offset)
      var v: uint64
      for i in 0 ..< 8:
        v = v or (uint64(data[offset + i].ord) shl (i * 8))
      value = WireValue(kind: wkFixed64, fixed64: v)
      offset += 8
    of 2:
      let payloadLen = readVarint(data, offset)
      if payloadLen > uint64(data.len) or
          offset + int(payloadLen) > data.len:
        raise newException(IworkFormatError,
          "truncated length-delimited field at offset " & $offset &
          " (need " & $payloadLen & " bytes, have " & $(data.len - offset) & ")")
      value = WireValue(kind: wkBytes,
        bytes: data[offset ..< offset + int(payloadLen)])
      offset += int(payloadLen)
    of 5:
      if offset + 4 > data.len:
        raise newException(IworkFormatError,
          "truncated fixed32 at offset " & $offset)
      var v: uint32
      for i in 0 ..< 4:
        v = v or (uint32(data[offset + i].ord) shl (i * 8))
      value = WireValue(kind: wkFixed32, fixed32: v)
      offset += 4
    else:
      raise newException(IworkFormatError,
        "unsupported wire type " & $wire & " at offset " & $keyOffset)
    result.fields.mgetOrPut(field, @[]).add(value)

func firstOfKind(msg: WireMessage, field: int, kind: WireKind): Option[WireValue] =
  # wrong-kind occurrences are treated as missing, never a crash
  for value in msg.fields.getOrDefault(field, @[]):
    if value.kind == kind:
      return some(value)

func getUint*(msg: WireMessage, field: int): Option[uint64] =
  ## first varint occurrence of a field as unsigned
  let v = msg.firstOfKind(field, wkVarint)
  if v.isSome: some(v.get.varint) else: none(uint64)

func getInt*(msg: WireMessage, field: int, zigzag = false): Option[int64] =
  ## first varint occurrence as signed, zigzag-decoded when asked
  let v = msg.getUint(field)
  if v.isNone:
    none(int64)
  elif zigzag:
    some(int64(v.get shr 1) xor -int64(v.get and 1))
  else:
    some(cast[int64](v.get))

func getFloat*(msg: WireMessage, field: int): Option[float32] =
  ## first fixed32 occurrence as float32
  let v = msg.firstOfKind(field, wkFixed32)
  if v.isSome: some(cast[float32](v.get.fixed32)) else: none(float32)

func getDouble*(msg: WireMessage, field: int): Option[float64] =
  ## first fixed64 occurrence as float64
  let v = msg.firstOfKind(field, wkFixed64)
  if v.isSome: some(cast[float64](v.get.fixed64)) else: none(float64)

func getString*(msg: WireMessage, field: int): Option[string] =
  ## first length-delimited occurrence as raw bytes/string
  let v = msg.firstOfKind(field, wkBytes)
  if v.isSome: some(v.get.bytes) else: none(string)

proc getMessage*(msg: WireMessage, field: int): Option[WireMessage] =
  ## lazily decodes the first length-delimited occurrence as a nested message
  let v = msg.getString(field)
  if v.isSome: some(decodeMessage(v.get)) else: none(WireMessage)

func getRepeatedUint*(msg: WireMessage, field: int): seq[uint64] =
  ## every varint occurrence of a field
  for value in msg.fields.getOrDefault(field, @[]):
    if value.kind == wkVarint:
      result.add(value.varint)

func getRepeatedInt*(msg: WireMessage, field: int, zigzag = false): seq[int64] =
  ## every varint occurrence as signed
  for v in msg.getRepeatedUint(field):
    if zigzag:
      result.add(int64(v shr 1) xor -int64(v and 1))
    else:
      result.add(cast[int64](v))

func getRepeatedFloat*(msg: WireMessage, field: int): seq[float32] =
  ## every fixed32 occurrence as float32
  for value in msg.fields.getOrDefault(field, @[]):
    if value.kind == wkFixed32:
      result.add(cast[float32](value.fixed32))

func getRepeatedDouble*(msg: WireMessage, field: int): seq[float64] =
  ## every fixed64 occurrence as float64
  for value in msg.fields.getOrDefault(field, @[]):
    if value.kind == wkFixed64:
      result.add(cast[float64](value.fixed64))

func getRepeatedString*(msg: WireMessage, field: int): seq[string] =
  ## every length-delimited occurrence as raw bytes/string
  for value in msg.fields.getOrDefault(field, @[]):
    if value.kind == wkBytes:
      result.add(value.bytes)

proc getRepeatedMessage*(msg: WireMessage, field: int): seq[WireMessage] =
  ## every length-delimited occurrence decoded as a nested message
  for value in msg.getRepeatedString(field):
    result.add(decodeMessage(value))
