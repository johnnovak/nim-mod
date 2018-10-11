import strformat, strutils

import illwill

import config, module
import renderer


type
  ViewType* = enum
    vtPattern, vtSamples, vtHelp


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

template setColor(tb: var TerminalBuffer, t: TextColor) =
  tb.setForegroundColor(t.fg)
  if t.hi:
    tb.setStyle({styleBright})
  else:
    tb.setStyle({})


proc drawCell(tb: var TerminalBuffer, x, y: Natural, cell: Cell, muted: bool) =
  var
    note = noteToStr(cell.note)
    effect = effectToStr(cell.effect.int)

    s1 = (cell.sampleNum and 0xf0) shr 4
    s2 =  cell.sampleNum and 0x0f
    sampleNum = nibbleToChar(s1.int) & nibbleToChar(s2.int)

  if muted:
    tb.setColor(gCurrTheme.muted)

  if not muted:
    if cell.note == NOTE_NONE:
      tb.setColor(gCurrTheme.noteNone)
    else:
      tb.setColor(gCurrTheme.note)

  tb.write(x, y, note)

  if not muted:
    if cell.sampleNum == 0:
      tb.setColor(gCurrTheme.sampleNone)
    else:
      tb.setColor(gCurrTheme.sample)

  tb.write(x+4, y, sampleNum)

  if not muted:
    if cell.effect == 0:
      tb.setColor(gCurrTheme.effectNone)
    else:
      tb.setColor(gCurrTheme.effect)

  tb.write(x+7, y, effect)


const
  SCREEN_X_PAD = 2
  SCREEN_Y_PAD = 1
  PLAYBACK_STATE_HEIGHT = 5
  VIEW_Y = 6
  PATTERN_HEADER_HEIGHT = 3
  PATTERN_TRACK_WIDTH = 10

proc drawPlaybackState*(tb: var TerminalBuffer, ps: PlaybackState) =
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

  tb.setColor(gCurrTheme.text)
  tb.write(COL1_X, y, fmt"Songname:")
  tb.setColor(gCurrTheme.textHi)
  tb.write(COL1_X_VAL, y, ps.module.songName)
  inc(y)

  tb.setColor(gCurrTheme.text)
  tb.write(COL1_X, y, fmt"Type:")
  tb.setColor(gCurrTheme.textHi)
  tb.write(COL1_X_VAL, y, fmt"{ps.module.moduleType.toString} {ps.module.numChannels}chn")
  if not ps.module.useAmigaLimits:
    tb.write(fmt" [ext]")
  inc(y)

  tb.setColor(gCurrTheme.text)
  tb.write(COL1_X, y, fmt"Songpos:")
  tb.setColor(gCurrTheme.textHi)
  tb.write(COL1_X_VAL, y, fmt"{ps.currSongPos:03} / {ps.module.songLength-1:03}")
  inc(y)

  tb.setColor(gCurrTheme.text)
  tb.write(COL1_X, y, fmt"Pattern:")
  tb.setColor(gCurrTheme.textHi)
  tb.write(COL1_X_VAL, y, fmt"{ps.module.songPositions[ps.currSongPos]:03}")
  inc(y)

  tb.setColor(gCurrTheme.text)
  tb.write(COL1_X, y, fmt"Time:")
  tb.setColor(gCurrTheme.textHi)
  let
    currSecsFract = (ps.playPositionFrame / ps.config.sampleRate).int
    currMins = currSecsFract div 60
    currSecs = currSecsFract mod 60
    totalSecsFract = (ps.songLengthFrames / ps.config.sampleRate).int
    totalMins = totalSecsFract div 60
    totalSecs = totalSecsFract mod 60

  tb.write(COL1_X_VAL, y, fmt"{currMins:02}:{currSecs:02} / " &
                          fmt"{totalMins:02}:{totalSecs:02}")
  inc(y)

  # Right column
  y = Y1

  tb.setColor(gCurrTheme.text)
  tb.write(COL2_X, y, fmt"Amp gain:")
  tb.setColor(gCurrTheme.textHi)
  tb.write(COL2_X_VAL-1, y, fmt"{ps.config.ampGain:5.1f}dB")
  inc(y)

  tb.setColor(gCurrTheme.text)
  tb.write(COL2_X, y, fmt"Resampler:")
  tb.setColor(gCurrTheme.textHi)

  var resamp: string
  case ps.config.resampler
  of rsNearestNeighbour: resamp = "off"
  of rsLinear:           resamp = "linear"
  tb.write(COL2_X_VAL, y, fmt"{resamp:>6}")
  inc(y)

  tb.setColor(gCurrTheme.text)
  tb.write(COL2_X, y, fmt"Stereo width:")
  tb.setColor(gCurrTheme.textHi)
  tb.write(COL2_X_VAL+1, y, fmt"{ps.config.stereoWidth:4}%")
  inc(y)

  # Tempo & speed

  tb.setColor(gCurrTheme.text)
  tb.write(COL3_X, Y1+2, fmt"Tempo:")
  tb.setColor(gCurrTheme.textHi)
  tb.write(COL3_X+7, Y1+2, fmt"{ps.tempo:3}")

  tb.setColor(gCurrTheme.text)
  tb.write(COL3_X, Y1+3, fmt"Speed:")
  tb.setColor(gCurrTheme.textHi)
  tb.write(COL3_X+7, Y1+3, fmt"{ps.ticksPerRow:3}")


