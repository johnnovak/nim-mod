import strutils


proc nibbleToChar(n: int): char =
  assert n >= 0 and n <= 15
  if n < 10:
    result = char(ord('0') + n)
  else:
    result = char(ord('A') + n - 10)


proc noteToStr(note: int): string =
  if note == NOTE_NONE:
   return "---"

  result = ""
  case note mod 12:
  of  0: result = "C-"
  of  1: result = "C#"
  of  2: result = "D-"
  of  3: result = "D#"
  of  4: result = "E-"
  of  5: result = "F-"
  of  6: result = "F#"
  of  7: result = "G-"
  of  8: result = "G#"
  of  9: result = "A-"
  of 10: result = "A#"
  of 11: result = "B-"
  else: discard
  result &= $(note div 12 + 1)


proc effectToStr(effect: int): string =
  let cmd = (effect and 0xf00) shr 8
  let x   = (effect and 0x0f0) shr 4
  let y   =  effect and 0x00f

  result = nibbleToChar(cmd) &
           nibbleToChar(x) &
           nibbleToChar(y)


proc `$`(m: Module): string =
  result =   "moduleType:  " & $m.moduleType &
           "\nnumChannels: " & $m.numChannels &
           "\nsongTitle:   " & $m.songTitle &
           "\nsongLength:  " & $m.songLength &
           "\nsongPositions:"

  for pos, pattNum in m.songPositions.pairs:
    result &= "\n  " & align($pos, 3) & " -> " & align($pattNum, 3)


proc `$`(c: Cell): string =
  let s1 = (c.sampleNum and 0xf0) shr 4
  let s2 =  c.sampleNum and 0x0f

  result = noteToStr(c.note) & " " &
           nibbleToChar(s1.int) & nibbleToChar(s2.int) & " " &
           effectToStr(c.effect.int)


proc `$`(p: Pattern): string =
  result = ""
  for row in 0..<ROWS_PER_PATTERN:
    result &= align($row, 2, '0') & " | "

    for track in p.tracks:
      result &= $track.rows[row] & " | "
    result &= "\n"


proc `$`(s: Sample): string =
  result =   "name:         " & $s.name &
           "\nlength:       " & $s.length &
           "\nfinetune:     " & $s.finetune &
           "\nvolume:       " & $s.volume &
           "\nrepeatOffset: " & $s.repeatOffset &
           "\nrepeatLength: " & $s.repeatLength


type GraphicsChars = object
  boxHoriz:     string
  boxHorizUp:   string
  boxHorizDown: string
  boxVert:      string
  boxVertLeft:  string
  boxVertRight: string
  boxVertHoriz: string
  boxDownLeft:  string
  boxDownRight: string
  boxUpRight:   string
  boxUpLeft:    string

let gfxCharsUnicode = GraphicsChars(
  boxHoriz:     "─",
  boxHorizUp:   "┴",
  boxHorizDown: "┬",
  boxVert:      "│",
  boxVertLeft:  "┤",
  boxVertRight: "├",
  boxVertHoriz: "┼",
  boxDownLeft:  "┐",
  boxDownRight: "┌",
  boxUpRight:   "└",
  boxUpLeft:    "┘"
)

let gfxCharsAscii = GraphicsChars(
  boxHoriz:     "-",
  boxHorizUp:   "+",
  boxHorizDown: "+",
  boxVert:      "|",
  boxVertLeft:  "+",
  boxVertRight: "+",
  boxVertHoriz: "+",
  boxDownLeft:  "+",
  boxDownRight: "+",
  boxUpRight:   "+",
  boxUpLeft:    "+"
)

# Global variable to hold the set of gfx chars to use
var gGfx: GraphicsChars


type TextColor = object
  fg: ForegroundColor
  hi: bool

type Theme = object
  rowNum:     TextColor
  rowNumHi:   TextColor
  note:       TextColor
  noteNone:   TextColor
  sample:     TextColor
  sampleNone: TextColor
  effect:     TextColor
  effectNone: TextColor
  border:     TextColor
  cursor:     TextColor
  cursorBg:   BackgroundColor

# Global variable to hold the current theme
var gTheme: Theme


template setColor(t: TextColor) =
  resetAttributes(stdout)
  setForegroundColor(stdout, t.fg)
  if t.hi:
    setStyle(stdout, {styleBright})
  else:
    setStyle(stdout, {styleDim})

