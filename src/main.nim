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
    of Key.Left, Key.H:
      playbackState.nextSongPos = max(0, playbackState.currSongPos-1)

    of Key.ShiftH:
      playbackState.nextSongPos = max(0, playbackState.currSongPos-10)

    of Key.Right, Key.L:
      playbackState.nextSongPos = min(module.songLength-1,
                                      playbackState.currSongPos+1)

    of Key.ShiftL:
      playbackState.nextSongPos = min(module.songLength-1,
                                      playbackState.currSongPos+10)

    of Key.F1: setTheme(0)
    of Key.F2: setTheme(1)
    of Key.F3: setTheme(2)
    of Key.F4: setTheme(3)
    of Key.F5: setTheme(4)
    of Key.F6: setTheme(5)

    of Key.One:   toggleMuteChannel(0)
    of Key.Two:   toggleMuteChannel(1)
    of Key.Three: toggleMuteChannel(2)
    of Key.Four:  toggleMuteChannel(3)

    of Key.Q: quit(0)

    of Key.R:
      # TODO do this in a more optimal way
      consoleDeinit()
      exitFullscreen()
      showCursor()

      consoleInit()
      enterFullscreen()
      hideCursor()

    else: discard

    if config.displayUI:
      updateScreen(playbackState)

    sleep(config.refreshRateMs)


main()

