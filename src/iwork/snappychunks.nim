# decoding the .iwa chunk format: a sequence of chunks, each a 4-byte
# header (1 byte type, always 0x00, then a 3-byte le payload length)
# followed by a raw snappy block - no stream framing, no crc.

import std/[logging, strutils]
import supersnappy
import ./errors

export errors

proc decodeIwa*(data: string): string =
  ## walks all chunks in an .iwa byte string and returns the
  ## concatenated decompressed stream
  var
    offset = 0
    chunks = 0
  while offset < data.len:
    if offset + 4 > data.len:
      raise newException(IworkFormatError,
        "truncated chunk header at offset " & $offset & " (need 4 bytes, have " &
        $(data.len - offset) & ")")
    let chunkType = data[offset].ord
    if chunkType != 0x00:
      raise newException(IworkFormatError,
        "unexpected chunk type 0x" & chunkType.toHex(2) & " at offset " &
        $offset & " (expected 0x00)")
    let payloadLen = data[offset + 1].ord or
      (data[offset + 2].ord shl 8) or
      (data[offset + 3].ord shl 16)
    let payloadStart = offset + 4
    if payloadStart + payloadLen > data.len:
      raise newException(IworkFormatError,
        "truncated chunk payload at offset " & $payloadStart & " (need " &
        $payloadLen & " bytes, have " & $(data.len - payloadStart) & ")")
    try:
      result.add(uncompress(data[payloadStart ..< payloadStart + payloadLen]))
    except SnappyError as e:
      raise newException(IworkFormatError,
        "bad snappy block at offset " & $payloadStart & ": " & e.msg)
    offset = payloadStart + payloadLen
    inc chunks
  debug "decoded iwa: ", chunks, " chunks, ", data.len, " bytes compressed -> ",
    result.len, " bytes decompressed"
