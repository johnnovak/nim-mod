import strformat, strutils

import illwill

import config, module
import renderer


type
  ViewType* = enum
    vtPattern, vtSamples, vtHelp

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
    if cell.note == NoteNone:
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
  ScreenXPad = 2
  ScreenYPad = 1
  ViewY = 6
  PatternHeaderHeight = 3
  PatternTrackWidth = 10

proc drawPlaybackState*(tb: var TerminalBuffer, ps: PlaybackState) =
  const
    X1 = ScreenXPad + 1
    Y1 = ScreenYPad + 0
    Col1X = X1
    Col1XVal = Col1X + 10
    Col2X = X1 + 37
    Col2XVal = Col2X + 12
    Col3X = X1 + 25

  # Left column
  var y = Y1

  tb.setColor(gCurrTheme.text)
  tb.write(Col1X, y, fmt"Songname:")
  tb.setColor(gCurrTheme.textHi)
  tb.write(Col1XVal, y, ps.module.songName)
  inc(y)

  tb.setColor(gCurrTheme.text)
  tb.write(Col1X, y, fmt"Type:")
  tb.setColor(gCurrTheme.textHi)
  tb.write(Col1XVal, y, fmt"{ps.module.moduleType.toString} {ps.module.numChannels}chn")
  if not ps.module.useAmigaLimits:
    tb.write(fmt" [ext]")
  inc(y)

  tb.setColor(gCurrTheme.text)
  tb.write(Col1X, y, fmt"Songpos:")
  tb.setColor(gCurrTheme.textHi)
  tb.write(Col1XVal, y, fmt"{ps.currSongPos:03} / {ps.module.songLength-1:03}")
  inc(y)

  tb.setColor(gCurrTheme.text)
  tb.write(Col1X, y, fmt"Pattern:")
  tb.setColor(gCurrTheme.textHi)
  tb.write(Col1XVal, y, fmt"{ps.module.songPositions[ps.currSongPos]:03}")
  inc(y)

  tb.setColor(gCurrTheme.text)
  tb.write(Col1X, y, fmt"Time:")
  tb.setColor(gCurrTheme.textHi)
  let
    currSecsFract = (ps.playPositionFrame / ps.config.sampleRate).int
    currMins = currSecsFract div 60
    currSecs = currSecsFract mod 60
    totalSecsFract = (ps.songLengthFrames / ps.config.sampleRate).int
    totalMins = totalSecsFract div 60
    totalSecs = totalSecsFract mod 60

  tb.write(Col1XVal, y, fmt"{currMins:02}:{currSecs:02} / " &
                          fmt"{totalMins:02}:{totalSecs:02}")
  inc(y)

  # Right column
  y = Y1

  tb.setColor(gCurrTheme.text)
  tb.write(Col2X, y, fmt"Amp gain:")
  tb.setColor(gCurrTheme.textHi)
  tb.write(Col2XVal-1, y, fmt"{ps.config.ampGain:5.1f}dB")
  inc(y)

  tb.setColor(gCurrTheme.text)
  tb.write(Col2X, y, fmt"Resampler:")
  tb.setColor(gCurrTheme.textHi)

  var resamp: string
  case ps.config.resampler
  of rsNearestNeighbour: resamp = "off"
  of rsLinear:           resamp = "linear"
  tb.write(Col2XVal, y, fmt"{resamp:>6}")
  inc(y)

  tb.setColor(gCurrTheme.text)
  tb.write(Col2X, y, fmt"Stereo width:")
  tb.setColor(gCurrTheme.textHi)
  tb.write(Col2XVal+1, y, fmt"{ps.config.stereoWidth:4}%")
  inc(y)

  # Tempo & speed

  tb.setColor(gCurrTheme.text)
  tb.write(Col3X, Y1+2, fmt"Tempo:")
  tb.setColor(gCurrTheme.textHi)
  tb.write(Col3X+7, Y1+2, fmt"{ps.tempo:3}")

  tb.setColor(gCurrTheme.text)
  tb.write(Col3X, Y1+3, fmt"Speed:")
  tb.setColor(gCurrTheme.textHi)
  tb.write(Col3X+7, Y1+3, fmt"{ps.ticksPerRow:3}")


proc drawTrack(tb: var TerminalBuffer, x, y: Natural, track: Track,
               rowLo: Natural, rowHi: Natural, state: ChannelState) =
  assert rowLo < track.rows.len
  assert rowHi < track.rows.len

  var currY = y
  for i in rowLo..rowHi:
    tb.drawCell(x, currY, track.rows[i], state != csPlaying)
    inc(currY)