proc drawTrack(tb: var TerminalBuffer, x, y: Natural, track: Track,
               rowLo: Natural, rowHi: Natural, state: ChannelState) =
  assert rowLo < track.rows.len
  assert rowHi < track.rows.len

  var currY = y
  for i in rowLo..rowHi:
    tb.drawCell(x, currY, track.rows[i], state != csPlaying)
    inc(currY)


proc drawPatternView*(tb: var TerminalBuffer, patt: Pattern,
                      currRow: int, maxRows, startTrack, endTrack: Natural,
                      channels: seq[renderer.Channel]) =
  assert currRow < ROWS_PER_PATTERN
  assert startTrack <= patt.tracks.high
  assert endTrack <= patt.tracks.high

  var bb = newBoxBuffer(tb.width, tb.height)

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
      tb.setColor(gCurrTheme.rowNumHi)
    else:
      tb.setColor(gCurrTheme.rowNum)
    tb.write(x, y, fmt"{rowNum:2}")
    inc(y)

  inc(x, 2)
  bb.drawVertLine(x, y1, y2)
  inc(x, 2)

  y = firstRowY

  # Draw tracks
  for i in startTrack..endTrack:
    let chanState = channels[i].state
    if chanState == csPlaying:
      tb.setColor(gCurrTheme.text)
    else:
      tb.setColor(gCurrTheme.muted)
    tb.write(x, y1+1, fmt"Channel {i+1:2}")
    tb.drawTrack(x, y, patt.tracks[i], rowLo, rowHi, chanState)

    inc(x, PATTERN_TRACK_WIDTH + 1)
    bb.drawVertLine(x, y1, y2)
    inc(x, 2)

  let x2 = x - 2

  bb.drawHorizLine(x1, x2, y1)
  bb.drawHorizLine(x1, x2, y2)
  bb.drawHorizLine(x1, x2, y1 + PATTERN_HEADER_HEIGHT-1)

  tb.setColor(gCurrTheme.border)
  tb.write(bb)

  # Draw cursor line
  let cursorY = y1 + PATTERN_HEADER_HEIGHT + cursorRow
  for x in SCREEN_X_PAD+1..x2-1:
    var c = tb[x, cursorY]
    c.fg = gCurrTheme.cursor.fg
    c.bg = gCurrTheme.cursorBg
    if gCurrTheme.cursor.hi:
      c.style = {styleBright}
    else:
      c.style = {}
    tb[x, cursorY] = c

  # Draw prev/next pattern page indicators
  tb.setColor(gCurrTheme.text)
  if startTrack > 0:
    tb.write(x1+4, y1+1, "<")
  if endTrack < patt.tracks.high:
    tb.write(x2, y1+1, ">")


proc getPatternViewWidth(numTracks: Natural): Natural =
  (PATTERN_TRACK_WIDTH + 3) * numTracks + 5

proc getMaxVisibleTracks(width: Natural): Natural =
  (width - SCREEN_X_PAD - 5) div (PATTERN_TRACK_WIDTH + 3)


var gStartSample = 1

proc scrollSamplesViewUp*() =
  gStartSample = max(gStartSample - 1, 1)

proc scrollSamplesViewDown*() =
  inc(gStartSample)

