# tests for the iwa snappy chunk decoder
import std/[os, unittest]
import supersnappy
import iwork

const fixtures = currentSourcePath().parentDir / "fixtures"

proc chunk(payload: string): string =
  # 1 byte type (0x00) + 3-byte le length + raw snappy block
  let compressed = compress(payload)
  result.add('\0')
  result.add(char(compressed.len and 0xff))
  result.add(char((compressed.len shr 8) and 0xff))
  result.add(char((compressed.len shr 16) and 0xff))
  result.add(compressed)

suite "snappychunks: decoding":
  test "single synthetic chunk round trips":
    let payload = "the quick brown fox jumps over the lazy dog, twice over"
    check decodeIwa(chunk(payload)) == payload

  test "multiple chunks concatenate into one stream":
    check decodeIwa(chunk("first half / ") & chunk("second half")) ==
      "first half / second half"

  test "empty input decodes to empty stream":
    check decodeIwa("") == ""

suite "snappychunks: integration with container layer":
  test "simple.key Index/Document.iwa decodes":
    let c = openContainer(fixtures / "simple.key")
    let raw = c.readEntry("Index/Document.iwa")
    let decoded = decodeIwa(raw)
    check decoded.len > 0
    check decoded.len > raw.len

suite "snappychunks: malformed input":
  test "bad chunk type byte raises IworkFormatError":
    var bad = chunk("payload")
    bad[0] = '\x01'
    expect IworkFormatError:
      discard decodeIwa(bad)

  test "truncated header raises IworkFormatError":
    expect IworkFormatError:
      discard decodeIwa("\x00\x05")

  test "truncated payload raises IworkFormatError":
    # header claims 200 bytes but only a few follow
    let bad = "\x00" & char(200) & "\x00\x00" & "short"
    expect IworkFormatError:
      discard decodeIwa(bad)

  test "garbage payload raises IworkFormatError":
    # right length, but not a valid snappy block
    let junk = "\xff\xff\xff\xff\xff\xff\xff\xff"
    let bad = "\x00" & char(junk.len) & "\x00\x00" & junk
    expect IworkFormatError:
      discard decodeIwa(bad)