proc getPatternViewWidth(numTracks: Natural): Natural =
  result = (PatternTrackWidth + 3) * numTracks + 5

proc getPatternMaxVisibleTracks(screenWidth: Natural): Natural =
  result = max(screenWidth - ScreenXPad-7, 0) div (PatternTrackWidth + 3)

proc getPatternMaxVisibleRows(viewHeight: Natural): Natural =
  result = max(viewHeight - PatternHeaderHeight - 1, 0)


proc drawPattern*(tb: var TerminalBuffer, patt: Pattern,
                  currRow: int, maxRows, startTrack, endTrack: Natural,
                  channels: seq[renderer.Channel]) =

  assert currRow < RowsPerPattern
  assert startTrack <= patt.tracks.high
  assert endTrack <= patt.tracks.high

  if maxRows < 1: return

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
    x1 = ScreenXPad
    y1 = ViewY
    y2 = y1 + maxRows + PatternHeaderHeight
    firstRowY = y1 + numEmptyRowsTop + PatternHeaderHeight

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

    inc(x, PatternTrackWidth + 1)
    bb.drawVertLine(x, y1, y2)
    inc(x, 2)

  let x2 = x - 2

  bb.drawHorizLine(x1, x2, y1)
  bb.drawHorizLine(x1, x2, y2)
  bb.drawHorizLine(x1, x2, y1 + PatternHeaderHeight-1)

  tb.setColor(gCurrTheme.border)
  tb.write(bb)

  # Draw cursor line
  let cursorY = y1 + PatternHeaderHeight + cursorRow
  for x in ScreenXPad+1..x2-1:
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


var gStartSample = 1

proc scrollSamplesViewUp*() =
  gStartSample = max(gStartSample - 1, 1)

proc scrollSamplesViewDown*() =
  inc(gStartSample)

proc drawSamplesView*(tb: var TerminalBuffer, ps: PlaybackState,
                      viewHeight: Natural) =

  if viewHeight < 5: return

  const
    x1 = ScreenXPad
    y1 = ViewY

    NumX      = x1+1
    NameX     = NumX + 2 + 2
    LengthX   = NameX + SampleNameLen-1 + 2
    FinetuneX = LengthX + 5 + 2
    VolumeX   = FinetuneX + 2 + 2
    RepeatX   = VolumeX + 2 + 2
    RepLenX   = RepeatX + 5 + 2

    x2 = RepLenX + 5 + 2 - 1

  let
    y2 = y1 + viewHeight-1

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
  tb.write(NumX, y, "  #")
  tb.write(NameX, y, "Samplename")
  tb.write(LengthX, y, "Length")
  tb.write(FinetuneX, y, "Tun")
  tb.write(VolumeX, y, "Vol")
  tb.write(RepeatX, y, "Repeat")
  tb.write(RepLenX, y, "Replen")

  # Draw column separators
  bb.drawVertLine(NameX-1, y1, y2)
  bb.drawVertLine(LengthX-1, y1, y2)
  bb.drawVertLine(FinetuneX-1, y1, y2)
  bb.drawVertLine(VolumeX-1, y1, y2)
  bb.drawVertLine(RepeatX-1, y1, y2)
  bb.drawVertLine(RepLenX-1, y1, y2)

  tb.setColor(gCurrTheme.border)
  tb.write(bb)

  # Draw sample list
  let
    numSamples = ps.module.numSamples
    numVisibleSamples = viewHeight-4

  if gStartSample + numVisibleSamples - 1 > numSamples:
    gStartSample = max(numSamples - (numVisibleSamples - 1), 1)

  let endSample = min(gStartSample + numVisibleSamples - 1, numSamples)

  inc(y, 2)
  for sampNo in gStartSample..endSample:
    let sample = ps.module.samples[sampNo]

    if sample.length > 0: tb.setColor(gCurrTheme.sample)
    else:                 tb.setColor(gCurrTheme.muted)

    tb.write(NumX, y, fmt"{sampNo:3}")
    tb.write(LengthX, y, fmt"{sample.length:6}")

    if sample.signedFinetune() != 0: tb.setColor(gCurrTheme.sample)
    else:                            tb.setColor(gCurrTheme.muted)
    tb.write(FinetuneX, y, fmt"{sample.signedFinetune():3}")

    if sample.volume != 0: tb.setColor(gCurrTheme.sample)
    else:                  tb.setColor(gCurrTheme.muted)
    # XXX the cast is a Nim 0.20.0 regression workaround
    tb.write(VolumeX, y, fmt"{cast[int](sample.volume):3x}")

    if sample.repeatOffset > 0: tb.setColor(gCurrTheme.sample)
    else:                       tb.setColor(gCurrTheme.muted)
    tb.write(RepeatX, y, fmt"{sample.repeatOffset:6}")

    if sample.repeatLength > 2: tb.setColor(gCurrTheme.sample)
    else:                       tb.setColor(gCurrTheme.muted)
    tb.write(RepLenX, y, fmt"{sample.repeatLength:6}")

    tb.setColor(gCurrTheme.textHi)
    tb.write(NameX, y, sample.name)

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


