import logging, parseopt, parseutils, strformat

const VERSION = "0.1.0"

type
  Config* = object
    inputFile*:        string
    outputType*:       OutputType
    sampleRate*:       Natural
    bitDepth*:         BitDepth
    bufferSize*:       Natural
    noSoundOutput*:    bool
    ampGain*:          float
    stereoWidth*:      int
    resampler*:        Resampler
    outFilename*:      string
    displayUI*:        bool
    refreshRateMs*:    Natural
    showLength*:       bool
    verboseOutput*:    bool
    suppressWarnings*: bool

  OutputType* = enum
    otAudio, otWaveWriter

  Resampler* = enum
    rsNearestNeighbour, rsLinear

  BitDepth* = enum
    bd16Bit, bd24Bit, bd32BitFloat


proc initConfigWithDefaults(): Config =
  result.outputType       = otAudio
  result.sampleRate       = 44100
  result.bitDepth         = bd16Bit
  result.bufferSize       = 2048
  result.noSoundOutput    = false
  result.ampGain          = -6.0
  result.stereoWidth      = 50
  result.resampler        = rsLinear
  result.outFilename      = ""
  result.displayUI        = true
  result.refreshRateMs    = 20
  result.verboseOutput    = false
  result.suppressWarnings = false

proc printVersion() =
  echo "nim-mod version " & VERSION
  echo "Copyright (c) 2016-2018 by John Novak"


proc printHelp() =
  printVersion()
  echo """
Usage: nim-mod [OPTIONS] FILENAME

Options:
  -o, --output=audio|wav    select output to use; default is 'audio'
                              audio = normal audio output
                              wav   = write output to a WAV file
  -s, --sampleRate=INTEGER  set the sample rate; default is 44100
  -b, --bitDepth=16|24|32   set the output bit depth, 32 stands for 32-bit
                            floating point; default is 16
  -B, --bufferSize=INTEGER  size of the audio buffer in bytes; default is 2048
  -N, --noSoundOutput       disable sound output
  -a, --ampGain=FLOAT       set the amplifier gain in dB; default is -6.0 dB
  -w, --stereoWidth=INTEGER
                            set the stereo width, must be between
                            -100 and 100; default is 50
                                   0 = mono
                                 100 = full stereo (hard panned channels)
                                -100 = full reverse stereo
  -r, --resampler=MODE      set the resampling mode; default is 'linear'
                              off    = nearest-neighbour (no interpolation)
                              linear = linear interpolation
  -f, --outFilename         set the output filename for the file writer
  -U, --noUserInterface     disable the user interface
  -R, --refreshRate=INTEGER set the UI refresh rate in ms; 20 ms by default
  -l, --showLength          print the non-looped song length and exit
  -h, --help                show this help
  -v, --version             show detailed version information
  -V, --verbose             verbose output, for debugging
  -q, --quiet               suppress warnings

"""


proc invalidOptValue(opt: string, val: string, msg: string) {.noconv.} =
  echo fmt"Error: value '{val}' for option -{opt} is invalid:"
  echo fmt"    {msg}"
  quit(QuitFailure)

proc missingOptValue(opt: string) {.noconv.} =
  echo fmt"Error: option -{opt} requires a parameter"
  quit(QuitFailure)

proc invalidOption(opt: string) {.noconv.} =
  echo fmt"Error: option -{opt} is invalid"
  quit(QuitFailure)


proc parseCommandLine*(): Config =
  var
    config = initConfigWithDefaults()
    optParser = initOptParser()

  for kind, opt, val in optParser.getopt():
    case kind
    of cmdArgument:
      config.inputFile = opt

    of cmdLongOption, cmdShortOption:
      case opt
      of "output", "o":
        case val
        of "": missingOptValue(opt)
        of "audio": config.outputType = otAudio
        of "wav":   config.outputType = otWaveWriter
        else:
          invalidOptValue(opt, val,
            "output type must be either 'audio' or 'wav'")

      of "sampleRate", "s":
        if val == "": missingOptValue(opt)
        var sr: int
        if parseInt(val, sr) == 0:
          invalidOptValue(opt, val, "sample rate must be a positive integer")
        if sr > 0: config.sampleRate = sr
        else:
          invalidOptValue(opt, val, "sample rate must be a positive integer")

      of "bitDepth", "b":
        case val
        of "": missingOptValue(opt)
        of "16": config.bitDepth = bd16Bit
        of "24": config.bitDepth = bd24Bit
        of "32": config.bitDepth = bd32BitFloat
        else:
          invalidOptValue(opt, val,
            "bit depth must be one of '16', '24 or '32'")

      of "bufferSize", "B":
        if val == "": missingOptValue(opt)
        var s: int
        if parseInt(val, s) == 0:
          invalidOptValue(opt, val, "buffer size must be a positive integer")
        if s > 0: config.bufferSize = s
        else:
          invalidOptValue(opt, val, "buffer size must be a positive integer")

      of "noSoundOutput", "N":
        config.noSoundOutput = true

      of "ampGain", "a":
        if val == "": missingOptValue(opt)
        var g: float
        if parseFloat(val, g) == 0:
          invalidOptValue(opt, val,
            "amplification gain must be a floating point number")
        if g < -24.0 or g > 24.0:
          invalidOptValue(opt, val,
            "amplification gain must be between -36 and +36 dB")
        config.ampGain = g

      of "stereoWidth", "w":
        if val == "": missingOptValue(opt)
        var w: int
        if parseInt(val, w) == 0:
          invalidOptValue(opt, val, "invalid stereo width value")
        if w < -100 or w > 100:
          invalidOptValue(opt, val, "stereo width must be between -100 and 100")
        config.stereoWidth = w

      of "resampler", "r":
        case val:
        of "": missingOptValue(opt)
        of "off": config.resampler = rsNearestNeighbour
        of "linear":  config.resampler = rsLinear
        else:
          invalidOptValue(opt, val,
            "resampler mode must be one of 'off' or 'linear'")

      of "outFilename", "f":
        config.outFilename = val

      of "noUserInterface", "U":
        config.displayUI = false

      of "refreshRate", "R":
        if val == "": missingOptValue(opt)
        var rate: int
        if parseInt(val, rate) == 0:
          invalidOptValue(opt, val, "refresh rate must be a positive integer")
        if rate > 0: config.refreshRateMs = rate
        else:
          invalidOptValue(opt, val, "refresh rate must be a positive integer")

      of "showLength", "l":
        config.showLength = true

      of "help",    "h": printHelp();    quit(QuitSuccess)
      of "version", "v": printVersion(); quit(QuitSuccess)

      of "verbose", "V":
        config.verboseOutput = true

      of "quiet", "q":
        config.suppressWarnings = true

      else: invalidOption(opt)

    of cmdEnd: assert(false)

  if config.inputFile == "":
    error("Error: input file must be specified")
    quit(QuitFailure)

  result = config

