import strformat, strutils

import illwill

import config, module
import renderer


type
  ViewType* = enum
    vtPattern, vtSamples, vtHelp

var gCurrView = vtPattern

proc setCurrView*(view: ViewType) = gCurrView = view
proc currView*: ViewType = gCurrView


type
  TextColor = object
    fg: ForegroundColor
    hi: bool

  Theme = object
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

var gCurrTheme = themes[0]

proc setTheme*(n: Natural) =
  if n <= themes.high:
    gCurrTheme = themes[n]

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
    cb.setColor(gCurrTheme.muted)

  if not muted:
    if cell.note == NOTE_NONE:
      cb.setColor(gCurrTheme.noteNone)
    else:
      cb.setColor(gCurrTheme.note)

  cb.write(x, y, note)

  if not muted:
    if cell.sampleNum == 0:
      cb.setColor(gCurrTheme.sampleNone)
    else:
      cb.setColor(gCurrTheme.sample)

  cb.write(x+4, y, sampleNum)

  if not muted:
    if cell.effect == 0:
      cb.setColor(gCurrTheme.effectNone)
    else:
      cb.setColor(gCurrTheme.effect)

  cb.write(x+7, y, effect)


const
  SCREEN_X_PAD = 2
  SCREEN_Y_PAD = 1
  PLAYBACK_STATE_HEIGHT = 5
  VIEW_Y = 6
  PATTERN_HEADER_HEIGHT = 3
  PATTERN_TRACK_WIDTH = 10

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

  cb.setColor(gCurrTheme.text)
  cb.write(COL1_X, y, fmt"Songname:")
  cb.setColor(gCurrTheme.textHi)
  cb.write(COL1_X_VAL, y, ps.module.songName)
  inc(y)

  cb.setColor(gCurrTheme.text)
  cb.write(COL1_X, y, fmt"Type:")
  cb.setColor(gCurrTheme.textHi)
  cb.write(COL1_X_VAL, y, fmt"{ps.module.moduleType.toString} {ps.module.numChannels}chn")
  if not ps.module.useAmigaLimits:
    cb.write(fmt" [ext]")
  inc(y)

  cb.setColor(gCurrTheme.text)
  cb.write(COL1_X, y, fmt"Songpos:")
  cb.setColor(gCurrTheme.textHi)
  cb.write(COL1_X_VAL, y, fmt"{ps.currSongPos:03} / {ps.module.songLength-1:03}")
  inc(y)

  cb.setColor(gCurrTheme.text)
  cb.write(COL1_X, y, fmt"Pattern:")
  cb.setColor(gCurrTheme.textHi)
  cb.write(COL1_X_VAL, y, fmt"{ps.module.songPositions[ps.currSongPos]:03}")
  inc(y)

  cb.setColor(gCurrTheme.text)
  cb.write(COL1_X, y, fmt"Time:")
  cb.setColor(gCurrTheme.textHi)
  let
    currSecsFract = (ps.playPositionFrame / ps.config.sampleRate).int
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

  cb.setColor(gCurrTheme.text)
  cb.write(COL2_X, y, fmt"Volume:")
  cb.setColor(gCurrTheme.textHi)
  cb.write(COL2_X_VAL-1, y, fmt"{ps.config.ampGain:5.1f}dB")
  inc(y)

  cb.setColor(gCurrTheme.text)
  cb.write(COL2_X, y, fmt"Interpol.:")
  cb.setColor(gCurrTheme.textHi)

  var interpol: string
  case ps.config.interpolation
  of siNearestNeighbour: interpol = "off"
  of siLinear:           interpol = "linear"
  cb.write(COL2_X_VAL, y, fmt"{interpol:>6}")
  inc(y)

  cb.setColor(gCurrTheme.text)
  cb.write(COL2_X, y, fmt"De-click:")
  cb.setColor(gCurrTheme.textHi)
  cb.write(COL2_X_VAL, y, "   off")
  inc(y)

  cb.setColor(gCurrTheme.text)
  cb.write(COL2_X, y, fmt"Stereo width:")
  cb.setColor(gCurrTheme.textHi)
  cb.write(COL2_X_VAL+1, y, fmt"{ps.config.stereoWidth:4}%")
  inc(y)

  # Tempo & speed

  cb.setColor(gCurrTheme.text)
  cb.write(COL3_X, Y1+2, fmt"Tempo:")
  cb.setColor(gCurrTheme.textHi)
  cb.write(COL3_X+7, Y1+2, fmt"{ps.tempo:3}")

  cb.setColor(gCurrTheme.text)
  cb.write(COL3_X, Y1+3, fmt"Speed:")
  cb.setColor(gCurrTheme.textHi)
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
                      currRow: int, maxRows, startTrack, endTrack: Natural,
                      channels: seq[renderer.Channel]) =
  assert currRow < ROWS_PER_PATTERN
  assert startTrack <= patt.tracks.high
  assert endTrack <= patt.tracks.high

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
    y1 = VIEW_Y
    y2 = y1 + maxRows + PATTERN_HEADER_HEIGHT
    firstRowY = y1 + numEmptyRowsTop + PATTERN_HEADER_HEIGHT

  var x = x1

  bb.drawVertLine(x, y1, y2)
  inc(x, 2)

  # Draw row numbers
  var y = firstRowY
  for rowNum in rowLo..rowHi:
    if rowNum mod 4 == 0:
      cb.setColor(gCurrTheme.rowNumHi)
    else:
      cb.setColor(gCurrTheme.rowNum)
    cb.write(x, y, fmt"{rowNum:2}")
    inc(y)

  inc(x, 2)
  bb.drawVertLine(x, y1, y2)
  inc(x, 2)

  y = firstRowY

  # Draw tracks
  for i in startTrack..endTrack:
    let chanState = channels[i].state
    if chanState == csPlaying:
      cb.setColor(gCurrTheme.text)
    else:
      cb.setColor(gCurrTheme.muted)
    cb.write(x, y1+1, fmt"Channel {i+1:2}")
    cb.drawTrack(x, y, patt.tracks[i], rowLo, rowHi, chanState)

    inc(x, PATTERN_TRACK_WIDTH + 1)
    bb.drawVertLine(x, y1, y2)
    inc(x, 2)

  let x2 = x - 2

  bb.drawHorizLine(x1, x2, y1)
  bb.drawHorizLine(x1, x2, y2)
  bb.drawHorizLine(x1, x2, y1 + PATTERN_HEADER_HEIGHT-1)

  cb.setColor(gCurrTheme.border)
  cb.write(bb)

  # Draw cursor line
  let cursorY = y1 + PATTERN_HEADER_HEIGHT + cursorRow
  for x in SCREEN_X_PAD+1..x2-1:
    var c = cb[x, cursorY]
    c.fg = gCurrTheme.cursor.fg
    c.bg = gCurrTheme.cursorBg
    if gCurrTheme.cursor.hi:
      c.style = {styleBright}
    else:
      c.style = {}
    cb[x, cursorY] = c

  # Draw prev/next pattern page indicators
  cb.setColor(gCurrTheme.text)
  if startTrack > 0:
    cb.write(x1+4, y1+1, "<")
  if endTrack < patt.tracks.high:
    cb.write(x2, y1+1, ">")


