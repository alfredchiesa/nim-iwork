-- builds grouped-tables.key (made with keynote 14.5 on macos 15.7):
-- slide 1 has a table, slide 2 is skipped, slide 3 has a group nested
-- in a group. grouping goes through the arrange menu, so the terminal
-- needs accessibility access. run: osascript <this> /abs/path/out.key

on clickCanvas()
  tell application "System Events" to tell process "Keynote"
    set {wx, wy} to position of window 1
    set {ww, wh} to size of window 1
    click at {wx + (ww * 0.55), wy + (wh * 0.85)}
  end tell
  delay 0.5
end clickCanvas

on groupAll()
  my clickCanvas()
  tell application "System Events" to tell process "Keynote"
    keystroke "a" using command down
    delay 0.5
    click menu item "Group" of menu "Arrange" of menu bar 1
  end tell
  delay 0.5
end groupAll

on run argv
  set outPath to item 1 of argv
  tell application "Keynote"
    activate
    set doc to make new document with properties {document theme:theme "White"}
    tell doc
      set s1 to slide 1
      set base slide of s1 to master slide "Title & Bullets"
      tell s1
        set object text of default title item to "Quarterly numbers"
        set object text of default body item to "Sales by region"
        set presenter notes to "Mention the north"
        set t to make new table with properties {row count:3, column count:3, header row count:1, header column count:0, footer row count:0, name:"Sales"}
        tell t
          set value of cell "A1" to "Region"
          set value of cell "B1" to "Q1"
          set value of cell "C1" to "Q2"
          set value of cell "A2" to "North"
          set value of cell "B2" to "10"
          set value of cell "C2" to "12"
          set value of cell "A3" to "South"
          set value of cell "B3" to "7"
          set value of cell "C3" to "9"
        end tell
      end tell
      set s2 to make new slide with properties {base slide:master slide "Title & Bullets"}
      tell s2
        set object text of default title item to "Hidden slide"
        set object text of default body item to "Only in the skipped slide"
        set presenter notes to "Skipped slide note"
        set skipped to true
      end tell
      set s3 to make new slide with properties {base slide:master slide "Blank"}
      tell s3
        make new text item with properties {object text:"Group alpha", position:{100, 100}}
        make new text item with properties {object text:"Group beta", position:{100, 250}}
        set presenter notes to "Grouped slide note"
      end tell
      set current slide to s3
    end tell
  end tell
  delay 1
  my groupAll()
  tell application "Keynote"
    tell slide 3 of doc
      make new text item with properties {object text:"Outer gamma", position:{100, 400}}
    end tell
  end tell
  delay 2
  tell application "System Events" to key code 53
  delay 1
  my groupAll()
  delay 1
  tell application "Keynote"
    tell doc
      set s4 to make new slide with properties {base slide:master slide "Title & Bullets"}
      tell s4
        set object text of default title item to "Closing"
        set object text of default body item to "Thanks"
      end tell
    end tell
    save doc in POSIX file outPath
    close doc saving no
  end tell
end run
