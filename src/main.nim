import parseopt, os, strutils

import illwill/illwill

import audio/fmod/fmoddriver as audio
import module
import loader
import player
import display


const VERSION = "0.1.0"

var
  gRedraw = true
  gMaxRows = 32
  gPlaybackState: PlaybackState
  gSampleRate = 44100

const ROW_JUMP = 8


proc audioCb(samples: AudioBufferPtr, numFrames: Natural) =
  render(gPlaybackState, samples, numFrames)


proc quitProc() {.noconv.} =
  resetAttributes()
  consoleDeinit()
  exitFullscreen()
  showCursor()
  discard audio.closeAudio()


proc printVersion() =
  echo "nim-mod version " & VERSION
  echo "Copyright (c) 2016 by John Novak"

proc printHelp() =
  printVersion()
  echo "\nUsage: nim-mod FILENAME"


proc main() =
  # Command line arguments handling
  var filename = ""

  for kind, key, val in getopt():
    case kind:
    of cmdArgument:
      filename = key
    of cmdLongOption, cmdShortOption:
      case key:
      of "help",    "h": printHelp();    quit(0)
      of "version", "v": printVersion(); quit(0)
    of cmdEnd: assert(false)

  if filename == "":
    printHelp()
    quit(0)

  # Load module
  var module: Module
  try:
    module = loadModule(filename)
  except:
    echo "Error loading module: " & getCurrentExceptionMsg()
    quit(1)

  initPlaybackState(gPlaybackState, gSampleRate, module)

  # Init audio stuff
  if not audio.initAudio(audioCb):
    echo audio.getLastError()
    quit(1)

  if not audio.startPlayback():
    echo audio.getLastError()
    quit(1)

  # Init console
  system.addQuitProc(quitProc)

  consoleInit()
  enterFullscreen()
  hideCursor()

  let (w, h) = terminalSize()

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

  proc toggleMuteChannel(chNum: Natural) =
    if chNum <= gPlaybackState.channelState.high:
      if gPlaybackState.channelState[chNum] == csMuted:
        gPlaybackState.channelState[chNum] = csPlaying
      else:
        gPlaybackState.channelState[chNum] = csMuted

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

#    of keyLeft,  ord('H'): setPattern(max(currPattern - 1, 0))
#    of keyRight, ord('L'): setPattern(min(currPattern + 1,
#                                          module.patterns.high))
    of keyLeft,  ord('H'):
      gPlaybackState.nextSongPos = max(0, gPlaybackState.songPos - 1)

    of keyRight, ord('L'):
      gPlaybackState.nextSongPos = min(module.songLength - 1,
                                       gPlaybackState.songPos + 1)

    of keyF1: setTheme(0); gRedraw = true
    of keyF2: setTheme(1); gRedraw = true
    of keyF3: setTheme(2); gRedraw = true
    of keyF4: setTheme(3); gRedraw = true
    of keyF5: setTheme(4); gRedraw = true

    of ord('1'): toggleMuteChannel(0)
    of ord('2'): toggleMuteChannel(1)
    of ord('3'): toggleMuteChannel(2)
    of ord('4'): toggleMuteChannel(3)

    of ord('r'):
      # TODO do this in a more optimal way
      resetAttributes()
      consoleDeinit()
      exitFullscreen()
      showCursor()

      consoleInit()
      enterFullscreen()
      hideCursor()

    of ord('q'):
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
      drawPlaybackState(gPlaybackState)
      setCursorPos(0, 5)
      drawPatternView(module.patterns[currPattern],
                      currRow = currRow, maxRows = gMaxRows,
                      startTrack = 0, maxTracks = 4)
      gRedraw = false

    sleep(10)


main()

