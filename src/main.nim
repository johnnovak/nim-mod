import logging, math, os, strformat, strutils

import illwill

# import audio/fmoddriver as audio
import audio/soundiodriver as audio
import config
import display
import loader
import module
import renderer
import easywave


proc showLength(config: Config, module: Module) =
  var ps = initPlaybackState(config, module)
  let
    (lenFrames, restartType, restartPos) = precalcSongPosCacheAndSongLength(ps)
    lenFractSeconds = lenFrames / ps.config.sampleRate
    (lenSecs, millis) = splitDecimal(lenFractSeconds)
    mins = lenSecs.int div 60
    secs = lenSecs.int mod 60
    ms = round(millis * 1000).int
    lengthStr = fmt"{mins:02}:{secs:02}.{ms:03}"

  case restartType
  of srNoRestart:
    echo fmt"Song length: {lengthStr}"

  of srNormalRestart:
    echo fmt"Song length:  {lengthStr} (non-looped)"
    echo fmt"Restart type: {restartType}"

  of srSongRestartPos, srPositionJump:
    echo fmt"Song length:     {lengthStr} (non-looped)"
    echo fmt"Restart type:    {restartType}"
    echo fmt"Restart songpos: {restartPos}"


proc playerQuitProc() {.noconv.} =
  illwillDeinit()
  discard audio.closeAudio()

proc startPlayer(config: Config, module: Module) =
  var ps = initPlaybackState(config, module)
  discard ps.precalcSongPosCacheAndSongLength()
  ps.setStartPos(config.startPos, config.startRow)

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


  if config.displayUI:
    illwillInit(fullscreen = true)
    hideCursor()
    setTheme(config.theme)
  else:
    illwillInit(fullscreen = false)

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
    of Key.QuestionMark: toggleHelpView()

    of Key.Escape:
      if currView() == vtHelp: toggleHelpView()

    of Key.V:
      case currView()
      of vtPattern: setCurrView(vtSamples)
      of vtSamples: setCurrView(vtPattern)
      of vtHelp:    discard

    of Key.Up, Key.K:
      case currView()
      of vtPattern: discard
      of vtSamples: scrollSamplesViewUp()
      of vtHelp:    scrollHelpViewUp()

    of Key.Down, Key.J:
      case currView()
      of vtPattern: discard
      of vtSamples: scrollSamplesViewDown()
      of vtHelp:    scrollHelpViewDown()

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
      if config.displayUI:
        illwillInit(fullscreen = true)
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
  var (framesToWrite, _, _) = precalcSongPosCacheAndSongLength(ps)
  debug(fmt"framesToWrite: {framesToWrite}")

  var
    sampleFormat: SampleFormat
    buf: seq[uint8]
    bytesToWrite: Natural

  case config.bitDepth
  of bd16Bit:
    sampleFormat = sf16BitInteger
    newSeq(buf, BUFLEN_SAMPLES * 2)
    bytesToWrite = framesToWrite * NUM_CHANNELS * 2
  of bd24Bit:
    sampleFormat = sf24BitInteger
    newSeq(buf, BUFLEN_SAMPLES * 3)
    bytesToWrite = framesToWrite * NUM_CHANNELS * 3
  of bd32BitFloat:
    sampleFormat = sf32BitFloat
    newSeq(buf, BUFLEN_SAMPLES * 4)
    bytesToWrite = framesToWrite * NUM_CHANNELS * 4

  var ww = writeWaveFile(
    config.outFilename, sampleFormat, config.sampleRate, NUM_CHANNELS)

  ww.writeFormatChunk()
  ww.startDataChunk()

  debug(fmt"bytesToWrite: {bytesToWrite}")

  while bytesToWrite > 0:
    let numBytes = min(bytesToWrite, buf.len)
    render(ps, buf[0].addr, numBytes)

    case config.bitDepth
    of bd16Bit:      ww.writeData16(buf[0].addr, numBytes)
    of bd24Bit:      ww.writeData24Packed(buf[0].addr, numBytes)
    of bd32BitFloat: ww.writeData32(buf[0].addr, numBytes)

    dec(bytesToWrite, numBytes)

  ww.endChunk()
  ww.endFile()


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
    of otAudio, otOff:
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

