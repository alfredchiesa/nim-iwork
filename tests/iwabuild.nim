# tiny builders for synthetic iwork documents: hand-rolled protobuf,
# iwa object records, snappy chunks, and a directory bundle to hold them.
# not a test module itself (no leading t), the t*.nim files import it
import std/os
import supersnappy

proc varint*(v: uint64): string =
  var v = v
  while v >= 0x80:
    result.add(char((v and 0x7f) or 0x80))
    v = v shr 7
  result.add(char(v))

proc pbUint*(field: int, v: uint64): string =
  ## a varint field
  varint(uint64(field shl 3)) & varint(v)

proc pbBytes*(field: int, s: string): string =
  ## a length-delimited field (bytes, string, or nested message)
  varint(uint64(field shl 3 or 2)) & varint(uint64(s.len)) & s

proc pbRef*(field: int, id: uint64): string =
  ## a tsp.reference to object `id`
  pbBytes(field, pbUint(1, id))

proc iwaObject*(id: uint64, msgType: uint32, payload: string): string =
  ## one [varint len][archiveinfo][payload] record
  let info = pbUint(1, id) &
    pbBytes(2, pbUint(1, msgType) & pbUint(3, uint64(payload.len)))
  varint(uint64(info.len)) & info & payload

proc iwaChunk*(stream: string): string =
  ## wraps a decompressed stream as a single snappy chunk
  let packed = compress(stream)
  "\x00" & char(packed.len and 0xff) & char((packed.len shr 8) and 0xff) &
    char((packed.len shr 16) and 0xff) & packed

proc writeBundle*(dir, stream: string) =
  ## writes `stream` as the bundle's Index/Document.iwa
  createDir(dir / "Index")
  writeFile(dir / "Index" / "Document.iwa", iwaChunk(stream))
