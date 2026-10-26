# registry type numbers for the archive messages later phases care about.
# heads up: type ids are per-application - the same number means different
# things in keynote, pages, and numbers. sourced from the obriensp proto
# dumps and the keynote-parser / numbers-parser projects.

const
  # keynote (kn)
  knDocumentArchive* = 1'u32    ## kn.documentarchive, the root object
  knShowArchive* = 2'u32        ## kn.showarchive, deck-level info
  knSlideNodeArchive* = 4'u32   ## kn.slidenodearchive, slide tree node
  knSlideArchive* = 5'u32       ## kn.slidearchive, one slide's content
  knPlaceholderArchive* = 7'u32 ## kn.placeholderarchive, title/body placeholder
                                ## (source: keynote-parser proto mapping)
  knNoteArchive* = 15'u32       ## kn.notearchive, presenter notes
                                ## (source: keynote-parser proto mapping)

  # pages (tp)
  tpDocumentArchive* = 10000'u32 ## tp.documentarchive, the root object
  tpSectionArchive* = 10011'u32  ## tp.sectionarchive, one document section
                                 ## (verified against the pages templates)
  tpHeadersFootersArchive* = 10143'u32 ## a section's header (field 1) and
                                       ## footer (field 2) storages, three
                                       ## slots each: left, center, right
                                       ## (verified against the pages templates)
  tpFloatingDrawablesArchive* = 10010'u32 ## drawables floating on pages,
                                          ## grouped by page
                                          ## (verified against real documents)

  # numbers (tn)
  tnDocumentArchive* = 1'u32    ## tn.documentarchive, the root object
  tnSheetArchive* = 2'u32       ## tn.sheetarchive, one sheet

  # shared text engine (tswp), same ids across all three apps
  tswpStorageArchive* = 2001'u32 ## tswp.storagearchive, a text storage
  tswpShapeInfoArchive* = 2011'u32 ## tswp.shapeinfoarchive, a text shape
                                   ## (source: keynote-parser proto mapping)

  # shared drawing layer (tsd), same ids across all three apps
  tsdGroupArchive* = 3008'u32 ## tsd.grouparchive, grouped drawables
                              ## (verified against real documents)

  # shared table engine (tst), same ids across all three apps
  tstTableInfoArchive* = 6000'u32  ## tst.tableinfoarchive, table drawable
  tstTableModelArchive* = 6001'u32 ## tst.tablemodelarchive, table structure
  tstTileArchive* = 6002'u32       ## tst.tile, a tile of cell storage
  tstTableDataList* = 6005'u32     ## tst.tabledatalist, shared value lists
  tstRichTextPayloadArchive* = 6218'u32 ## tst.richtextpayloadarchive, one
                                        ## rich text cell's storage
                                        ## (verified against real documents)
