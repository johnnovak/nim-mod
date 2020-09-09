import strformat, strutils

include periodtable

const
  SongTitleLen*           = 20
  SampleNameLen*          = 22
  MaxSamples*             = 31
  NumSamplesSoundTracker* = 15
  NumSongPositions*       = 128
  RowsPerPattern*         = 64
  MaxPatterns*            = 128

  NumSemitones*    = 12

  MinSampleRepLen* = 2

  AmigaNumOctaves* = 3
  AmigaNumNotes*   = AmigaNumOctaves * NumSemitones
  AmigaNoteMin*    = 0
  AmigaNoteMax*    = AmigaNumNotes - 1

  ExtNumOctaves*   = 8
  ExtNumNotes*     = ExtNumOctaves * NumSemitones
  ExtNoteMin*      = 0
  ExtNoteMax*      = ExtNumNotes - 1
  ExtNoteMinAmiga* = 3 * NumSemitones
  ExtNoteMaxAmiga* = ExtNoteMinAmiga + AmigaNumNotes - 1

  NoteNone* = -1


type
  Module* = ref object
    moduleType*:     ModuleType
    numChannels*:    Natural
    songName*:       string
    songLength*:     Natural
    songRestartPos*: Natural
    songPositions*:  array[NumSongPositions, Natural]
    samples*:        array[1..MaxSamples, Sample]
    numSamples*:     Natural
    patterns*:       seq[Pattern]
    useAmigaLimits*: bool

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

  Pattern* = object
    tracks*: seq[Track]

  Track* = object
    rows*: array[RowsPerPattern, Cell]

  Cell* = object
    note*:      int
    sampleNum*: Natural
    effect*:    int


proc initPattern*(): Pattern =
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
  if note == NoteNone:
   return "---"

  case note mod NumSemitones:
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
  result &= $(note div NumSemitones + 1)


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
  const RepeatLengthMin = 3
  result = s.repeatLength >= RepeatLengthMin

proc noteWithinAmigaLimits*(note: int): bool =
  if note == NoteNone:
    result = true
  else:
    result = note >= ExtNoteMinAmiga and note <= ExtNoteMaxAmiga

proc signedFinetune*(s: Sample): int =
  result = s.finetune
  if result > 7: dec(result, 16)


proc `$`*(c: Cell): string =
  let
    s1 = (c.sampleNum and 0xf0) shr 4
    s2 =  c.sampleNum and 0x0f

  result = noteToStr(c.note) & " " &
           nibbleToChar(s1.int) & nibbleToChar(s2.int) & " " &
           effectToStr(c.effect.int)


proc `$`*(p: Pattern): string =
  for row in 0..<RowsPerPattern:
    result &= align($row, 2, '0') & " | "

    for track in p.tracks:
      result &= $track.rows[row] & " | "
    result &= "\n"


proc `$`*(s: Sample): string =
  # convert signed nibble to signed int
  result = fmt"name: '{s.name}', " &
           fmt"length: {s.length}, " &
           fmt"finetune: {s.signedFinetune()}, " &
           fmt"volume: {s.volume}, " &
           fmt"repeatOffset: {s.repeatOffset}, " &
           fmt"repeatLength: {s.repeatLength}"


proc `$`*(m: Module): string =
  result = fmt"moduleType: {m.moduleType}" &
           fmt"numChannels: {m.numChannels}" &
           fmt"songName: {m.songName}" &
           fmt"songLength: {m.songLength}" &
           fmt"songPositions: {m.songPositions.len} entries"

