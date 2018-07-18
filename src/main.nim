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
    songlengthSeconds = ceil(estimateSongLengthMillis(ps))
    mins = songlengthSeconds.int div 60
    secs = songlengthSeconds.int mod 60

  echo fmt"Song length: {mins:02}:{secs:02}"


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
  var
    ps = initPlaybackState(config, module)
    buf: array[8192, uint8]
    f: File

  let outfile = config.outFilename

  render(ps, buf[0].addr, buf.len)

  if open(f, config.outFilename, fmWrite):
    var ps = initPlaybackState(config, module)
    try:
      wavewriter.writeHeaders(f, config.sampleRate, sf16Bit, numChannels = 2)
      wavewriter.writeDataStart(format = sf16Bit)

      var bytesWritten = 0
      while not ps.hasSongEnded:
        render(ps, buf[0].addr, buf.len)
        writeData16Bit(f, buf, buf.len)
        inc(bytesWritten, buf.len)
        echo bytesWritten

      f.close()
    except:
      let ex = getCurrentException()
      echo fmt"Error writing output file '{outfile}': " & ex.msg
      echo getStackTrace(ex)
      quit(1)
  else:
    echo fmt"Error opening output file '{outfile}' for writing"
    quit(1)


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
    of otAudio:      startPlayer(config, module)
    of otWaveWriter: writeWaveFile(config, module)

main()

