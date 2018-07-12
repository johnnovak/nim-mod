import parseopt2, parseutils, strformat

const VERSION = "0.1.0"

type
  Config* = object
    inputFile*:        string
    outputType*:       OutputType
    sampleRate*:       Natural
    bitDepth*:         BitDepth
    ampGain*:          float
    stereoSeparation*: float
    interpolation*:    SampleInterpolation
    declick*:          bool
    outFilename*:      string
    displayUI*:        bool

  OutputType* = enum
    otAudio, otFile

  SampleInterpolation* = enum
    siNearestNeighbour, siLinear, siSinc

  BitDepth* = enum
    bd16Bit, bd24Bit, bd32BitFloat


proc initConfigWithDefaults(): Config =
  result.outputType       = otAudio
  result.sampleRate       = 44100
  result.bitDepth         = bd16Bit
  result.ampGain          = -6.0
  result.stereoSeparation = 70
  result.interpolation    = siLinear
  result.declick          = true
  result.outFilename      = nil
  result.displayUI        = true

proc printVersion() =
  echo "nim-mod version " & VERSION
  echo "Copyright (c) 2016-2018 by John Novak"


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
  -d, --declick=on|off      turns declicking on or off, on by default
  -o, --outFilename         set the output filename for the file writer
  -u, --userInterface=on|off  turns the UI on or off; on by default
  -h, --help                show this help
  -v, --version             show detailed version information

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
        of "file":  config.outputType = otFile
        else:
          invalidOptValue(opt, val,
            "output type must be either 'audio' or 'file'")

      of "sampleRate", "s":
        if val == "": missingOptValue(opt)
        var sr: int
        if parseInt(val, sr) == 0:
          invalidOptValue(opt, val,
            "sample rate must be a positive integer")
        if sr > 0: config.sampleRate = sr
        else:
          invalidOptValue(opt, val,
            "sample rate must be a positive integer")

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

      of "stereoSeparation", "p":
        if val == "": missingOptValue(opt)
        var sep: int
        if parseInt(val, sep) == 0:
          invalidOptValue(opt, val, "invalid stereo separation value")
        if sep < -100 or sep > 100:
          invalidOptValue(opt, val, "stereo separation must be between -100 and 100")

      of "interpolation", "i":
        case val:
        of "": missingOptValue(opt)
        of "nearest": config.interpolation = siNearestNeighbour
        of "linear":  config.interpolation = siLinear
        of "sinc":    config.interpolation = siSinc
        else:
          invalidOptValue(opt, val,
            "interpolation must be one of 'nearest', 'linear' or 'sinc'")

      of "declick", "d":
        case val:
        of "": missingOptValue(opt)
        of "on":  config.declick = true
        of "off": config.declick = false
        else:
          invalidOptValue(opt, val, "valid values are 'on' and 'off'")

      of "userInterface", "u":
        case val:
        of "": missingOptValue(opt)
        of "on":  config.displayUI = true
        of "off": config.displayUI = false
        else:
          invalidOptValue(opt, val, "valid values are 'on' and 'off'")

      of "outFilename", "f":
        config.outFilename = val

      of "help",    "h": printHelp();    quit(0)
      of "version", "v": printVersion(); quit(0)

      else: invalidOption(opt)

    of cmdEnd: assert(false)

  if config.inputFile == "":
    echo "Error: input file must be specified"
    quit(0)

  result = config

