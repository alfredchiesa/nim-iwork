# decoding the modern (v5) numbers cell storage record: a small binary
# format that lives inside the tile protobufs, not protobuf itself.
# layout per cell (verified against real documents, with masaccio's
# numbers-parser as the reference implementation):
#   byte 0        storage version (5)
#   byte 1        cell type
#   bytes 2-3     reserved
#   bytes 4-7     extra flags (unused here)
#   bytes 8-11    flags, little-endian uint32
#   bytes 12...   one fixed-size field per set flag bit, ascending bit order

import std/[logging, math, tables, times]

type
  CellKind* = enum
    ckEmpty    ## no value in the cell
    ckText     ## plain text
    ckNumber   ## numeric value as float64
    ckBool     ## boolean
    ckDate     ## calendar date/time
    ckDuration ## time span in seconds
    ckFormula  ## formula cell (display text or a marker)
    ckError    ## cell that failed to decode or holds an error

  CellValue* = object
    ## one decoded table cell
    case kind*: CellKind
    of ckEmpty: discard
    of ckText: text*: string
    of ckNumber: number*: float64
    of ckBool: boolean*: bool
    of ckDate: date*: DateTime
    of ckDuration: durationSeconds*: float64
    of ckFormula: formula*: string
    of ckError: error*: string

const
  # cell type bytes (numbers-parser cell_storage.py)
  ctEmpty = 0
  ctNumberD128 = 2  # number stored as ieee decimal128
  ctText = 3
  ctDate = 5
  ctBool = 6
  ctDuration = 7
  ctError = 8
  ctRichText = 9
  ctNumberDouble = 10 # number stored as plain double

  # flag bits, ascending order = field order in the record.
  # each present field has a fixed size; we skip the ones we don't use
  fD128 = 0        # 16 bytes, decimal128 number (currency and plain numbers)
  fDouble = 1      # 8 bytes, double value (numbers, durations, bools)
  fDatetime = 2    # 8 bytes, double seconds since 2001-01-01
  fStringId = 3    # 4 bytes, key into the table's shared string list
  fRichId = 4      # 4 bytes, key into the rich text payload list
  fFormulaId = 9   # 4 bytes, key into the formula list
  fFormulaErrorId = 11 # 4 bytes, formula error id
  # bits 5-8, 10, 12-20 are style/format/comment ids, all 4 bytes each

func fieldSize(bit: int): int =
  # everything is 4 bytes except the three value fields up front
  case bit
  of fD128: 16
  of fDouble, fDatetime: 8
  else: 4

func readUint32(buf: string, at: int): uint32 =
  for i in 0 ..< 4:
    result = result or (uint32(buf[at + i].ord) shl (i * 8))

func readDouble(buf: string, at: int): float64 =
  var bits: uint64
  for i in 0 ..< 8:
    bits = bits or (uint64(buf[at + i].ord) shl (i * 8))
  cast[float64](bits)

func readD128(buf: string, at: int): float64 =
  # ieee 754 decimal128, little endian: sign and a 14-bit biased exponent
  # live in the top two bytes, the coefficient in the rest. numbers only
  # ever writes small coefficients, so a float64 result is fine here
  let exponent = (((buf[at + 15].ord and 0x7f) shl 7) or
    (buf[at + 14].ord shr 1)) - 0x1820
  var coefficient = 0.0
  for i in countdown(13, 0):
    coefficient = coefficient * 256 + float64(buf[at + i].ord)
  if (buf[at + 14].ord and 1) == 1:
    coefficient += 1.208925819614629e24 # 2^80 carried out of the low bytes
  result = coefficient * pow(10.0, float64(exponent))
  if (buf[at + 15].ord and 0x80) != 0:
    result = -result

# the apple epoch: dates are stored as seconds since 2001-01-01 utc
let appleEpoch = dateTime(2001, mJan, 1, zone = utc())

