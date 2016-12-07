const MAX_SONG_TITLE_LEN*  = 20
const MAX_SAMPLE_NAME_LEN* = 22
const MAX_SAMPLES*         = 31
const MAX_PATTERNS*        = 128
const MAX_SAMPLE_SIZE*     = 65535 * 2
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
  songTitle*:     string
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


const
  NUM_NOTES* = 36
  NOTE_NONE* = -1
  NOTE_MIN*  =  0
  NOTE_MAX*  = NUM_NOTES - 1

const vibratoTable = [
    0,  24,  49,  74,  97, 120, 141, 161,
  180, 197, 212, 224, 235, 244, 250, 253,
  255, 253, 250, 244, 235, 224, 212, 197,
  180, 161, 141, 120,  97,  74,  49,  24
]

const periodTable = [
  # Tuning 0, Normal
  856, 808, 762, 720, 678, 640, 604, 570, 538, 508, 480, 453, # C-1 to B-1
  428, 404, 381, 360, 339, 320, 302, 285, 269, 254, 240, 226, # C-2 to B-2
  214, 202, 190, 180, 170, 160, 151, 143, 135, 127, 120, 113, # C-3 to B-3
  # Tuning 1
  850, 802, 757, 715, 674, 637, 601, 567, 535, 505, 477, 450,
  425, 401, 379, 357, 337, 318, 300, 284, 268, 253, 239, 225,
  213, 201, 189, 179, 169, 159, 150, 142, 134, 126, 119, 113,
  # Tuning 2
  844, 796, 752, 709, 670, 632, 597, 563, 532, 502, 474, 447,
  422, 398, 376, 355, 335, 316, 298, 282, 266, 251, 237, 224,
  211, 199, 188, 177, 167, 158, 149, 141, 133, 125, 118, 112,
  # Tuning 3
  838, 791, 746, 704, 665, 628, 592, 559, 528, 498, 470, 444,
  419, 395, 373, 352, 332, 314, 296, 280, 264, 249, 235, 222,
  209, 198, 187, 176, 166, 157, 148, 140, 132, 125, 118, 111,
  # Tuning 4
  832, 785, 741, 699, 660, 623, 588, 555, 524, 495, 467, 441,
  416, 392, 370, 350, 330, 312, 294, 278, 262, 247, 233, 220,
  208, 196, 185, 175, 165, 156, 147, 139, 131, 124, 117, 110,
  # Tuning 5
  826, 779, 736, 694, 655, 619, 584, 551, 520, 491, 463, 437,
  413, 390, 368, 347, 328, 309, 292, 276, 260, 245, 232, 219,
  206, 195, 184, 174, 164, 155, 146, 138, 130, 123, 116, 109,
  # Tuning 6
  820, 774, 730, 689, 651, 614, 580, 547, 516, 487, 460, 434,
  410, 387, 365, 345, 325, 307, 290, 274, 258, 244, 230, 217,
  205, 193, 183, 172, 163, 154, 145, 137, 129, 122, 115, 109,
  # Tuning 7
  814, 768, 725, 684, 646, 610, 575, 543, 513, 484, 457, 431,
  407, 384, 363, 342, 323, 305, 288, 272, 256, 242, 228, 216,
  204, 192, 181, 171, 161, 152, 144, 136, 128, 121, 114, 108,
  # Tuning -8
  907, 856, 808, 762, 720, 678, 640, 604, 570, 538, 508, 480,
  453, 428, 404, 381, 360, 339, 320, 302, 285, 269, 254, 240,
  226, 214, 202, 190, 180, 170, 160, 151, 143, 135, 127, 120,
  # Tuning -7
  900, 850, 802, 757, 715, 675, 636, 601, 567, 535, 505, 477,
  450, 425, 401, 379, 357, 337, 318, 300, 284, 268, 253, 238,
  225, 212, 200, 189, 179, 169, 159, 150, 142, 134, 126, 119,
  # Tuning -6
  894, 844, 796, 752, 709, 670, 632, 597, 563, 532, 502, 474,
  447, 422, 398, 376, 355, 335, 316, 298, 282, 266, 251, 237,
  223, 211, 199, 188, 177, 167, 158, 149, 141, 133, 125, 118,
  # Tuning -5
  887, 838, 791, 746, 704, 665, 628, 592, 559, 528, 498, 470,
  444, 419, 395, 373, 352, 332, 314, 296, 280, 264, 249, 235,
  222, 209, 198, 187, 176, 166, 157, 148, 140, 132, 125, 118,
  # Tuning -4
  881, 832, 785, 741, 699, 660, 623, 588, 555, 524, 494, 467,
  441, 416, 392, 370, 350, 330, 312, 294, 278, 262, 247, 233,
  220, 208, 196, 185, 175, 165, 156, 147, 139, 131, 123, 117,
  # Tuning -3
  875, 826, 779, 736, 694, 655, 619, 584, 551, 520, 491, 463,
  437, 413, 390, 368, 347, 328, 309, 292, 276, 260, 245, 232,
  219, 206, 195, 184, 174, 164, 155, 146, 138, 130, 123, 116,
  # Tuning -2
  868, 820, 774, 730, 689, 651, 614, 580, 547, 516, 487, 460,
  434, 410, 387, 365, 345, 325, 307, 290, 274, 258, 244, 230,
  217, 205, 193, 183, 172, 163, 154, 145, 137, 129, 122, 115,
  # Tuning -1
  862, 814, 768, 725, 684, 646, 610, 575, 543, 513, 484, 457,
  431, 407, 384, 363, 342, 323, 305, 288, 272, 256, 242, 228,
  216, 203, 192, 181, 171, 161, 152, 144, 136, 128, 121, 114
]

#type
#  AudioBuffer* {.unchecked.} = array[1, int16]
#  AudioBufferPtr* = ptr AudioBuffer

