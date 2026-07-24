# Package

version       = "0.1.0" # x-release-please-version
author        = "Alfred Chiesa"
description   = "Pure Nim reader for Apple Keynote, Pages, and Numbers documents"
license       = "MIT"
srcDir        = "src"

# Dependencies

requires "nim >= 2.0.0"
requires "zippy >= 0.10.0"
requires "supersnappy >= 2.1.0"

# docs: https://alfredchiesa.github.io/nim-iwork/

task docs, "generate html docs into htmldocs/":
  exec "nim doc --project --index:on --outdir:htmldocs " &
    "--git.url:https://github.com/alfredchiesa/nim-iwork " &
    "--git.commit:main src/iwork.nim"
  # pages serves index.html at the site root
  cpFile("htmldocs/iwork.html", "htmldocs/index.html")
