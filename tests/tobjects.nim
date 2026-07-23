# tests for the iwork object index and reference resolution,
# run against the real fixture documents
import std/[options, os, tables, unittest]
import iwork

const fixtures = currentSourcePath().parentDir / "fixtures"

suite "objects: building the index":
  test "every simple fixture yields a non-empty index":
    for name in ["simple.key", "simple.pages", "simple.numbers"]:
      let idx = buildIndex(openContainer(fixtures / name))
      check idx.objects.len > 0

  test "object id 1 exists and comes from Index/Document.iwa":
    for name in ["simple.key", "simple.pages", "simple.numbers"]:
      let idx = buildIndex(openContainer(fixtures / name))
      check 1'u64 in idx.objects
      check idx.objects[1'u64].entry == "Index/Document.iwa"

  test "objects expose type and decodable message":
    let idx = buildIndex(openContainer(fixtures / "simple.key"))
    let root = idx.objects[1'u64]
    check root.msgType > 0'u32
    check root.raw.len > 0
    check root.message.fields.len > 0

suite "objects: reference resolution":
  test "deref follows at least one real reference chain":
    let idx = buildIndex(openContainer(fixtures / "simple.key"))
    # walk real objects until we find a field holding a tsp.reference
    # (nested message whose field 1 is an id present in the index)
    var resolved = 0
    for obj in idx.objects.values:
      let msg =
        try:
          obj.message
        except IworkFormatError:
          continue
      for field in msg.fields.keys:
        let target = idx.deref(msg, field)
        if target.isSome:
          check target.get.id in idx.objects
          inc resolved
    check resolved > 0

  test "derefAll resolves repeated references":
    let idx = buildIndex(openContainer(fixtures / "simple.key"))
    var best = 0
    for obj in idx.objects.values:
      let msg =
        try:
          obj.message
        except IworkFormatError:
          continue
      for field in msg.fields.keys:
        best = max(best, idx.derefAll(msg, field).len)
    # a keynote deck always has some repeated reference list (slides etc)
    check best >= 2

  test "deref on a non-reference field returns none":
    let idx = buildIndex(openContainer(fixtures / "simple.key"))
    let root = idx.objects[1'u64]
    check idx.deref(root.message, 9999).isNone