proc getPatternViewWidth(numTracks: Natural): Natural =
  (PATTERN_TRACK_WIDTH + 3) * numTracks + 5

proc getMaxVisibleTracks(width: Natural): Natural =
  (width - SCREEN_X_PAD - 5) div (PATTERN_TRACK_WIDTH + 3)


var gStartSample = 1

proc scrollSamplesViewUp*() = dec(gStartSample)
proc scrollSamplesViewDown*() = inc(gStartSample)

proc drawSamplesView*(cb: var ConsoleBuffer, ps: PlaybackState,
                      height: Natural) =
  const
    x1 = SCREEN_X_PAD
    y1 = VIEW_Y

    NUM_X      = x1+1
    NAME_X     = NUM_X + 2 + 2
    LENGTH_X   = NAME_X + SAMPLE_NAME_LEN-1 + 2
    FINETUNE_X = LENGTH_X + 5 + 2
    VOLUME_X   = FINETUNE_X + 2 + 2
    REPEAT_X   = VOLUME_X + 2 + 2
    REPLEN_X   = REPEAT_X + 5 + 2

    x2 = REPLEN_X + 5 + 2 - 1

  let
    y2 = y1 + height-1

  var bb = newBoxBuffer(cb.width, cb.height)

  # Draw border
  bb.drawVertLine(x1, y1, y2)
  bb.drawVertLine(x2, y1, y2)
  bb.drawHorizLine(x1, x2, y1)
  bb.drawHorizLine(x1, x2, y2)

  # Draw headers
  var y = y1+1
  bb.drawHorizLine(x1, x2, y+1)
  cb.setColor(gCurrTheme.text)
  cb.write(NUM_X, y, "  #")
  cb.write(NAME_X, y, "Samplename")
  cb.write(LENGTH_X, y, "Length")
  cb.write(FINETUNE_X, y, "Tun")
  cb.write(VOLUME_X, y, "Vol")
  cb.write(REPEAT_X, y, "Repeat")
  cb.write(REPLEN_X, y, "Replen")

  # Draw column separators
  bb.drawVertLine(NAME_X-1, y1, y2)
  bb.drawVertLine(LENGTH_X-1, y1, y2)
  bb.drawVertLine(FINETUNE_X-1, y1, y2)
  bb.drawVertLine(VOLUME_X-1, y1, y2)
  bb.drawVertLine(REPEAT_X-1, y1, y2)
  bb.drawVertLine(REPLEN_X-1, y1, y2)

  cb.setColor(gCurrTheme.border)
  cb.write(bb)

  # Draw sample list
  if gStartSample < 1:
    gStartSample = 1

  let
    numSamples = ps.module.numSamples
    maxVisibleSamples = min(height-4, numSamples)
  var
    endSample = numSamples
  if endSample - gStartSample + 1 > maxVisibleSamples:
    endSample = gStartSample + maxVisibleSamples-1
  elif endSample - gStartSample + 1 < maxVisibleSamples:
    gStartSample = 1 + numSamples - maxVisibleSamples

  inc(y, 2)
  for sampNo in gStartSample..endSample:
    let sample = ps.module.samples[sampNo]

    if sample.length > 0: cb.setColor(gCurrTheme.sample)
    else:                 cb.setColor(gCurrTheme.muted)

    cb.write(NUM_X, y, fmt"{sampNo:3}")
    cb.write(LENGTH_X, y, fmt"{sample.length:6}")

    if sample.signedFinetune() != 0: cb.setColor(gCurrTheme.sample)
    else:                            cb.setColor(gCurrTheme.muted)
    cb.write(FINETUNE_X, y, fmt"{sample.signedFinetune():3}")

    cb.setColor(gCurrTheme.sample)
    cb.write(VOLUME_X, y, fmt"{sample.volume:3x}")

    if sample.repeatOffset > 0: cb.setColor(gCurrTheme.sample)
    else:                       cb.setColor(gCurrTheme.muted)
    cb.write(REPEAT_X, y, fmt"{sample.repeatOffset:6}")

    if sample.repeatLength > 2: cb.setColor(gCurrTheme.sample)
    else:                       cb.setColor(gCurrTheme.muted)
    cb.write(REPLEN_X, y, fmt"{sample.repeatLength:6}")

    if sample.length > 0: cb.setColor(gCurrTheme.textHi)
    else:                 cb.setColor(gCurrTheme.muted)
    cb.write(NAME_X, y, sample.name)

    inc(y)


