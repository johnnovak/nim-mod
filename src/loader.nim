import algorithm, endians, logging, strformat

import module

const
  TAG_LEN        = 4
  TAG_OFFSET     = 1080   # this is the correct offset for all MOD types
                          # EXCEPT for old 15-sample SoundTracker modules
  BYTES_PER_CELL = 4

type ModuleLoadError* = object of Exception


proc mkTag(tag: string): int =
  assert tag.len == 4
  result =  cast[int](tag[0]) shl 24 or
            cast[int](tag[1]) shl 16 or
            cast[int](tag[2]) shl  8 or
            cast[int](tag[3])

proc digitToInt(c: char): int = c.int - '0'.int

proc firstDigitToInt(tag: int): int =
  digitToInt(cast[char]((tag and 0xff000000) shr 24))

proc lastDigitToInt(tag: int): int =
  digitToInt(cast[char](tag and 0xff))

proc firstTwoDigitsToInt(tag: int): int =
  let
    digit1 = digitToInt(cast[char]((tag and 0xff000000) shr 24))
    digit2 = digitToInt(cast[char]((tag and 0x00ff0000) shr 16))
  result = digit1 * 10 + digit2

proc determineModuleType(tag: int): (ModuleType, int) =
  # Based on:
  # https://wiki.multimedia.cx/index.php?title=Protracker_Module
  # https://chipflip.wordpress.com/2011/04/22/taketracker-mystery-solved/
  # https://greg-kennedy.com/tracker/modformat.html

  if tag == mkTag("M.K.") or tag == mkTag("M!K!"):
    result = (mtProTracker, 4)

  elif tag == mkTag("2CHN") or tag == mkTag("4CHN") or
       tag == mkTag("6CHN") or tag == mkTag("8CHN"):
    result = (mtFastTracker, firstDigitToInt(tag))

  elif tag == mkTag("CD81") or tag == mkTag("OKTA"):
    result = (mtOktalyzer, 8)

  elif tag == mkTag("OCTA"):
    result = (mtOctaMED, 8)

  elif (tag and 0xffff) == (mkTag("xxCH") and 0xffff):
    let chans = firstTwoDigitsToInt(tag)
    if not (chans >= 10 and chans <= 32 and chans mod 2 == 0):
      raise newException(ModuleLoadError,
                         fmt"Invalid FastTracker module tag: '{tag}'")
    result = (mtFastTracker, chans)

  elif (tag and 0xffff) == (mkTag("xxCN") and 0xffff):
    result = (mtFastTracker, firstTwoDigitsToInt(tag))

  elif tag == mkTag("TDZ1") or tag == mkTag("TDZ2") or tag == mkTag("TDZ3"):
    result = (mtTakeTracker, lastDigitToInt(tag))

  elif tag == mkTag("5CHN") or tag == mkTag("7CHN") or tag == mkTag("9CHN"):
    result = (mtTakeTracker, firstDigitToInt(tag))

  elif tag == mkTag("FLT4") or tag == mkTag("FLT8"):
    result = (mtStarTrekker, lastDigitToInt(tag))

  else:
    result = (mtSoundTracker, 4)


proc loadSampleInfo(buf: var seq[uint8], pos: var int): Sample =
  var samp = newSample()

  var name = cast[cstring](alloc0(SAMPLE_NAME_LEN + 1))
  copyMem(name, buf[pos].addr, SAMPLE_NAME_LEN)
  samp.name = $name
  inc(pos, SAMPLE_NAME_LEN)

  bigEndian16(samp.length.addr, buf[pos].addr)
  samp.length *= 2    # convert length in words to length in bytes
  inc(pos, 2)

  samp.finetune = (buf[pos] and 0xf).int
  inc(pos, 1)

  samp.volume = int(buf[pos])
  inc(pos)

  bigEndian16(samp.repeatOffset.addr, buf[pos].addr)
  samp.repeatOffset *= 2
  inc(pos, 2)

  bigEndian16(samp.repeatLength.addr, buf[pos].addr)
  samp.repeatLength *= 2
  inc(pos, 2)

  result = samp


proc periodToNote(period: int): int =
  # Find closest note in the period table as in some modules the periods can
  # be a little off.
  if period == 0:
    return NOTE_NONE

  if period >= periodTable[0]:
    return NOTE_MIN

  for i in 1..NUM_NOTES:
    if periodTable[i] <= period:
      let d1 = period - periodTable[i]
      let d2 = periodTable[i-1] - period
      if d1 < d2:
        return i
      else:
        return i-1

  return NOTE_MAX


proc read(f: File, dest: pointer, len: Natural) =
  let numBytesRead = f.readBuffer(dest, len)
  if numBytesRead != len:
    raise newException(ModuleLoadError, "Unexpected end of file")


proc loadPattern(f: File, numChannels: int): Pattern =
  var patt = newPattern(numChannels)
  var buf: array[BYTES_PER_CELL, uint8]

  for rowNum in 0..<ROWS_PER_PATTERN:
    for track in 0..<numChannels:
      read(f, buf[0].addr, BYTES_PER_CELL)

      var cell: Cell
      cell.note = periodToNote(((buf[0] and 0x0f).int shl 8) or
                                 buf[1].int)

      cell.sampleNum =  (buf[0] and 0xf0).int or
                       ((buf[2] and 0xf0).int shr 4)

      cell.effect = ((buf[2] and 0x0f).int shl 8) or
                      buf[3].int

      patt.tracks[track].rows[rowNum] = cell

  result = patt


