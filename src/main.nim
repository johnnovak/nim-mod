import logging, os, strformat, strutils

import illwill

import audio/fmoddriver as audio
import config
import module
import loader
import player
import display

var
  playbackState: PlaybackState
  displayUI: bool

proc audioCb(samples: AudioBufferPtr, numFrames: Natural) =
  render(playbackState, samples, numFrames)

proc quitProc() {.noconv.} =
  if displayUI:
    consoleDeinit()
    exitFullscreen()
    showCursor()
  discard audio.closeAudio()


proc main() =
  var logger = newConsoleLogger()
  addHandler(logger)
  setLogFilter(lvlNotice)

  var config = parseCommandLine()

  if config.verboseOutput:
    setLogFilter(lvlDebug)

  # Load module
  var module: Module
  try:
    module = readModule(config.inputFile)
  except:
    let ex = getCurrentException()
    echo "Error loading module: " & ex.msg
    echo getStackTrace(ex)
    quit(1)

  playbackState = initPlaybackState(config, module)

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
    displayUI = true
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
    if chNum <= playbackState.channelState.high:
      if playbackState.channelState[chNum] == csMuted:
        playbackState.channelState[chNum] = csPlaying
      else:
        playbackState.channelState[chNum] = csMuted

  while true:
    let key = getKey()

    case key:
    of keyLeft, ord('h'):
      playbackState.nextSongPos = max(0, playbackState.currSongPos-1)

    of ord('H'):
      playbackState.nextSongPos = max(0, playbackState.currSongPos-10)

    of keyRight, ord('l'):
      playbackState.nextSongPos = min(module.songLength-1,
                                      playbackState.currSongPos+1)

    of ord('L'):
      playbackState.nextSongPos = min(module.songLength-1,
                                      playbackState.currSongPos+10)

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
      updateScreen(playbackState)

    sleep(config.refreshRateMs)


main()

