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

  ExtractionWarningKind* = enum
    ## why extracted text is known to be incomplete
    ewStructureError   ## the structured walk failed with IworkFormatError
    ewMissingReference ## an object the walk needed is absent or dangling

  ExtractionWarning* = object
    ## one known gap in a text extraction
    kind*: ExtractionWarningKind
    message*: string
