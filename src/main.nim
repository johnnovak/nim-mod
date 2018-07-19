import logging, math, os, strformat, strutils

import illwill

import audio/fmoddriver as audio
import config
import display
import loader
import module
import renderer
import wavewriter


proc showLength(config: Config, module: Module) =
  var ps = initPlaybackState(config, module)
  let
    (lengthSeconds, millis) = splitDecimal(estimateSongLengthInSeconds(ps))
    mins = lengthSeconds.int div 60
    secs = lengthSeconds.int mod 60

  echo fmt"Song length: {mins:02}:{secs:02}.{millis*1000:03}"


var displayUI: bool

proc playerQuitProc() {.noconv.} =
  if displayUI:
    consoleDeinit()
    exitFullscreen()
    showCursor()
  discard audio.closeAudio()

proc startPlayer(config: Config, module: Module) =
  var playbackState = initPlaybackState(config, module)

  proc audioCallback(buf: pointer, bufLen: Natural) =
    render(playbackState, buf, bufLen)

  # Init audio stuff
  if not audio.initAudio(audioCallback):
    echo audio.getLastError()
    quit(1)

  if not audio.startPlayback():
    echo audio.getLastError()
    quit(1)

  system.addQuitProc(playerQuitProc)

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
    if chNum <= playbackState.channels.high:
      if playbackState.channels[chNum].state == csMuted:
        playbackState.channels[chNum].state = csPlaying
      else:
        playbackState.channels[chNum].state = csMuted

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


proc writeWaveFile(config: Config, module: Module) =
  const bufSizeInSamples = 4096
  var
    sampleFormat: SampleFormat
    buf: seq[uint8]

  case config.bitDepth
  of bd16Bit:
    sampleFormat = sf16Bit
    newSeq(buf, bufSizeInSamples * 2)
  of bd24Bit:
    sampleFormat = sf24Bit
    newSeq(buf, bufSizeInSamples * 3)
  of bd32BitFloat:
    sampleFormat = sf32BitFloat
    newSeq(buf, bufSizeInSamples * 4)

  var waveWriter = initWaveWriter(
    config.outFilename, sampleFormat, config.sampleRate, numChannels = 2)

  var playbackState = initPlaybackState(config, module)

  wavewriter.writeHeaders()

  while not playbackState.hasSongEnded:
    render(playbackState, buf[0].addr, buf.len)
    waveWriter.writeData(buf)

  wavewriter.updateHeaders()
  wavewriter.close()


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

  if config.showLength:
    showLength(config, module)
  else:
    case config.outputType
    of otAudio:
      # TODO exception handling?
      startPlayer(config, module)

    of otWaveWriter:
      try:
        writeWaveFile(config, module)
      except:
        let ex = getCurrentException()
        echo fmt"Error writing output file '{config.outFilename}': " & ex.msg
        echo getStackTrace(ex)
        quit(1)


main()

