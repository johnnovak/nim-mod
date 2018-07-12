import logging, os, strformat, strutils

import illwill

import audio/fmoddriver as audio
import config
import module
import loader
import player
import display


var
  gPlaybackState: PlaybackState
  gDisplayUI: bool


proc audioCb(samples: AudioBufferPtr, numFrames: Natural) =
  render(gPlaybackState, samples, numFrames)


proc quitProc() {.noconv.} =
  if gDisplayUI:
    resetAttributes()
    consoleDeinit()
    exitFullscreen()
    showCursor()
  discard audio.closeAudio()


proc main() =
  var logger = newConsoleLogger()
  addHandler(logger)

  var config = parseCommandLine()

  # Load module
  var module: Module
  try:
    module = readModule(config.inputFile)
  except:
    let ex = getCurrentException()
    echo "Error loading module: " & ex.msg
    echo getStackTrace(ex)
    quit(1)

  gPlaybackState = initPlaybackState(config, module)

  # Init audio stuff
  if not audio.initAudio(audioCb):
    echo audio.getLastError()
    quit(1)

  if not audio.startPlayback():
    echo audio.getLastError()
    quit(1)

  system.addQuitProc(quitProc)

  consoleInit()

  if config.displayUI:
    gDisplayUI = true
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

  proc setPattern(patt: Natural) =
    lastPattern = currPattern
    currPattern = patt

  proc toggleMuteChannel(chNum: Natural) =
    if chNum <= gPlaybackState.channelState.high:
      if gPlaybackState.channelState[chNum] == csMuted:
        gPlaybackState.channelState[chNum] = csPlaying
      else:
        gPlaybackState.channelState[chNum] = csMuted

  while true:
    let key = getKey()

    case key:
    of keyLeft, ord('h'):
      gPlaybackState.nextSongPos = max(0, gPlaybackState.currSongPos-1)

    of ord('H'):
      gPlaybackState.nextSongPos = max(0, gPlaybackState.currSongPos-10)

    of keyRight, ord('l'):
      gPlaybackState.nextSongPos = min(module.songLength-1,
                                       gPlaybackState.currSongPos+1)

    of ord('L'):
      gPlaybackState.nextSongPos = min(module.songLength-1,
                                       gPlaybackState.currSongPos+10)

    of keyF1: setTheme(0)
    of keyF2: setTheme(1)
    of keyF3: setTheme(2)
    of keyF4: setTheme(3)
    of keyF5: setTheme(4)

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

    if config.displayUI:
      updateScreen(gPlaybackState)

    sleep(20)


main()

