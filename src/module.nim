import strutils

include periodtable

const
  NUM_NOTES*     = 36
  NUM_SEMITONES* = 12
  NOTE_NONE*     = -1
  NOTE_MIN*      =  0
  NOTE_MAX*      = NUM_NOTES - 1
  FINETUNE_PAD*  = 37

const
  MAX_SONG_TITLE_LEN*  = 20
  MAX_SAMPLE_NAME_LEN* = 22
  MAX_SAMPLES*         = 31
  MAX_PATTERNS*        = 128
  ROWS_PER_PATTERN*    = 64

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

type
  SampleData* {.unchecked.} = array[1, int8]
  SampleDataPtr* = ptr SampleData

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
  songName*:      string
  songLength*:    int
  songPositions*: array[MAX_PATTERNS, int]
  samples*:       array[1..MAX_SAMPLES, Sample]
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


proc nibbleToChar*(n: int): char =
  assert n >= 0 and n <= 15
  if n < 10:
    result = char(ord('0') + n)
  else:
    result = char(ord('A') + n - 10)


proc noteToStr*(note: int): string =
  if note == NOTE_NONE:
   return "---"

  result = ""
  case note mod NUM_SEMITONES:
  of  0: result = "C-"
  of  1: result = "C#"
  of  2: result = "D-"
  of  3: result = "D#"
  of  4: result = "E-"
  of  5: result = "F-"
  of  6: result = "F#"
  of  7: result = "G-"
  of  8: result = "G#"
  of  9: result = "A-"
  of 10: result = "A#"
  of 11: result = "B-"
  else: discard
  result &= $(note div NUM_SEMITONES + 1)


proc effectToStr*(effect: int): string =
  let
    cmd = (effect and 0xf00) shr 8
    x   = (effect and 0x0f0) shr 4
    y   =  effect and 0x00f

  result = nibbleToChar(cmd) &
           nibbleToChar(x) &
           nibbleToChar(y)


proc `$`*(c: Cell): string =
  let
    s1 = (c.sampleNum and 0xf0) shr 4
    s2 =  c.sampleNum and 0x0f

  result = noteToStr(c.note) & " " &
           nibbleToChar(s1.int) & nibbleToChar(s2.int) & " " &
           effectToStr(c.effect.int)


proc `$`*(p: Pattern): string =
  result = ""
  for row in 0..<ROWS_PER_PATTERN:
    result &= align($row, 2, '0') & " | "

    for track in p.tracks:
      result &= $track.rows[row] & " | "
    result &= "\n"


proc `$`*(s: Sample): string =
  result =   "name:         " & $s.name &
           "\nlength:       " & $s.length &
           "\nfinetune:     " & $s.finetune &
           "\nvolume:       " & $s.volume &
           "\nrepeatOffset: " & $s.repeatOffset &
           "\nrepeatLength: " & $s.repeatLength


proc `$`*(m: Module): string =
  result =   "moduleType:  " & $m.moduleType &
           "\nnumChannels: " & $m.numChannels &
           "\nsongName:    " & $m.songName &
           "\nsongLength:  " & $m.songLength &
           "\nsongPositions:"

  for pos, pattNum in m.songPositions.pairs:
    result &= "\n  " & align($pos, 3) & " -> " & align($pattNum, 3)