proc decodeCellAt*(buf: string, offset: int,
    strings: Table[uint32, string]): CellValue =
  ## decodes one v5 cell record at a byte offset; anything unexpected
  ## logs at debug level and comes back as an error/empty value instead
  ## of raising, so one weird cell never kills the document
  if offset + 12 > buf.len:
    debug "cell record truncated at offset ", offset
    return CellValue(kind: ckError, error: "truncated cell record")
  let version = buf[offset].ord
  let cellType = buf[offset + 1].ord
  if version != 5:
    debug "unsupported cell storage version ", version, " at offset ", offset
    return CellValue(kind: ckError, error: "cell storage v" & $version)
  let flags = readUint32(buf, offset + 8)

  # walk the flag bits in order, remembering where each value field sits
  var pos = offset + 12
  var d128 = 0.0
  var dbl = 0.0
  var datetime = 0.0
  var stringId = 0'u32
  var hasFormula = false
  var hasD128, hasDouble, hasString = false
  for bit in 0 ..< 21:
    if (flags and (1'u32 shl bit)) == 0:
      continue
    let size = fieldSize(bit)
    if pos + size > buf.len:
      debug "cell field for bit ", bit, " truncated at offset ", pos
      return CellValue(kind: ckError, error: "truncated cell field")
    case bit
    of fD128:
      d128 = readD128(buf, pos)
      hasD128 = true
    of fDouble:
      dbl = readDouble(buf, pos)
      hasDouble = true
    of fDatetime:
      datetime = readDouble(buf, pos)
    of fStringId:
      stringId = readUint32(buf, pos)
      hasString = true
    of fFormulaId:
      hasFormula = true
    else:
      discard # style/format/comment ids, not values
    pos += size

  case cellType
  of ctEmpty:
    CellValue(kind: ckEmpty)
  of ctNumberD128, ctNumberDouble:
    # currency cells (type 10) carry their value in the d128 field too,
    # so prefer whichever value field is actually present
    if hasD128:
      CellValue(kind: ckNumber, number: d128)
    elif hasDouble:
      CellValue(kind: ckNumber, number: dbl)
    elif hasFormula:
      CellValue(kind: ckFormula, formula: "=?")
    else:
      debug "number cell without value field at offset ", offset
      CellValue(kind: ckEmpty)
  of ctText:
    if hasString and stringId in strings:
      CellValue(kind: ckText, text: strings[stringId])
    elif hasFormula:
      # a text-valued formula whose cached string is elsewhere
      CellValue(kind: ckFormula, formula: "=?")
    else:
      debug "text cell without resolvable string id ", stringId
      CellValue(kind: ckError, error: "unresolved string " & $stringId)
  of ctDate:
    CellValue(kind: ckDate,
      date: appleEpoch + initDuration(
        milliseconds = int64(datetime * 1000)))
  of ctBool:
    CellValue(kind: ckBool, boolean: dbl != 0.0)
  of ctDuration:
    CellValue(kind: ckDuration, durationSeconds: dbl)
  of ctError:
    CellValue(kind: ckError, error: "#ERROR")
  of ctRichText:
    # rich text bodies live in their own payload list; we don't chase
    # them yet, so surface a marker rather than losing the cell
    CellValue(kind: ckText, text: "")
  else:
    debug "unknown cell type ", cellType, " at offset ", offset
    CellValue(kind: ckError, error: "unknown cell type " & $cellType)

proc cellOffsets*(offsets: string): seq[int] =
  ## unpacks the little-endian uint16 per-column offsets buffer;
  ## 0xffff means the column has no cell in this row
  for i in 0 ..< offsets.len div 2:
    let v = offsets[i * 2].ord or (offsets[i * 2 + 1].ord shl 8)
    result.add(if v == 0xffff: -1 else: v)

proc asString*(v: CellValue): string =
  ## human-readable form of a cell value, also used for csv output
  case v.kind
  of ckEmpty: ""
  of ckText: v.text
  of ckNumber:
    if v.number == v.number.int64.float64: $v.number.int64
    else: $v.number
  of ckBool: $v.boolean
  of ckDate: v.date.format("yyyy-MM-dd HH:mm:ss")
  of ckDuration: $v.durationSeconds & "s"
  of ckFormula: v.formula
  of ckError: v.error
