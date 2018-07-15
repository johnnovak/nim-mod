import strformat, strutils

import illwill

import module
from player import PlaybackState


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
  text:       TextColor
  textHi:     TextColor
  cursor:     TextColor
  cursorBg:   BackgroundColor

include themes

# Global variable to hold the current theme
var gTheme: Theme

gTheme = themes[0]

proc setTheme*(n: Natural) =
  if n <= themes.high:
    gTheme = themes[n]

template setColor(cb: var ConsoleBuffer, t: TextColor) =
  cb.setForegroundColor(t.fg)
  if t.hi:
    cb.setStyle({styleBright})
  else:
    cb.setStyle({})


proc drawCell(cb: var ConsoleBuffer, x, y: Natural, cell: Cell) =
  var
    note = noteToStr(cell.note)
    effect = effectToStr(cell.effect.int)

    s1 = (cell.sampleNum and 0xf0) shr 4
    s2 =  cell.sampleNum and 0x0f
    sampleNum = nibbleToChar(s1.int) & nibbleToChar(s2.int)

  if cell.note == NOTE_NONE:
    setColor(cb, gTheme.noteNone)
  else:
    setColor(cb, gTheme.note)

  cb.write(x, y, note)

  if cell.sampleNum == 0:
    setColor(cb, gTheme.sampleNone)
  else:
    setColor(cb, gTheme.sample)

  cb.write(x+4, y, sampleNum)

  if cell.effect == 0:
    setColor(cb, gTheme.effectNone)
  else:
    setColor(cb, gTheme.effect)

  cb.write(x+7, y, effect)


const
  SCREEN_X_PAD = 2
  SCREEN_Y_PAD = 1
  PATTERN_Y             = 6
  PATTERN_HEADER_HEIGHT = 3
  PATTERN_TRACK_WIDTH   = 10

proc drawPlaybackState*(cb: var ConsoleBuffer, ps: PlaybackState) =
  const
    X1 = SCREEN_X_PAD + 1
    Y1 = SCREEN_Y_PAD + 0
    COL1_X = X1
    COL1_X_VAL = COL1_X + 10
    COL2_X = X1 + 37
    COL2_X_VAL = COL2_X + 12
    COL3_X = X1 + 22

  # Left column
  var y = Y1

  setColor(cb, gTheme.text)
  cb.write(COL1_X, y, fmt"Songname:")
  setColor(cb, gTheme.textHi)
  cb.write(COL1_X_VAL, y, ps.module.songName)
  inc(y)

  setColor(cb, gTheme.text)
  cb.write(COL1_X, y, fmt"Type:")
  setColor(cb, gTheme.textHi)
  cb.write(COL1_X_VAL, y, fmt"{ps.module.moduleType.toString} {ps.module.numChannels}chn")
  inc(y)

  setColor(cb, gTheme.text)
  cb.write(COL1_X, y, fmt"Songpos:")
  setColor(cb, gTheme.textHi)
  cb.write(COL1_X_VAL, y, fmt"{ps.currSongPos:02}/{ps.module.songLength-1:02}")
  inc(y)

  setColor(cb, gTheme.text)
  cb.write(COL1_X, y, fmt"Pattern:")
  setColor(cb, gTheme.textHi)
  cb.write(COL1_X_VAL, y, fmt"{ps.module.songPositions[ps.currSongPos]:02}")
  inc(y)

  # Right column
  y = Y1

  setColor(cb, gTheme.text)
  cb.write(COL2_X, y, fmt"Volume:")
  setColor(cb, gTheme.textHi)
  cb.write(COL2_X_VAL, y, "  -6db")
  inc(y)

  setColor(cb, gTheme.text)
  cb.write(COL2_X, y, fmt"Resampler:")
  setColor(cb, gTheme.textHi)
  cb.write(COL2_X_VAL, y, "linear")
  inc(y)

  setColor(cb, gTheme.text)
  cb.write(COL2_X, y, fmt"De-click:")
  setColor(cb, gTheme.textHi)
  cb.write(COL2_X_VAL, y, "   off")
  inc(y)

  setColor(cb, gTheme.text)
  cb.write(COL2_X, y, fmt"Stereo sep.:")
  setColor(cb, gTheme.textHi)
  cb.write(COL2_X_VAL, y, "   20%")
  inc(y)

  # Tempo & speed

  setColor(cb, gTheme.text)
  cb.write(COL3_X, Y1+2, fmt"Tempo:")
  setColor(cb, gTheme.textHi)
  cb.write(COL3_X+8, Y1+2, fmt"{ps.tempo:3}")

  setColor(cb, gTheme.text)
  cb.write(COL3_X, Y1+3, fmt"Speed:")
  setColor(cb, gTheme.textHi)
  cb.write(COL3_X+8, Y1+3, fmt"{ps.ticksPerRow:3}")


