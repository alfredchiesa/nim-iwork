-- builds inline-tables.pages (made with pages 14.5 on macos 15.7): a
-- table inline in the body after multibyte text, plus a floating table.
-- the inline insert uses the insert menu, so the terminal needs
-- accessibility access. run: osascript <this> /abs/path/out.pages

on run argv
  set outPath to item 1 of argv
  tell application "Pages"
    activate
    set doc to make new document with properties {document template:template "Blank"}
    set body text of doc to "Ünïcödé façade naïve café 🙂🙂🙂🙂🙂🙂🙂🙂🙂🙂🙂🙂" & return & "Second paragraph 🙂🙂🙂🙂🙂🙂🙂🙂" & return & return & "Closing paragraph after the table."
  end tell
  delay 1
  tell application "System Events" to tell process "Pages"
    set {wx, wy} to position of window 1
    set {ww, wh} to size of window 1
    click at {wx + (ww * 0.45), wy + (wh * 0.6)}
    delay 0.5
    key code 125 using command down -- cmd+down, end of document
    delay 0.3
    key code 126 -- up, onto the empty paragraph
    delay 0.3
    click menu item "Basic" of menu 1 of menu item "Table" of menu "Insert" of menu bar 1
  end tell
  delay 1
  tell application "Pages"
    tell doc
      set n to count of tables
      set t to table 1
      set column count of t to 2
      set row count of t to 3
      set header row count of t to 1
      set header column count of t to 0
      set footer row count of t to 0
      set name of t to "Inventory"
      tell t
        set value of cell "A1" to "Part"
        set value of cell "B1" to "Count"
        set value of cell "A2" to "Bolt"
        set value of cell "B2" to "40"
        set value of cell "A3" to "Nut"
        set value of cell "B3" to "55"
      end tell
      tell page 1 to set f to make new table with properties {row count:2, column count:2, header row count:1, header column count:0, footer row count:0}
      set name of f to "Prices"
      tell f
        set value of cell "A1" to "Item"
        set value of cell "B1" to "Price"
        set value of cell "A2" to "Widget"
        set value of cell "B2" to "5"
      end tell
    end tell
    save doc in POSIX file outPath
    close doc saving no
    return n
  end tell
end run
