import strutils

import module
import illwill/illwill
from player import PlaybackState


# TODO move into illwill
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

let gfxCharsCP850 = GraphicsChars(
  boxHoriz:     "\196",
  boxHorizUp:   "\193",
  boxHorizDown: "\194",
  boxVert:      "\179",
  boxVertLeft:  "\180",
  boxVertRight: "\195",
  boxVertHoriz: "\197",
  boxDownLeft:  "\191",
  boxDownRight: "\218",
  boxUpRight:   "\192",
  boxUpLeft:    "\217"
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

# TODO belongs to illwill
# Global variable to hold the set of gfx chars to use
var gGfx: GraphicsChars

when defined(windows):
  gGfx = gfxCharsCP850
else:
  when defined(posix):
    import os
    if "utf" in getEnv("LANG").toLowerAscii:
      gGfx = gfxCharsUnicode
  else:
    gGfx = gfxCharsAscii


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

include themes

# Global variable to hold the current theme
var gTheme: Theme

gTheme = themes[0]

proc setTheme*(n: Natural) =
  if n <= themes.high:
    gTheme = themes[n]

template setColor(t: TextColor) =
  resetAttributes(stdout)
  setForegroundColor(stdout, t.fg)
  if t.hi:
    setStyle(stdout, {styleBright})


proc drawPatternViewBorder(numTracks: int, mid, sep, last: string) =
  const
    PATTERN_VIEW_ROWNUM_WIDTH = 5
    PATTERN_VIEW_TRACK_WIDTH  = 12

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


proc drawPlaybackState*(ps: PlaybackState) =
  put "Songname: "
  put ps.module.songName

  cursorDown(stdout)
  setCursorXPos(0)
  put "Position: "
  put $ps.songPos
  put "/"
  put $ps.module.songLength

  put "      Tempo: "
  put $ps.tempo

  cursorDown(stdout)
  setCursorXPos(0)
  put "Pattern:  "
  put $ps.module.songPositions[ps.songPos]

  put "         Speed: "
  put $ps.ticksPerRow


proc drawPatternView*(patt: Pattern,
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