proc drawTrack(cb: var ConsoleBuffer, x, y: Natural, track: Track,
               rowLo: Natural, rowHi: Natural) =
  assert rowLo < track.rows.len
  assert rowHi < track.rows.len

  var currY = y
  for i in rowLo..rowHi:
    drawCell(cb, x, currY, track.rows[i])
    inc(currY)


proc drawPatternView*(cb: var ConsoleBuffer, patt: Pattern,
                      currRow, maxRows, startTrack, maxTracks: int) =
  assert currRow < ROWS_PER_PATTERN

  let
    trackLo = startTrack
    trackHi = trackLo + maxTracks-1

  assert trackLo <= patt.tracks.high
  assert trackHi <= patt.tracks.high

  var bb = newBoxBuffer(cb.width, cb.height)

  let rowsInPattern = patt.tracks[0].rows.len

  var
    cursorRow = (maxRows-1) div 2
    numEmptyRowsTop = 0
    rowLo = currRow - cursorRow
    rowHi = min(currRow + (maxRows - cursorRow-1), rowsInPattern-1)

  if rowLo < 0:
    numEmptyRowsTop = -rowLo
    rowLo = 0

  let
    x1 = SCREEN_X_PAD
    y1 = PATTERN_Y
    y2 = y1 + maxRows + PATTERN_HEADER_HEIGHT
    firstRowY = y1 + numEmptyRowsTop + PATTERN_HEADER_HEIGHT

  var x = x1

  bb.drawVertLine(x, y1, y2)
  inc(x, 2)

  var y = firstRowY
  for rowNum in rowLo..rowHi:
    if rowNum mod 4 == 0:
      setColor(cb, gTheme.rowNumHi)
    else:
      setColor(cb, gTheme.rowNum)
    cb.write(x, y, fmt"{rowNum:2}")
    inc(y)

  inc(x, 2)
  bb.drawVertLine(x, y1, y2)
  inc(x, 2)

  y = firstRowY

  for i in trackLo..trackHi:
    setColor(cb, gTheme.text)
    cb.write(x, y1+1, fmt"Channel {i+1:2}")
    drawTrack(cb, x, y, patt.tracks[i], rowLo, rowHi)

    inc(x, PATTERN_TRACK_WIDTH + 1)
    bb.drawVertLine(x, y1, y2)
    inc(x, 2)

  let x2 = x - 2

  bb.drawHorizLine(x1, x2, y1)
  bb.drawHorizLine(x1, x2, y2)
  bb.drawHorizLine(x1, x2, y1 + PATTERN_HEADER_HEIGHT-1)

  setColor(cb, gTheme.border)
  cb.write(bb)

  let cursorY = y1 + PATTERN_HEADER_HEIGHT + cursorRow
  for x in SCREEN_X_PAD+1..x2-1:
    var c = cb[x, cursorY]
    c.fg = gTheme.cursor.fg
    c.bg = gTheme.cursorBg
    if gTheme.cursor.hi:
      c.style = {styleBright}
    else:
      c.style = {}
    cb[x, cursorY] = c


var cb: ConsoleBuffer

proc updateScreen*(ps: PlaybackState) =
  var (w, h) = terminalSize()
  dec(w)

  if cb == nil or cb.width != w or cb.height != h:
    cb = newConsoleBuffer(w, h)
  else:
    cb.clear()

  drawPlaybackState(cb, ps)

  let currPattern = ps.module.songPositions[ps.currSongPos]
  drawPatternView(cb, ps.module.patterns[currPattern],
                  currRow = ps.currRow,
                  maxRows = h - PATTERN_Y - PATTERN_HEADER_HEIGHT-4,
                  startTrack = 0, maxTracks = ps.module.numChannels)

  cb.setColor(gTheme.text)
  cb.write(SCREEN_X_PAD+1, h - SCREEN_Y_PAD-1, "Press ")
  cb.setColor(gTheme.textHi)
  cb.write("?")
  cb.setColor(gTheme.text)
  cb.write(" for help, ")
  cb.setColor(gTheme.textHi)
  cb.write("Q")
  cb.setColor(gTheme.text)
  cb.write(" to quit")

  cb.display()

