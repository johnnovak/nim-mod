import strformat, strutils

include periodtable

const
  SONG_TITLE_LEN*            = 20
  SAMPLE_NAME_LEN*           = 22
  NUM_SAMPLES*               = 31
  NUM_SAMPLES_SOUNDTRACKER*  = 15
  NUM_SONG_POSITIONS*        = 128
  ROWS_PER_PATTERN*          = 64

  NUM_NOTES*     = 36
  NUM_SEMITONES* = 12
  NOTE_NONE*     = -1
  NOTE_MIN*      =  0
  NOTE_MAX*      = NUM_NOTES - 1

  FINETUNE_PAD*  = 37

type
  Module* = ref object
    moduleType*:     ModuleType
    numChannels*:    Natural
    songName*:       string
    songLength*:     Natural
    songRestartPos*: Natural
    songPositions*:  array[NUM_SONG_POSITIONS, Natural]
    samples*:        array[1..NUM_SAMPLES, Sample]
    patterns*:       seq[Pattern]

  ModuleType* = enum
    mtFastTracker,
    mtOctaMED,
    mtOktalyzer,
    mtProTracker,
    mtSoundTracker,
    mtStarTrekker,
    mtTakeTracker

  Sample* = ref object
    name*:         string
    length*:       Natural
    finetune*:     int
    volume*:       Natural
    repeatOffset*: Natural
    repeatLength*: Natural
    data*:         seq[float32]

  Pattern* = ref object
    tracks*: seq[Track]

  Track* = ref object
    rows*: array[ROWS_PER_PATTERN, Cell]

  Cell* = object
    note*:      int
    sampleNum*: int
    effect*:    int


proc newPattern*(): Pattern =
  result = new Pattern
  result.tracks = newSeq[Track]()

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


proc toString*(mt: ModuleType): string =
  case mt
  of mtFastTracker:  result = "FastTracker"
  of mtOctaMED:      result = "OctaMED"
  of mtOktalyzer:    result = "Oktalyzer"
  of mtProTracker:   result = "ProTracker"
  of mtSoundTracker: result = "SoundTracker"
  of mtStarTrekker:  result = "StarTrekker"
  of mtTakeTracker:  result = "TakeTracker"

proc isLooped*(s: Sample): bool =
  const REPEAT_LENGTH_MIN = 3
  result = s.repeatLength >= REPEAT_LENGTH_MIN


proc `$`*(c: Cell): string =
  let
    s1 = (c.sampleNum and 0xf0) shr 4
    s2 =  c.sampleNum and 0x0f

  result = noteToStr(c.note) & " " &
           nibbleToChar(s1.int) & nibbleToChar(s2.int) & " " &
           effectToStr(c.effect.int)


proc `$`*(p: Pattern): string =
  for row in 0..<ROWS_PER_PATTERN:
    result &= align($row, 2, '0') & " | "

    for track in p.tracks:
      result &= $track.rows[row] & " | "
    result &= "\n"


proc `$`*(s: Sample): string =
  result = fmt"name: '{s.name}'," &
           fmt"length: {s.length}, " &
           fmt"finetune: {s.finetune}, " &
           fmt"volume: {s.volume}, " &
           fmt"repeatOffset: {s.repeatOffset}, " &
           fmt"repeatLength: {s.repeatLength}"


proc `$`*(m: Module): string =
  result = fmt"moduleType: {m.moduleType}" &
           fmt"numChannels: {m.numChannels}" &
           fmt"songName: {m.songName}" &
           fmt"songLength: {m.songLength}" &
           fmt"songPositions: {m.songPositions.len} entries"

