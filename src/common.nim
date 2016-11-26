const MAX_SONG_TITLE_LEN*  = 20
const MAX_SAMPLE_NAME_LEN* = 22
const MAX_SAMPLES*         = 31
const MAX_PATTERNS*        = 128
const MAX_SAMPLE_SIZE*     = 65536 * 2
const ROWS_PER_PATTERN*    = 64

const TAG_LEN        = 4
const TAG_OFFSET     = 1080
const BYTES_PER_CELL = 4


type ModuleType* = enum
  mtFastTracker,
  mtOctaMED,
  mtOktalyzer,
  mtProtracker,
  mtSoundTracker,
  mtStarTrekker,
  mtTakeTracker

type Cell* = ref object
  note*:      int
  sampleNum*: int
  effect*:    int

type Track* = ref object
  rows*: array[ROWS_PER_PATTERN, Cell]

type Pattern* = ref object
  tracks*: seq[Track]

type SampleDataPtr* = ptr array[MAX_SAMPLE_SIZE, uint8]

type Sample* = ref object
  name*:         string
  length*:       int
  finetune*:     int
  volume*:       int
  repeatOffset*: int
  repeatLength*: int
  data*:         SampleDataPtr

type Module* = ref object
  moduleType*:    ModuleType
  numChannels*:   int
  songTitle*:     string
  songLength*:    int
  songPositions*: array[MAX_PATTERNS, uint8]
  samples*:       array[MAX_SAMPLES, Sample]
  patterns*:      seq[Pattern]


proc newCell*(): Cell =
  result = new Cell

proc newTrack*(): Track =
  result = new Track

proc newPattern*(numChannels: Natural): Pattern =
  result = new Pattern
  newSeq(result.tracks, numChannels)
  for trackNum in 0..<numChannels:
    result.tracks[trackNum] = newTrack()

proc newSample*(): Sample =
  result = new Sample

proc newModule*(): Module =
  result = new Module
  result.patterns = newSeq[Pattern]()


const NOTE_NONE* = -1
const NOTE_C1*   =  0

const periodTable = [
  856, 808, 762, 720, 678, 640, 604, 570, 538, 508, 480, 453,  # C-1 to B-1
  428, 404, 381, 360, 339, 320, 302, 285, 269, 254, 240, 226,  # C-2 to B-2
  214, 202, 190, 180, 170, 160, 151, 143, 135, 127, 120, 113   # C-3 to B-3
]

