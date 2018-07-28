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
    lengthFractSeconds = precalcSongPosCacheAndSongLength(ps) / ps.config.sampleRate
    (lengthSeconds, millis) = splitDecimal(lengthFractSeconds)
    mins = lengthSeconds.int div 60
    secs = lengthSeconds.int mod 60
    ms = round(millis * 1000).int

  echo fmt"Song length: {mins:02}:{secs:02}.{ms:03}"


var displayUI = false

proc playerQuitProc() {.noconv.} =
  consoleDeinit()
  if displayUI:
    exitFullscreen()
    showCursor()
  discard audio.closeAudio()

proc startPlayer(config: Config, module: Module) =
  var ps = initPlaybackState(config, module)
  discard ps.precalcSongPosCacheAndSongLength()

  proc audioCallback(buf: pointer, bufLen: Natural) =
    render(ps, buf, bufLen)

  # Init audio stuff
  if not audio.initAudio(config, audioCallback):
    error(audio.getLastError())
    quit(QuitFailure)

  if not audio.startPlayback():
    error(audio.getLastError())
    quit(QuitFailure)

  system.addQuitProc(playerQuitProc)

  consoleInit()

  if config.displayUI:
    displayUI = true
    enterFullscreen()
    hideCursor()

  var
    currPattern = 0
    currRow = 0
    lastPattern = -1
    lastRow = -1

  proc toggleMuteChannel(chNum: Natural) =
    if chNum <= ps.channels.high:
      if ps.channels[chNum].state == csMuted:
        ps.channels[chNum].state = csPlaying
      else:
        ps.channels[chNum].state = csMuted

  proc unmuteAllChannels() =
    for chNum in 0..ps.channels.high:
      ps.channels[chNum].state = csPlaying


  while true:
    let key = getKey()
    case key:
    of Key.V:
      if   currView() == vtPattern: setCurrView(vtSamples)
      elif currView() == vtSamples: setCurrView(vtPattern)

    of Key.J:
      if currView() == vtSamples: scrollSamplesViewDown()

    of Key.K:
      if currView() == vtSamples: scrollSamplesViewUp()

    of Key.Space:
      ps.paused = not ps.paused

    of Key.Left, Key.H:
      ps.nextSongPos = max(0, ps.currSongPos-1)

    of Key.ShiftH:
      ps.nextSongPos = max(0, ps.currSongPos-10)

    of Key.Right, Key.L:
      ps.nextSongPos = min(module.songLength-1, ps.currSongPos+1)

    of Key.ShiftL:
      ps.nextSongPos = min(module.songLength-1, ps.currSongPos+10)

    of Key.G:      ps.nextSongPos = 0
    of Key.ShiftG: ps.nextSongPos = module.songLength-1

    of Key.F1: setTheme(0)
    of Key.F2: setTheme(1)
    of Key.F3: setTheme(2)
    of Key.F4: setTheme(3)
    of Key.F5: setTheme(4)
    of Key.F6: setTheme(5)
    of Key.F7: setTheme(6)

    of Key.One:   toggleMuteChannel(0)
    of Key.Two:   toggleMuteChannel(1)
    of Key.Three: toggleMuteChannel(2)
    of Key.Four:  toggleMuteChannel(3)
    of Key.Five:  toggleMuteChannel(4)
    of Key.Six:   toggleMuteChannel(5)
    of Key.Seven: toggleMuteChannel(6)
    of Key.Eight: toggleMuteChannel(7)
    of Key.Nine:  toggleMuteChannel(8)
    of Key.Zero:  toggleMuteChannel(9)

    of Key.U:     unmuteAllChannels()

    of Key.Tab:   nextTrackPage()

    of Key.Comma: ps.config.ampGain = max(-24.0, ps.config.ampGain - 0.5)
    of Key.Dot:   ps.config.ampGain = min( 24.0, ps.config.ampGain + 0.5)

    of Key.LeftBracket:
      ps.config.stereoWidth = max(-100, ps.config.stereoWidth - 10)

    of Key.RightBracket:
      ps.config.stereoWidth = min( 100, ps.config.stereoWidth + 10)

    of Key.I:
      var r = ps.config.resampler
      if r == Resampler.high:
        r = Resampler.low
      else:
        inc(r)
      ps.config.resampler = r

    of Key.Q: quit(QuitSuccess)

    of Key.R:
      consoleInit()
      enterFullscreen()
      hideCursor()
      updateScreen(ps, forceRedraw = true)

    else: discard

    if config.displayUI:
      updateScreen(ps)

    sleep(config.refreshRateMs)


proc writeWaveFile(config: Config, module: Module) =
  const
    BUFLEN_SAMPLES = 4096
    NUM_CHANNELS = 2

  var ps = initPlaybackState(config, module)
  var framesToWrite = precalcSongPosCacheAndSongLength(ps)
  debug(fmt"framesToWrite: {framesToWrite}")

  var
    sampleFormat: SampleFormat
    buf: seq[uint8]
    bytesToWrite: Natural

  case config.bitDepth
  of bd16Bit:
    sampleFormat = sf16Bit
    newSeq(buf, BUFLEN_SAMPLES * 2)
    bytesToWrite = framesToWrite * NUM_CHANNELS * 2
  of bd24Bit:
    sampleFormat = sf24Bit
    newSeq(buf, BUFLEN_SAMPLES * 3)
    bytesToWrite = framesToWrite * NUM_CHANNELS * 3
  of bd32BitFloat:
    sampleFormat = sf32BitFloat
    newSeq(buf, BUFLEN_SAMPLES * 4)
    bytesToWrite = framesToWrite * NUM_CHANNELS * 4

  var ww = initWaveWriter(
    config.outFilename, sampleFormat, config.sampleRate, NUM_CHANNELS)

  ww.writeHeaders()

  debug(fmt"bytesToWrite: {bytesToWrite}")

  while bytesToWrite > 0:
    let numBytes = min(bytesToWrite, buf.len)
    render(ps, buf[0].addr, numBytes)
    ww.writeData(buf, numBytes)
    dec(bytesToWrite, numBytes)

  ww.updateHeaders()
  ww.close()


proc main() =
  var logger = newConsoleLogger(fmtStr = "")
  addHandler(logger)
  setLogFilter(lvlNotice)

  var config = parseCommandLine()

  if config.verboseOutput:
    setLogFilter(lvlDebug)
  elif config.suppressWarnings:
    setLogFilter(lvlError)

  # Load module
  var module: Module
  try:
    module = readModule(config.inputFile)
  except:
    let ex = getCurrentException()
    error("Error loading module: " & ex.msg)
    when not defined(release):
      error(getStackTrace(ex))
    quit(QuitFailure)

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
        error(fmt"Error writing output file '{config.outFilename}': " & ex.msg)
        when not defined(release):
          error(getStackTrace(ex))
        quit(QuitFailure)


main()

