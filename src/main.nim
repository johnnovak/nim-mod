import logging, os, parseopt2, parseutils, strformat, strutils

import illwill

import audio/fmoddriver as audio
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
  gDisplayGUI = true

const ROW_JUMP = 8


proc audioCb(samples: AudioBufferPtr, numFrames: Natural) =
  render(gPlaybackState, samples, numFrames)


proc quitProc() {.noconv.} =
  if gDisplayGUI:
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
  echo """
Usage: nim-mod FILENAME

Options:
  -o, --output=audio|file   select output to use; default is 'audio'
                              audio  = normal audio output
                              file   = write output to a WAV file
  -s, --sampleRate=INTEGER  set the sample rate; default is 44100
  -b, --bitDepth=16|24|32   set the output bit depth; default is 16
  -a, --ampGain=FLOAT       set the amplifier gain in dB; default is 0.0
  -p, --stereoSeparation=INTEGER
                            set the stereo separation, must be between
                            -100 and 100; default is 70
                                   0 = mono
                                 100 = stereo (no crosstalk)
                                -100 = reverse stereo (no crosstalk)
  -i, --interpolation=MODE  set the sample interpolation mode; default is 'sinc'
                              off    = fastest, no interpolation
                              linear = fast, low quality
                              sinc   = slow, high quality
  -o, --outFilename         set the output filename for the file writer
  -h, --help                show this help
  -v, --version             show detailed version information

"""


type
  Config = object
    outputType:       OutputType
    sampleRate:       Natural
    bitDepth:         BitDepth
    ampGain:          float
    stereoSeparation: float
    interpolation:    SampleInterpolation
    declick:          bool
    outFilename:      string

  OutputType = enum
    otAudio, otFile

  SampleInterpolation = enum
    siNearestNeighbour, siLinear, siSinc

  BitDepth = enum
    bd16Bit, bd24Bit, bd32BitFloat


proc invalidOptValue(opt: string, val: string, msg: string) {.noconv.} =
  echo fmt"Error: value '{val}' for option -{opt} is invalid:"
  echo fmt"    {msg}"
  quit(1)

proc missingOptValue(opt: string) {.noconv.} =
  echo fmt"Error: option -{opt} requires a parameter"
  quit(1)

proc invalidOption(opt: string) {.noconv.} =
  echo fmt"Error: option -{opt} is invalid"
  quit(1)

proc main() =
  var logger = newConsoleLogger()
  addHandler(logger)

  # Command line arguments handling
  var infile = ""
  var outfile = ""

  var optParser = initOptParser()
  var config = new Config

  for kind, opt, val in optParser.getopt():
    case kind
    of cmdArgument:
      infile = opt

    of cmdLongOption, cmdShortOption:
      case opt
      of "output", "o":
        case val
        of "": missingOptValue(opt)
        of "audio": config.outputType = otAudio
        of "file":  config.outputType = otFile
        else:
          invalidOptValue(opt, val,
            "output type must be either 'audio' or 'file'")

      of "sampleRate", "s":
        if val == "": missingOptValue(opt)
        var sr: int
        if parseInt(val, sr) == 0:
          invalidOptValue(opt, val,
            fmt"sample rate must be a positive integer")
        if sr > 0: config.sampleRate = sr
        else:
          invalidOptValue(opt, val,
            fmt"sample rate must be a positive integer")

      of "bitDepth", "b":
        case val
        of "": missingOptValue(opt)
        of "16": config.bitDepth = bd16Bit
        of "24": config.bitDepth = bd24Bit
        of "32": config.bitDepth = bd32BitFloat
        else:
          invalidOptValue(opt, val,
            fmt"bit depth must be one of '16', '24 or '32'")

      of "ampGain", "a":
        if val == "": missingOptValue(opt)
        var g: float
        if parseFloat(val, g) == 0:
          invalidOptValue(opt, val,
            fmt"amplification gain must be a floating point number")
        if g < -36.0 or g > 36.0:
          invalidOptValue(opt, val,
            fmt"amplification gain must be between -36 and +36 dB")
        config.ampGain = g

      of "stereoSeparation", "p":
        if val == "": missingOptValue(opt)
        var sep: int
        if parseInt(val, sep) == 0:
          invalidOptValue(opt, val,
                          fmt"invalid stereo separation value: {sep}")
        if sep < -100 or sep > 100:
          invalidOptValue(opt, val,
                          fmt"stereo separation must be between -100 and 100")

      of "interpolation", "i":
        case val:
        of "": missingOptValue(opt)
        of "nearest": config.interpolation = siNearestNeighbour
        of "linear":  config.interpolation = siLinear
        of "sinc":    config.interpolation = siSinc
        else:
          invalidOptValue(opt, val,
            fmt"interpolation must be one of 'nearest', 'linear' or 'sinc'")

#      of "declick", "d":

      of "outFilename", "f":
        config.outFilename = val

      of "help",    "h": printHelp();    quit(0)
      of "version", "v": printVersion(); quit(0)

      else: invalidOption(opt)

    of cmdEnd: assert(false)

  if infile == "":
    printHelp()
    quit(0)

  # Load module
  var module: Module
  try:
    module = readModule(infile)
  except:
    let ex = getCurrentException()
    echo "Error loading module: " & ex.msg
    echo getStackTrace(ex)
    quit(1)

  initPlaybackState(gPlaybackState, gSampleRate, module)

  # Init audio stuff
  if not audio.initAudio(audioCb):
    echo audio.getLastError()
    quit(1)

  if not audio.startPlayback():
    echo audio.getLastError()
    quit(1)

  system.addQuitProc(quitProc)

  consoleInit()

#  gDisplayGUI = false

  if gDisplayGUI:
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
      # TODO
#    of keyHome, ord('g'):  setRow(0)
#    of keyEnd,  ord('G'):  setRow(ROWS_PER_PATTERN-1)
#    of keyUp,   ord('k'):  setRow(max(currRow - 1, 0))
#    of keyDown, ord('j'):  setRow(min(currRow + 1, ROWS_PER_PATTERN-1))

#    of keyPageUp,   keyCtrlU: setRow(max(currRow - ROW_JUMP, 0))
#    of keyPageDown, keyCtrlD: setRow(min(currRow + ROW_JUMP,
#                                         ROWS_PER_PATTERN-1))

#    of keyLeft,  ord('H'): setPattern(max(currPattern - 1, 0))
#    of keyRight, ord('L'): setPattern(min(currPattern + 1,
#                                          module.patterns.high))
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

    if gDisplayGUI:
      updateScreen(gPlaybackState)

    sleep(20)


main()

