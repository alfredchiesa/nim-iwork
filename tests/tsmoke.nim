# trivial smoke test: the package imports and the error hierarchy is sane
import std/unittest
import iwork

suite "smoke":
  test "package imports and error types exist":
    check IworkContainerError is IworkError
    check IworkFormatError is IworkError
    check IworkUnsupportedError is IworkError
    check IworkError is CatchableError