proc loadModule*(f: File): Module =
  var module = newModule()

  # We want to check the tag first, but instead of seeking we read ahead so we
  # can load from streams as well.
  var buf = newSeq[uint8](TAG_OFFSET + TAG_LEN)
  var pos = 0

  read(f, buf[0].addr, buf.len)

  # Try to determine module type from the tag
  var tagBuf: array[TAG_LEN + 1, uint8]
  copyMem(tagBuf.addr, buf[TAG_OFFSET].addr, TAG_LEN)
  tagBuf[TAG_LEN] = 0
  let tagString = $cast[cstring](tagBuf[0].addr)
  debug(fmt"Module tag: {tagString}")

  let tag = mkTag(tagString)
  (module.moduleType, module.numChannels) = determineModuleType(tag)
  debug(fmt"Detected module type: {module.moduleType}, " &
        fmt"{module.numChannels} channels")

  # Read song name
  var songName = cast[cstring](alloc0(SONG_TITLE_LEN + 1))
  copyMem(songName, buf[pos].addr, SONG_TITLE_LEN)
  module.songName = $songName
  debug(fmt"Songname: {songname}")
  inc(pos, SONG_TITLE_LEN)

  # Read sample info
  for i in 1..NUM_SAMPLES:
    module.samples[i] = loadSampleInfo(buf, pos)

  # Read song length
  module.songLength = int(buf[pos])
  debug(fmt"Song length: {module.songLength}")
  inc(pos)

  # TODO Magic constant or song restart point (depending on module type),
  # skip it for now...
  inc(pos)

  # Read song positions
  for i in 0..<NUM_SONG_POSITIONS:
    module.songPositions[i] = buf[pos].int
    inc(pos)

  # Determine the number of patterns:
  # the pattern with the highest number in the songpos table + 1
  var numPatterns = 0
  for sp in module.songPositions:
    numPatterns = max(sp.int, numPatterns)
  inc(numPatterns)
  debug(fmt"Number of patterns: {numPatterns}")

  # Read pattern data
  debug(fmt"Reading pattern data...")

  for pattNum in 0..<numPatterns:
    let patt = loadPattern(f, module.numChannels)
    module.patterns.add(patt)

  # Read sample data
  debug(fmt"Reading sample data...")

  for sampNum in 1..NUM_SAMPLES:
    let sampLen = module.samples[sampNum].length
    if sampLen > 0:
      # Load signed 8-bit sample data
      var byteData: seq[int8]
      newSeq(byteData, sampLen)
      read(f, byteData[0].addr, sampLen)

      # Convert sample data to float
      var floatData: seq[float32]
      const SAMPLE_PADDING = 1   # padding for easier interpolation
      newSeq(floatData, byteData.len + SAMPLE_PADDING)

      for i in 0..byteData.high:
        floatData[i] = byteData[i].float32

      # repeat the last sample value for easier linear interpolation
      floatData[sampLen] = floatData[sampLen-1]

      module.samples[sampNum].data = floatData

  debug(fmt"Module loaded successfully")
  result = module


proc loadModule*(fname: string): Module =
  debug(fmt"Loading module '{fname}'")

  var f: File
  if not open(f, fname, fmRead):
    raise newException(IOError, fmt"Cannot open file: '{fname}'")

  result = loadModule(f)
  f.close()


# Unit tests
when isMainModule:
  assert digitToInt('1') == 1

  assert mkTag("2CHN") == (ord('2').int shl 24 or
                           ord('C').int shl 16 or
                           ord('H').int shl  8 or
                           ord('N').int)

  assert firstDigitToInt(mkTag("2CHN")) == 2
  assert firstDigitToInt(mkTag("8CHN")) == 8

  var
    mt: ModuleType
    ch: int

  (mt, ch) = determineModuleType(mkTag("M.K."))
  assert mt == mtProTracker
  assert ch == 4

  (mt, ch) = determineModuleType(mkTag("M!K!"))
  assert mt == mtProTracker
  assert ch == 4

  (mt, ch) = determineModuleType(mkTag("2CHN"))
  assert mt == mtFastTracker
  assert ch == 2

  (mt, ch) = determineModuleType(mkTag("4CHN"))
  assert mt == mtFastTracker
  assert ch == 4

  (mt, ch) = determineModuleType(mkTag("6CHN"))
  assert mt == mtFastTracker
  assert ch == 6

  (mt, ch) = determineModuleType(mkTag("8CHN"))
  assert mt == mtFastTracker
  assert ch == 8

  (mt, ch) = determineModuleType(mkTag("CD81"))
  assert mt == mtOktalyzer
  assert ch == 8

  (mt, ch) = determineModuleType(mkTag("OKTA"))
  assert mt == mtOktalyzer
  assert ch == 8

  (mt, ch) = determineModuleType(mkTag("OCTA"))
  assert mt == mtOctaMED
  assert ch == 8

  (mt, ch) = determineModuleType(mkTag("32CH"))
  assert mt == mtFastTracker
  assert ch == 32

  (mt, ch) = determineModuleType(mkTag("05CN"))
  assert mt == mtTakeTracker
  assert ch == 5

  (mt, ch) = determineModuleType(mkTag("TDZ1"))
  assert mt == mtTakeTracker
  assert ch == 1

  (mt, ch) = determineModuleType(mkTag("5CHN"))
  assert mt == mtTakeTracker
  assert ch == 5

  (mt, ch) = determineModuleType(mkTag("FLT8"))
  assert mt == mtStarTrekker
  assert ch == 8

  (mt, ch) = determineModuleType(mkTag("    "))
  assert mt == mtSoundTracker
  assert ch == 4

