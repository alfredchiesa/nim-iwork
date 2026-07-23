# shared error hierarchy for the iwork package

type
  IworkError* = object of CatchableError
    ## base for everything this package raises

  IworkContainerError* = object of IworkError
    ## opening or reading a document container went wrong

  IworkFormatError* = object of IworkError
    ## the document content didn't parse the way we expected

  IworkUnsupportedError* = object of IworkError
    ## valid document, but a format we don't handle (e.g. pre-2013)