var cb: ConsoleBuffer
var gCurrTrackPage = 0

proc nextTrackPage*() = inc(gCurrTrackPage)

proc updateScreen*(ps: PlaybackState, forceRedraw: bool = false) =
  var (w, h) = terminalSize()
  dec(w)

  if cb == nil or cb.width != w or cb.height != h:
    cb = newConsoleBuffer(w, h)
  else:
    cb.clear()

  drawPlaybackState(cb, ps)

  let
    maxVisibleTracks = getMaxVisibleTracks(w)
    numTracks = ps.module.numChannels

  var startTrack = gCurrTrackPage * maxVisibleTracks
  if startTrack > numTracks-1:
    startTrack = 0
    gCurrTrackPage = 0
  elif numTracks - startTrack < maxVisibleTracks:
    startTrack = numTracks - maxVisibleTracks

  let
    endTrack = min(startTrack + maxVisibleTracks-1, numTracks-1)
    viewWidth = getPatternViewWidth(maxVisibleTracks)
    viewHeight = h - VIEW_Y - 3
    maxRows = viewHeight - PATTERN_HEADER_HEIGHT - 1

  case gCurrView
  of vtPattern:
    let
      currPattern = ps.module.songPositions[ps.currSongPos]

    var pattViewWidth = 0
    if maxRows >= 1:
      drawPatternView(cb, ps.module.patterns[currPattern], ps.currRow, maxRows,
                      startTrack, endTrack, ps.channels)
  of vtSamples:
    if maxRows >= 1:
      drawSamplesView(cb, ps, viewHeight)

  of vtHelp:
    discard

  # Status line
  if h >= 9:
    cb.setColor(gCurrTheme.text)
    cb.write(SCREEN_X_PAD+1, h - SCREEN_Y_PAD-1, "Press ")
    cb.setColor(gCurrTheme.textHi)
    cb.write("?")
    cb.setColor(gCurrTheme.text)
    cb.write(" for help, ")
    cb.setColor(gCurrTheme.textHi)
    cb.write("Q")
    cb.setColor(gCurrTheme.text)
    cb.write(" to quit")

  # Pause overlay
  if ps.paused:
    var y = VIEW_Y + PATTERN_HEADER_HEIGHT + (maxRows-1) div 2 - 1
    var txt = "P A U S E D"
    cb.setColor(gCurrTheme.text)
    cb.write(SCREEN_X_PAD, y, "─".repeat(viewWidth))
    cb.write(SCREEN_X_PAD, y+1, " ".repeat(viewWidth))
    cb.write(SCREEN_X_PAD + (viewWidth - txt.len) div 2, y+1, "P A U S E D")
    cb.write(SCREEN_X_PAD, y+2, "─".repeat(viewWidth))

  if forceRedraw:
    setDoubleBuffering(false)
    cb.display()
    setDoubleBuffering(true)
  else:
    cb.display()

