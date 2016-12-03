import os, terminal

import illwill/illwill
import audio/linux/alsa/alsadriver

include common
include loader
include display
include themes
include player


when defined(windows):
  gGfx = gfxCharsCP850
else:
  when defined(posix):
    if "utf" in getEnv("LANG").toLowerAscii:
      gGfx = gfxCharsUnicode
  else:
    gGfx = gfxCharsAscii

gTheme = themes[0]

var gRedraw = true
var gMaxRows = 32

const ROW_JUMP = 8

var gPlaybackState: PlaybackState


proc quitProc() {.noconv.} =
  resetAttributes()
  consoleDeinit()
  exitFullscreen()
  showCursor()


proc setTheme(n: Natural) =
  if n <= themes.high:
    gTheme = themes[n]
    gRedraw = true

const SAMPLE_RATE = 44100

proc playerCallback(samples: AudioBufferPtr, numFrames: int) {.cdecl, gcsafe.} =
  render(gPlaybackState, samples, numFrames, SAMPLE_RATE)


proc main() =
  system.addQuitProc(quitProc)

  consoleInit()
  enterFullscreen()
  hideCursor()

  let (w, h) = terminalSize()

  var buf = readFile("../data/STRWORLD.MOD")
  let module = loadModule(buf)

  initPlaybackState(gPlaybackState, module)
  initAudio(playerCallback)

  var
    currPattern = 0
    currRow = 0
    lastPattern = -1
    lastRow = -1

  proc setRow(row: Natural) =
    lastRow = currRow
    currRow = row
    if currRow != lastRow:
      gRedraw = true

  proc setPattern(patt: Natural) =
    lastPattern = currPattern
    currPattern = patt
    if currPattern != lastPattern:
      gRedraw = true


  while true:
    let key = getKey()

    case key:
    of keyHome, ord('g'):  setRow(0)
    of keyEnd,  ord('G'):  setRow(ROWS_PER_PATTERN-1)
    of keyUp,   ord('k'):  setRow(max(currRow - 1, 0))
    of keyDown, ord('j'):  setRow(min(currRow + 1, ROWS_PER_PATTERN-1))

    of keyPageUp,   keyCtrlU: setRow(max(currRow - ROW_JUMP, 0))
    of keyPageDown, keyCtrlD: setRow(min(currRow + ROW_JUMP,
                                         ROWS_PER_PATTERN-1))

    of keyLeft,  ord('H'): setPattern(max(currPattern - 1, 0))
    of keyRight, ord('L'): setPattern(min(currPattern + 1,
                                          module.patterns.high))

    of keyF1: setTheme(0)
    of keyF2: setTheme(1)
    of keyF3: setTheme(2)
    of keyF4: setTheme(3)
    of keyF5: setTheme(4)

    of ord('q'):
      closeAudio()
      quit(0)

    else: discard

    let patt = module.songPositions[gPlaybackState.songPos]
    if patt != lastPattern:
      currPattern = patt
      lastPattern = currPattern
      gRedraw = true

    if lastRow != gPlaybackState.currRow:
      currRow = gPlaybackState.currRow
      lastRow = currRow
      gRedraw = true

    if gRedraw:
      setCursorPos(0, 0)
      drawPatternView(module.patterns[currPattern],
                      currRow = currRow, maxRows = gMaxRows,
                      startTrack = 0, maxTracks = 4)
      gRedraw = false

    sleep(1)

main()

