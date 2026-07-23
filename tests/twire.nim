# tests for the generic protobuf wire-format decoder,
# with all byte sequences hand-built right here
import std/[options, unittest]
import iwork

proc varint(n: uint64): string =
  # manual varint encoder so the tests owe nothing to the decoder
  var v = n
  while true:
    if v < 0x80:
      result.add(char(v))
      break
    result.add(char((v and 0x7f) or 0x80))
    v = v shr 7

proc fieldKey(field, wire: int): string =
  varint(uint64(field shl 3 or wire))

suite "wire: scalar fields":
  test "varint field decodes":
    let msg = decodeMessage(fieldKey(1, 0) & varint(150))
    check msg.getUint(1) == some(150'u64)

  test "multi-byte varint round trips":
    let msg = decodeMessage(fieldKey(1, 0) & varint(uint64.high))
    check msg.getUint(1) == some(uint64.high)

  test "fixed32 field reads as float":
    # 1.5'f32 is 0x3fc00000 little endian
    let msg = decodeMessage(fieldKey(2, 5) & "\x00\x00\xc0\x3f")
    check msg.getFloat(2) == some(1.5'f32)

  test "fixed64 field reads as double":
    # 1.5'f64 is 0x3ff8000000000000 little endian
    let msg = decodeMessage(fieldKey(3, 1) & "\x00\x00\x00\x00\x00\x00\xf8\x3f")
    check msg.getDouble(3) == some(1.5'f64)

  test "length-delimited field reads as string":
    let msg = decodeMessage(fieldKey(4, 2) & varint(7) & "testing")
    check msg.getString(4) == some("testing")

  test "negative int without zigzag":
    let msg = decodeMessage(fieldKey(1, 0) & varint(cast[uint64](-2'i64)))
    check msg.getInt(1) == some(-2'i64)

  test "zigzag int decodes when asked":
    # zigzag(-3) == 5
    let msg = decodeMessage(fieldKey(1, 0) & varint(5))
    check msg.getInt(1, zigzag = true) == some(-3'i64)
    check msg.getInt(1) == some(5'i64)

suite "wire: nested and repeated":
  test "nested message via getMessage":
    let inner = fieldKey(1, 0) & varint(42)
    let msg = decodeMessage(fieldKey(2, 2) & varint(inner.len.uint64) & inner)
    let nested = msg.getMessage(2)
    check nested.isSome
    check nested.get.getUint(1) == some(42'u64)

  test "repeated varint field collects all values":
    let msg = decodeMessage(
      fieldKey(5, 0) & varint(1) & fieldKey(5, 0) & varint(2) &
      fieldKey(5, 0) & varint(3))
    check msg.getRepeatedUint(5) == @[1'u64, 2, 3]

  test "repeated nested messages":
    let a = fieldKey(1, 0) & varint(10)
    let b = fieldKey(1, 0) & varint(20)
    let msg = decodeMessage(
      fieldKey(2, 2) & varint(a.len.uint64) & a &
      fieldKey(2, 2) & varint(b.len.uint64) & b)
    let nested = msg.getRepeatedMessage(2)
    check nested.len == 2
    check nested[0].getUint(1) == some(10'u64)
    check nested[1].getUint(1) == some(20'u64)

suite "wire: missing and mismatched fields":
  test "missing field returns none, never crashes":
    let msg = decodeMessage(fieldKey(1, 0) & varint(1))
    check msg.getUint(99).isNone
    check msg.getString(99).isNone
    check msg.getMessage(99).isNone
    check msg.getRepeatedUint(99).len == 0

  test "wrong wire kind reads as missing":
    # field 1 is a varint, so string/float getters see nothing
    let msg = decodeMessage(fieldKey(1, 0) & varint(1))
    check msg.getString(1).isNone
    check msg.getFloat(1).isNone

suite "wire: malformed input":
  test "truncated varint raises IworkFormatError":
    expect IworkFormatError:
      discard decodeMessage("\x80")

  test "truncated length-delimited payload raises":
    expect IworkFormatError:
      discard decodeMessage(fieldKey(1, 2) & varint(10) & "ab")

  test "truncated fixed32 raises":
    expect IworkFormatError:
      discard decodeMessage(fieldKey(1, 5) & "\x00\x00")

  test "truncated fixed64 raises":
    expect IworkFormatError:
      discard decodeMessage(fieldKey(1, 1) & "\x00\x00\x00\x00")

  test "unsupported wire type raises":
    # wire type 3 (group start) is not a thing in iwork archives
    expect IworkFormatError:
      discard decodeMessage(fieldKey(1, 3))

  test "field number zero raises":
    expect IworkFormatError:
      discard decodeMessage(varint(0) & varint(1))