proc drawSamplesView*(tb: var TerminalBuffer, ps: PlaybackState,
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

  var bb = newBoxBuffer(tb.width, tb.height)

  # Draw border
  bb.drawVertLine(x1, y1, y2)
  bb.drawVertLine(x2, y1, y2)
  bb.drawHorizLine(x1, x2, y1)
  bb.drawHorizLine(x1, x2, y2)

  # Draw headers
  var y = y1+1
  bb.drawHorizLine(x1, x2, y+1)
  tb.setColor(gCurrTheme.text)
  tb.write(NUM_X, y, "  #")
  tb.write(NAME_X, y, "Samplename")
  tb.write(LENGTH_X, y, "Length")
  tb.write(FINETUNE_X, y, "Tun")
  tb.write(VOLUME_X, y, "Vol")
  tb.write(REPEAT_X, y, "Repeat")
  tb.write(REPLEN_X, y, "Replen")

  # Draw column separators
  bb.drawVertLine(NAME_X-1, y1, y2)
  bb.drawVertLine(LENGTH_X-1, y1, y2)
  bb.drawVertLine(FINETUNE_X-1, y1, y2)
  bb.drawVertLine(VOLUME_X-1, y1, y2)
  bb.drawVertLine(REPEAT_X-1, y1, y2)
  bb.drawVertLine(REPLEN_X-1, y1, y2)

  tb.setColor(gCurrTheme.border)
  tb.write(bb)

  # Draw sample list
  let
    numSamples = ps.module.numSamples
    numVisibleSamples = height-4

  if gStartSample + numVisibleSamples - 1 > numSamples:
    gStartSample = max(numSamples - (numVisibleSamples - 1), 1)

  let endSample = min(gStartSample + numVisibleSamples - 1, numSamples)

  inc(y, 2)
  for sampNo in gStartSample..endSample:
    let sample = ps.module.samples[sampNo]

    if sample.length > 0: tb.setColor(gCurrTheme.sample)
    else:                 tb.setColor(gCurrTheme.muted)

    tb.write(NUM_X, y, fmt"{sampNo:3}")
    tb.write(LENGTH_X, y, fmt"{sample.length:6}")

    if sample.signedFinetune() != 0: tb.setColor(gCurrTheme.sample)
    else:                            tb.setColor(gCurrTheme.muted)
    tb.write(FINETUNE_X, y, fmt"{sample.signedFinetune():3}")

    if sample.volume != 0: tb.setColor(gCurrTheme.sample)
    else:                  tb.setColor(gCurrTheme.muted)
    tb.write(VOLUME_X, y, fmt"{sample.volume:3x}")

    if sample.repeatOffset > 0: tb.setColor(gCurrTheme.sample)
    else:                       tb.setColor(gCurrTheme.muted)
    tb.write(REPEAT_X, y, fmt"{sample.repeatOffset:6}")

    if sample.repeatLength > 2: tb.setColor(gCurrTheme.sample)
    else:                       tb.setColor(gCurrTheme.muted)
    tb.write(REPLEN_X, y, fmt"{sample.repeatLength:6}")

    tb.setColor(gCurrTheme.textHi)
    tb.write(NAME_X, y, sample.name)

    inc(y)


var gHelpViewText: TerminalBuffer

var gStartHelpLine = 0

proc scrollHelpViewUp*() =
  gStartHelpLine = max(gStartHelpLine - 1, 0)

proc scrollHelpViewDown*() =
  inc(gStartHelpLine)

proc createHelpViewText() =
  var
    y = 0
    xPad = 15

  proc writeEntry(key: string, desc: string) =
    gHelpViewText.setColor(gCurrTheme.textHi)
    gHelpViewText.write(0, y, key)
    gHelpViewText.setColor(gCurrTheme.text)
    gHelpViewText.write(xPad, y, desc)
    inc(y)

  gHelpViewText.setColor(gCurrTheme.note)
  gHelpViewText.write(0, y, "GENERAL")
  inc(y, 2)

  writeEntry("?", "toggle help view")
  writeEntry("ESC", "exit help view")
  writeEntry("UpArrow, K", "scroll view up (sample & help view)")
  writeEntry("DownArrow, J", "scroll view down (sample & help view)")
  writeEntry("V", "toggle pattern/sample view")
  writeEntry("Tab", "next track page (pattern view)")
  writeEntry("F1-F7", "set theme")
  writeEntry("R", "force redraw screen")
  writeEntry("Q", "quit")
  inc(y)

  gHelpViewText.setColor(gCurrTheme.note)
  gHelpViewText.write(0, y, "PLAYBACK")
  inc(y, 2)

  writeEntry("SPACE", "pause playback")
  writeEntry("LeftArrow, H", "jump 1 song position backward")
  writeEntry("Shift+H", "jump 10 song positions backward")
  writeEntry("RightArrow, L", "jump 1 song position forward")
  writeEntry("Shift+L", "jump 10 song positions forward")
  writeEntry("G", "jump to first song position")
  writeEntry("Shift+G", "jump to last song position")
  inc(y)

  gHelpViewText.setColor(gCurrTheme.note)
  gHelpViewText.write(0, y, "SOUND OUTPUT")
  inc(y, 2)

  xPad = 6
  writeEntry("1-9", "toggle mute channels 1-9")
  writeEntry("0", "toggle mute channel 10")
  writeEntry("U", "unmute all channels")
  writeEntry(",", "decrease amp gain")
  writeEntry(".", "increase amp gain")
  writeEntry("[", "decrease stereo width")
  writeEntry("]", "increase stereo width")
  writeEntry("I", "toggle resampler algorithm")
  inc(y)


proc drawHelpView*(tb: var TerminalBuffer, ps: PlaybackState, height: Natural) =
  const
    WIDTH = 56
    x1 = SCREEN_X_PAD
    y1 = VIEW_Y
    x2 = x1 + WIDTH

  let
    y2 = y1 + height-1

  var bb = newBoxBuffer(tb.width, tb.height)

  # Draw border
  bb.drawVertLine(x1, y1, y2)
  bb.drawVertLine(x2, y1, y2)
  bb.drawHorizLine(x1, x2, y1)
  bb.drawHorizLine(x1, x2, y2)

  tb.setColor(gCurrTheme.border)
  tb.write(bb)

  var x = x1+2
  var y = y1+1

  gHelpViewText = newTerminalBuffer(WIDTH-2, 32)
  createHelpViewText()  # could be suboptimal with long texts, but in reality
                        # doesn't really matter...
  let
    numLines = gHelpViewText.height
    numVisibleLines = height-2

  if gStartHelpLine + numVisibleLines >= numLines:
    gStartHelpLine = max(numLines - numVisibleLines, 0)

  tb.copyFrom(gHelpViewText, 0, gStartHelpLine, WIDTH, numVisibleLines, x, y)


var gCurrTrackPage = 0

proc nextTrackPage*() = inc(gCurrTrackPage)


var
  gCurrView = vtPattern
  gLastView: ViewType

proc setCurrView*(view: ViewType) =
  gCurrView = view

proc currView*: ViewType = gCurrView

proc toggleHelpView*() =
  if gCurrView == vtHelp:
    gCurrView = gLastView
  else:
    gLastView = gCurrView
    gCurrView = vtHelp


var gTerminalBuffer: TerminalBuffer

proc updateScreen*(ps: PlaybackState, forceRedraw: bool = false) =
  var (w, h) = terminalSize()
  dec(w)

  if gTerminalBuffer == nil or gTerminalBuffer.width != w or
                               gTerminalBuffer.height != h:
    gTerminalBuffer = newTerminalBuffer(w, h)
  else:
    gTerminalBuffer.clear()

  drawPlaybackState(gTerminalBuffer, ps)

  let
    maxVisibleTracks = getMaxVisibleTracks(w)
    numTracks = ps.module.numChannels

  var startTrack = gCurrTrackPage * maxVisibleTracks
  if startTrack > numTracks-1:
    startTrack = 0
    gCurrTrackPage = 0
  elif numTracks - startTrack < maxVisibleTracks:
    startTrack = max(numTracks - maxVisibleTracks, 0)

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
      drawPatternView(gTerminalBuffer, ps.module.patterns[currPattern],
                      ps.currRow, maxRows, startTrack, endTrack, ps.channels)
  of vtSamples:
    if maxRows >= 1:
      drawSamplesView(gTerminalBuffer, ps, viewHeight)

  of vtHelp:
    drawHelpView(gTerminalBuffer, ps, viewHeight)

  # Status line
  if h >= 9:
    gTerminalBuffer.setColor(gCurrTheme.text)
    gTerminalBuffer.write(SCREEN_X_PAD+1, h - SCREEN_Y_PAD-1, "Press ")
    gTerminalBuffer.setColor(gCurrTheme.textHi)
    gTerminalBuffer.write("?")
    gTerminalBuffer.setColor(gCurrTheme.text)
    gTerminalBuffer.write(" for help, ")
    gTerminalBuffer.setColor(gCurrTheme.textHi)
    gTerminalBuffer.write("Q")
    gTerminalBuffer.setColor(gCurrTheme.text)
    gTerminalBuffer.write(" to quit")

  # Pause overlay
  if ps.paused:
    var y = VIEW_Y + PATTERN_HEADER_HEIGHT + (maxRows-1) div 2 - 1
    var txt = "P A U S E D"
    gTerminalBuffer.setColor(gCurrTheme.text)
    gTerminalBuffer.write(SCREEN_X_PAD, y, "─".repeat(viewWidth))
    gTerminalBuffer.write(SCREEN_X_PAD, y+1, " ".repeat(viewWidth))
    gTerminalBuffer.write(SCREEN_X_PAD + (viewWidth - txt.len) div 2, y+1,
                         "P A U S E D")
    gTerminalBuffer.write(SCREEN_X_PAD, y+2, "─".repeat(viewWidth))

  if forceRedraw:
    setDoubleBuffering(false)
    gTerminalBuffer.display()
    setDoubleBuffering(true)
  else:
    gTerminalBuffer.display()