template put(s: string) = stdout.write s


proc drawPatternViewBorder(numTracks: int, mid, sep, last: string) =
  const PATTERN_VIEW_ROWNUM_WIDTH = 5
  const PATTERN_VIEW_TRACK_WIDTH  = 12

  setColor gTheme.border
  put repeat(mid, PATTERN_VIEW_ROWNUM_WIDTH) & sep
  for trackNum in 0..<numTracks:
    put repeat(mid, PATTERN_VIEW_TRACK_WIDTH)
    if trackNum < numTracks-1:
      put sep
    else:
      put last
  put "\n"

proc drawPatternViewTopBorder(numTracks: int) =
  drawPatternViewBorder(numTracks, mid  = gGfx.boxHoriz,
                                   sep  = gGfx.boxHorizDown,
                                   last = gGfx.boxDownLeft)

proc drawPatternViewBottomBorder(numTracks: int) =
  drawPatternViewBorder(numTracks, mid  = gGfx.boxHoriz,
                                   sep  = gGfx.boxHorizUp,
                                   last = gGfx.boxUpLeft)

proc drawPatternViewEmptyRow(numTracks: int) =
  drawPatternViewBorder(numTracks, mid  = " ",
                                   sep  = gGfx.boxVert,
                                   last = gGfx.boxVert)

proc drawCell(cell: Cell, hilite: bool) =
  var
    note = noteToStr(cell.note)
    effect = effectToStr(cell.effect.int)

    s1 = (cell.sampleNum and 0xf0) shr 4
    s2 =  cell.sampleNum and 0x0f
    sampleNum = nibbleToChar(s1.int) & nibbleToChar(s2.int)

  if not hilite:
    if cell.note == NOTE_NONE:
      setColor gTheme.noteNone
    else:
      setColor gTheme.note

  put note & " "

  if not hilite:
    if cell.sampleNum == 0:
      setColor gTheme.sampleNone
    else:
      setColor gTheme.sample

  put sampleNum & " "

  if not hilite:
    if cell.effect == 0:
      setColor gTheme.effectNone
    else:
      setColor gTheme.effect

  put effect

  if not hilite:
    setColor gTheme.border


proc drawRow(patt: Pattern, rowNum, trackLo, trackHi: int, hilite: bool) =
  if hilite:
    setColor gTheme.cursor
    setBackgroundColor(gTheme.cursorBg)
  else:
    if rowNum mod 16 == 0:
      setColor gTheme.rowNumHi
    else:
      setColor gTheme.rowNum

  put "  " & align($rowNum, 2, '0')

  if not hilite:
    setColor gTheme.border

  put " " & gGfx.boxVert & " "

  for trackNum in trackLo..trackHi:
    drawCell(patt.tracks[trackNum].rows[rowNum], hilite)
    put " " & gGfx.boxVert & " "

  put "\n"


proc drawPatternView(patt: Pattern,
                     currRow, maxRows, startTrack, maxTracks: int) =
  assert currRow < ROWS_PER_PATTERN

  var
    trackLo = startTrack
    trackHi = trackLo + maxTracks - 1

  assert trackLo <= patt.tracks.high
  assert trackHi <= patt.tracks.high

  var hiliteRow = maxRows div 2
  if maxRows mod 2 == 0:
    hiliteRow -= 1

  var
    emptyRowsTop    = 0
    emptyRowsBottom = 0
    rowLo = currRow - hiliteRow
    rowHi = currRow + (maxRows - hiliteRow - 1)

  if rowLo < 0:
    emptyRowsTop = -rowLo
    hiliteRow += rowLo
    rowLo = 0
  else:
    hiliteRow += rowLo

  if rowHi > ROWS_PER_PATTERN-1:
    emptyRowsBottom = rowHi - (ROWS_PER_PATTERN-1)
    rowHi = ROWS_PER_PATTERN-1

  drawPatternViewTopBorder(maxTracks)

  for i in 0..<emptyRowsTop:
    drawPatternViewEmptyRow(maxTracks)

  for rowNum in rowLo..rowHi:
    var hilite = rowNum == hiliteRow
    drawRow(patt, rowNum, trackLo, trackHi, hilite)

  for i in 0..<emptyRowsBottom:
    drawPatternViewEmptyRow(maxTracks)

  drawPatternViewBottomBorder(maxTracks)

