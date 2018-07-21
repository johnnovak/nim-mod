import parseopt, parseutils, strformat

const VERSION = "0.1.0"

type
  Config* = object
    inputFile*:        string
    outputType*:       OutputType
    sampleRate*:       Natural
    bitDepth*:         BitDepth
    ampGain*:          float
    stereoWidth*:      int
    interpolation*:    SampleInterpolation
    declick*:          bool
    outFilename*:      string
    displayUI*:        bool
    refreshRateMs*:    Natural
    showLength*:       bool
    verboseOutput*:    bool

  OutputType* = enum
    otAudio, otWaveWriter

  SampleInterpolation* = enum
    siNearestNeighbour, siLinear

  BitDepth* = enum
    bd16Bit, bd24Bit, bd32BitFloat


proc initConfigWithDefaults(): Config =
  result.outputType       = otAudio
  result.sampleRate       = 44100
  result.bitDepth         = bd16Bit
  result.ampGain          = -6.0
  result.stereoWidth      = 50
  result.interpolation    = siLinear
  result.declick          = true
  result.outFilename      = nil
  result.displayUI        = true
  result.refreshRateMs    = 20
  result.verboseOutput    = false

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
  -a, --ampGain=FLOAT       set the amplifier gain in dB; default is -6.0
  -w, --stereoWidth=INTEGER
                            set the stereo width, must be between
                            -100 and 100; default is 50
                                   0 = mono
                                 100 = full stereo (hard panned channels)
                                -100 = full reverse stereo
  -i, --interpolation=MODE  set the sample interpolation mode; default is 'linear'
                              off    = no interpolation (nearest-neighbour)
                              linear = linear interpolation
  -d, --declick=on|off      turn declicking on or off, on by default
  -f, --outFilename         set the output filename for the file writer
  -u, --userInterface=on|off  turn the UI on or off; on by default
  -r, --refreshRate=INTEGER set the UI refresh rate in ms; 20 ms by default
  -l, --showLength          only print out the estimated non-looped length
                            of the module
  -h, --help                show this help
  -v, --version             show detailed version information
  -V, --verbose             verbose output, for debugging; off by default

"""


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

      of "ampGain", "a":
        if val == "": missingOptValue(opt)
        var g: float
        if parseFloat(val, g) == 0:
          invalidOptValue(opt, val,
            "amplification gain must be a floating point number")
        if g < -36.0 or g > 36.0:
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

      of "interpolation", "i":
        case val:
        of "": missingOptValue(opt)
        of "off": config.interpolation = siNearestNeighbour
        of "linear":  config.interpolation = siLinear
        else:
          invalidOptValue(opt, val,
            "interpolation must be one of 'off' or 'linear'")

      of "declick", "d":
        case val:
        of "": missingOptValue(opt)
        of "on":  config.declick = true
        of "off": config.declick = false
        else:
          invalidOptValue(opt, val, "valid values are 'on' and 'off'")

      of "outFilename", "f":
        config.outFilename = val

      of "userInterface", "u":
        case val:
        of "": missingOptValue(opt)
        of "on":  config.displayUI = true
        of "off": config.displayUI = false
        else:
          invalidOptValue(opt, val, "valid values are 'on' and 'off'")

      of "refreshRate", "r":
        if val == "": missingOptValue(opt)
        var rate: int
        if parseInt(val, rate) == 0:
          invalidOptValue(opt, val, "refresh rate must be a positive integer")
        if rate > 0: config.refreshRateMs = rate
        else:
          invalidOptValue(opt, val, "refresh rate must be a positive integer")

      of "showLength", "l":
        config.showLength = true

      of "help",    "h": printHelp();    quit(0)
      of "version", "v": printVersion(); quit(0)

      of "verbose", "V":
        case val:
        of "": missingOptValue(opt)
        of "on":  config.verboseOutput = true
        of "off": config.verboseOutput = false
        else:
          invalidOptValue(opt, val, "valid values are 'on' and 'off'")

      else: invalidOption(opt)

    of cmdEnd: assert(false)

  if config.inputFile == nil:
    echo "Error: input file must be specified"
    quit(0)

  result = config

