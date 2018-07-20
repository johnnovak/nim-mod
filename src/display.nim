import strformat, strutils

import illwill

import module
import renderer


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
  muted:      TextColor
  text:       TextColor
  textHi:     TextColor
  cursor:     TextColor
  cursorBg:   BackgroundColor

include themes

var currTheme = themes[0]

proc setTheme*(n: Natural) =
  if n <= themes.high:
    currTheme = themes[n]

template setColor(cb: var ConsoleBuffer, t: TextColor) =
  cb.setForegroundColor(t.fg)
  if t.hi:
    cb.setStyle({styleBright})
  else:
    cb.setStyle({})


proc drawCell(cb: var ConsoleBuffer, x, y: Natural, cell: Cell, muted: bool) =
  var
    note = noteToStr(cell.note)
    effect = effectToStr(cell.effect.int)

    s1 = (cell.sampleNum and 0xf0) shr 4
    s2 =  cell.sampleNum and 0x0f
    sampleNum = nibbleToChar(s1.int) & nibbleToChar(s2.int)

  if muted:
    cb.setColor(currTheme.muted)

  if not muted:
    if cell.note == NOTE_NONE:
      cb.setColor(currTheme.noteNone)
    else:
      cb.setColor(currTheme.note)

  cb.write(x, y, note)

  if not muted:
    if cell.sampleNum == 0:
      cb.setColor(currTheme.sampleNone)
    else:
      cb.setColor(currTheme.sample)

  cb.write(x+4, y, sampleNum)

  if not muted:
    if cell.effect == 0:
      cb.setColor(currTheme.effectNone)
    else:
      cb.setColor(currTheme.effect)

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
    COL3_X = X1 + 25

  # Left column
  var y = Y1

  cb.setColor(currTheme.text)
  cb.write(COL1_X, y, fmt"Songname:")
  cb.setColor(currTheme.textHi)
  cb.write(COL1_X_VAL, y, ps.module.songName)
  inc(y)

  cb.setColor(currTheme.text)
  cb.write(COL1_X, y, fmt"Type:")
  cb.setColor(currTheme.textHi)
  cb.write(COL1_X_VAL, y, fmt"{ps.module.moduleType.toString} {ps.module.numChannels}chn")
  inc(y)

  cb.setColor(currTheme.text)
  cb.write(COL1_X, y, fmt"Songpos:")
  cb.setColor(currTheme.textHi)
  cb.write(COL1_X_VAL, y, fmt"{ps.currSongPos:02}/{ps.module.songLength-1:02}")
  inc(y)

  cb.setColor(currTheme.text)
  cb.write(COL1_X, y, fmt"Pattern:")
  cb.setColor(currTheme.textHi)
  cb.write(COL1_X_VAL, y, fmt"{ps.module.songPositions[ps.currSongPos]:02}")
  inc(y)

  cb.setColor(currTheme.text)
  cb.write(COL1_X, y, fmt"Time:")
  cb.setColor(currTheme.textHi)
  let
    currSecsFract = (ps.currFrame / ps.config.sampleRate).int
    currMins = currSecsFract div 60
    currSecs = currSecsFract mod 60
    totalSecsFract = (ps.songLengthFrames / ps.config.sampleRate).int
    totalMins = totalSecsFract div 60
    totalSecs = totalSecsFract mod 60

  cb.write(COL1_X_VAL, y, fmt"{currMins:02}:{currSecs:02} / " &
                          fmt"{totalMins:02}:{totalSecs:02}")
  inc(y)

  # Right column
  y = Y1

  cb.setColor(currTheme.text)
  cb.write(COL2_X, y, fmt"Volume:")
  cb.setColor(currTheme.textHi)
  cb.write(COL2_X_VAL, y, "  -6db")
  inc(y)

  cb.setColor(currTheme.text)
  cb.write(COL2_X, y, fmt"Resampler:")
  cb.setColor(currTheme.textHi)
  cb.write(COL2_X_VAL, y, "linear")
  inc(y)

  cb.setColor(currTheme.text)
  cb.write(COL2_X, y, fmt"De-click:")
  cb.setColor(currTheme.textHi)
  cb.write(COL2_X_VAL, y, "   off")
  inc(y)

  cb.setColor(currTheme.text)
  cb.write(COL2_X, y, fmt"Stereo sep.:")
  cb.setColor(currTheme.textHi)
  cb.write(COL2_X_VAL, y, "   20%")
  inc(y)

  # Tempo & speed

  cb.setColor(currTheme.text)
  cb.write(COL3_X, Y1+2, fmt"Tempo:")
  cb.setColor(currTheme.textHi)
  cb.write(COL3_X+7, Y1+2, fmt"{ps.tempo:3}")

  cb.setColor(currTheme.text)
  cb.write(COL3_X, Y1+3, fmt"Speed:")
  cb.setColor(currTheme.textHi)
  cb.write(COL3_X+7, Y1+3, fmt"{ps.ticksPerRow:3}")


proc drawTrack(cb: var ConsoleBuffer, x, y: Natural, track: Track,
               rowLo: Natural, rowHi: Natural, state: ChannelState) =
  assert rowLo < track.rows.len
  assert rowHi < track.rows.len

  var currY = y
  for i in rowLo..rowHi:
    cb.drawCell(x, currY, track.rows[i], state != csPlaying)
    inc(currY)


proc drawPatternView*(cb: var ConsoleBuffer, patt: Pattern,
                      currRow, maxRows, startTrack, maxTracks: int,
                      channels: seq[renderer.Channel]) =
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
      cb.setColor(currTheme.rowNumHi)
    else:
      cb.setColor(currTheme.rowNum)
    cb.write(x, y, fmt"{rowNum:2}")
    inc(y)

  inc(x, 2)
  bb.drawVertLine(x, y1, y2)
  inc(x, 2)

  y = firstRowY

  for i in trackLo..trackHi:
    let chanState = channels[i].state
    if chanState == csPlaying:
      cb.setColor(currTheme.text)
    else:
      cb.setColor(currTheme.muted)
    cb.write(x, y1+1, fmt"Channel {i+1:2}")
    cb.drawTrack(x, y, patt.tracks[i], rowLo, rowHi, chanState)

    inc(x, PATTERN_TRACK_WIDTH + 1)
    bb.drawVertLine(x, y1, y2)
    inc(x, 2)

  let x2 = x - 2

  bb.drawHorizLine(x1, x2, y1)
  bb.drawHorizLine(x1, x2, y2)
  bb.drawHorizLine(x1, x2, y1 + PATTERN_HEADER_HEIGHT-1)

  cb.setColor(currTheme.border)
  cb.write(bb)

  let cursorY = y1 + PATTERN_HEADER_HEIGHT + cursorRow
  for x in SCREEN_X_PAD+1..x2-1:
    var c = cb[x, cursorY]
    c.fg = currTheme.cursor.fg
    c.bg = currTheme.cursorBg
    if currTheme.cursor.hi:
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
                  ps.currRow,
                  maxRows = h - PATTERN_Y - PATTERN_HEADER_HEIGHT-4,
                  startTrack = 0, maxTracks = ps.module.numChannels,
                  ps.channels)

  cb.setColor(currTheme.text)
  cb.write(SCREEN_X_PAD+1, h - SCREEN_Y_PAD-1, "Press ")
  cb.setColor(currTheme.textHi)
  cb.write("?")
  cb.setColor(currTheme.text)
  cb.write(" for help, ")
  cb.setColor(currTheme.textHi)
  cb.write("Q")
  cb.setColor(currTheme.text)
  cb.write(" to quit")

  cb.display()