proc drawHelpView*(tb: var TerminalBuffer, viewHeight: Natural) =
  if viewHeight < 2: return

  const
    WIDTH = 56
    x1 = ScreenXPad
    y1 = ViewY
    x2 = x1 + WIDTH

  let
    y2 = y1 + viewHeight-1

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
    numVisibleLines = max(viewHeight-2, 0)

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


proc drawPatternView(tb: var TerminalBuffer, ps: PlaybackState,
                     viewHeight: Natural) =

  let
    maxVisibleTracks = getPatternMaxVisibleTracks(tb.width)
    numTracks = ps.module.numChannels
    maxRows = getPatternMaxVisibleRows(viewHeight)

  var startTrack = gCurrTrackPage * maxVisibleTracks
  if startTrack > numTracks-1:
    startTrack = 0
    gCurrTrackPage = 0
  elif numTracks - startTrack < maxVisibleTracks:
    startTrack = max(numTracks - maxVisibleTracks, 0)

  let
    endTrack = max(min(startTrack + maxVisibleTracks-1, numTracks-1), 0)
    currPattern = ps.module.songPositions[ps.currSongPos]

  drawPattern(gTerminalBuffer, ps.module.patterns[currPattern],
              ps.currRow, maxRows, startTrack, endTrack, ps.channels)


proc drawStatusLine(tb: var TerminalBuffer) =
  if tb.height >= 9:
    tb.setColor(gCurrTheme.text)
    tb.write(ScreenXPad+1, tb.height - ScreenYPad-1, "Press ")
    tb.setColor(gCurrTheme.textHi)
    tb.write("?")
    tb.setColor(gCurrTheme.text)
    tb.write(" for help, ")
    tb.setColor(gCurrTheme.textHi)
    tb.write("Q")
    tb.setColor(gCurrTheme.text)
    tb.write(" to quit")

proc drawPauseOverlay(tb: var TerminalBuffer, ps: PlaybackState,
                      viewHeight: Natural) =

  if viewHeight < 5: return

  var viewWidth: Natural
  case gCurrView
  of vtPattern:
    let maxVisibleTracks = getPatternMaxVisibleTracks(tb.width)
    let numTracks = max(min(maxVisibleTracks, ps.module.numChannels), 1)
    viewWidth = getPatternViewWidth(numTracks)

  of vtSamples, vtHelp:
    viewWidth = 57

  let
    maxRows = getPatternMaxVisibleRows(viewHeight)

  var y = ViewY + PatternHeaderHeight + (maxRows-1) div 2 - 1
  var txt = "P A U S E D"
  tb.setColor(gCurrTheme.text)
  tb.write(ScreenXPad, y, "─".repeat(viewWidth))
  tb.write(ScreenXPad, y+1, " ".repeat(viewWidth))

  var x = ScreenXPad + max(viewWidth - txt.len, 0) div 2
  tb.write(x, y+1,
                       "P A U S E D")
  tb.write(ScreenXPad, y+2, "─".repeat(viewWidth))


proc drawScreen(tb: var TerminalBuffer, ps: PlaybackState) =
  drawPlaybackState(tb, ps)
  drawStatusLine(tb)

  let viewHeight = max(tb.height - ViewY - 3, 0)

  case gCurrView
  of vtPattern: drawPatternView(tb, ps, viewHeight)
  of vtSamples: drawSamplesView(tb, ps, viewHeight)
  of vtHelp:    drawHelpView(tb, viewHeight)

  if ps.paused:
    drawPauseOverlay(tb, ps, viewHeight)


proc updateScreen*(ps: PlaybackState, forceRedraw: bool = false) =
  var (w, h) = terminalSize()

  if gTerminalBuffer == nil or gTerminalBuffer.width != w or
                               gTerminalBuffer.height != h:
    gTerminalBuffer = newTerminalBuffer(w, h)
  else:
    gTerminalBuffer.clear()

  drawScreen(gTerminalBuffer, ps)

  if forceRedraw and hasDoubleBuffering():
    setDoubleBuffering(false)
    gTerminalBuffer.display()
    setDoubleBuffering(true)
  else:
    gTerminalBuffer.display()

