import algorithm, endians, logging, strformat, strutils

import module

const
  TagLen    = 4
  TagOffset = 1080  # this is the correct offset for all MOD types
                    # EXCEPT for old 15-sample SoundTracker modules
  BytesPerCell = 4

type ModuleReadError* = object of Exception


proc mkTag(tag: string): int =
  if tag.len == 4:
    result = cast[int](tag[0]) shl 24 or
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
    # Strictly speaking, the FT2 limit is 32 channels, but with OpenMPT you
    # can use up to 99 channels
    if not (chans >= 10 and chans <= 99 and chans mod 2 == 0):
      raise newException(ModuleReadError,
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


proc nonPrintableCharsToSpace(s: var string) =
  for i in 0..s.high:
    if ord(s[i]) < 32: s[i] = ' '


proc readSampleInfo(buf: var seq[uint8], pos: var Natural): Sample =
  var samp = new Sample

  var name = cast[cstring](alloc0(SampleNameLen + 1))
  copyMem(name, buf[pos].addr, SampleNameLen)
  samp.name = $name
  nonPrintableCharsToSpace(samp.name)

  inc(pos, SampleNameLen)

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


proc periodToExtNote(period: Natural): int =
  # Find closest note in the period table as in some modules the periods can
  # be a little off.
  if period == 0:
    return NoteNone

  if period >= extPeriodTable[0]:
    return ExtNoteMin

  for i in 1..ExtNumNotes-1:
    if extPeriodTable[i] <= period:
      let d1 = period - extPeriodTable[i]
      let d2 = extPeriodTable[i-1] - period
      if d1 != 0 and d2 != 0:
        debug(fmt"    Non-standard period found: {period}")
      if d1 < d2:
        return i
      else:
        return i-1

  return ExtNoteMax


proc read(f: File, dest: pointer, len: Natural) =
  let numBytesRead = f.readBuffer(dest, len)
  if numBytesRead != len:
    debug(fmt"Error: wanted to read {len} bytes " &
          fmt"but could read only {numBytesRead}")
    raise newException(ModuleReadError, "Unexpected end of file")


proc readPattern(buf: openarray[uint8], numChannels: Natural): Pattern =
  var patt = initPattern()
  for i in 0..<numChannels:
    patt.tracks.add(Track())

  var pos = 0
  for rowNum in 0..<RowsPerPattern:
    for track in 0..<numChannels:
      var cell: Cell
      cell.note = periodToExtNote(((buf[pos+0] and 0x0f).int shl 8) or
                                    buf[pos+1].int)

      cell.sampleNum =  (buf[pos+0] and 0xf0).int or
                       ((buf[pos+2] and 0xf0).int shr 4)

      cell.effect = ((buf[pos+2] and 0x0f).int shl 8) or
                      buf[pos+3].int

      patt.tracks[track].rows[rowNum] = cell

      inc(pos, BytesPerCell)

  result = patt


proc readPattern(f: File, numChannels: Natural): Pattern =
  let bytesInPattern = BytesPerCell * RowsPerPattern * numChannels
  var buf: seq[uint8]
  newSeq(buf, bytesInPattern)
  read(f, buf[0].addr, bytesInPattern)
  result = readPattern(buf, numChannels)


proc mergePatterns(p1, p2: Pattern): Pattern =
  var patt = initPattern()
  for t in p1.tracks:
    patt.tracks.add(t)
  for t in p2.tracks:
    patt.tracks.add(t)
  result = patt

proc allNotesWithinAmigaLimits(module: Module): bool =
  for patt in module.patterns:
    for track in patt.tracks:
      for cell in track.rows:
        if not noteWithinAmigaLimits(cell.note):
          return false
  return true

proc convertToAmigaNotes(module: Module) =
  for patt in 0..module.patterns.high:
    for track in 0..<module.numChannels:
      for row in 0..<RowsPerPattern:
        var note = module.patterns[patt].tracks[track].rows[row].note
        if note != NoteNone:
          note -= ExtNoteMinAmiga
          assert note >= AmigaNoteMin and note <= AmigaNoteMax
          module.patterns[patt].tracks[track].rows[row].note = note


proc readPatternData(f: File, buf: var seq[uint8], pos: Natural,
                     module: var Module, numPatterns: Natural) =
  debug(fmt"Reading pattern data...")

  # For non-SoundTracker modules, we have read everything before the pattern
  # data already (first 1084 bytes), so we can continue reading the pattern
  # data from the stream. But for SoundTracker modules, the data before the
  # pattern data is only 600 bytes long, so the first pattern needs to be read
  # partially from the buffer (a pattern is always 1024 bytes long).
  if module.moduleType == mtSoundTracker:
    # Read first pattern
    debug(fmt"  Reading pattern 1")
    let bytesInPattern = BytesPerCell * RowsPerPattern *
                         module.numChannels
    var pattBuf: seq[uint8]
    newSeq(pattBuf, bytesInPattern)

    # pos is at the next byte to be read
    var remainingBytesInBuf = buf.len - pos
    debug(fmt"  remainingBytesInBuf: {remainingBytesInBuf}")
    copyMem(pattBuf[0].addr, buf[pos].addr, remainingBytesInBuf)

    var bytesToRead = bytesInPattern - remainingBytesInBuf
    read(f, pattBuf[remainingBytesInBuf].addr, bytesToRead)

    var patt = readPattern(pattBuf, module.numChannels)
    module.patterns.add(patt)

    # Read the remaining patterns
    for pattNum in 1..<numPatterns:
      debug(fmt"  Reading pattern {pattNum}")
      let patt = readPattern(f, module.numChannels)
      module.patterns.add(patt)

  # 8-channel StarTrekker modules use two consecutive 4-channel patterns
  # to represent a single 8-channel pattern
  elif module.moduleType == mtStarTrekker and module.numChannels == 8:
    if numPatterns mod 2 != 0:
      raise newException(ModuleReadError,
        "Invalid 8-channel StarTrekker module: " &
        fmt"number of patterns is not even: {numPatterns}"
      )
    for pattNum in 0..<numPatterns:
      debug(fmt"  Reading pattern data {pattNum} (FLT8)")
      let
        p1 = readPattern(f, module.numChannels)
        p2 = readPattern(f, module.numChannels)
        patt = mergePatterns(p1, p2)
      module.patterns.add(patt)
  else:
    for pattNum in 0..<numPatterns:
      debug(fmt"  Reading pattern {pattNum}")
      let patt = readPattern(f, module.numChannels)
      module.patterns.add(patt)


proc readSampleData(f: File, module: var Module) =
  debug(fmt"Reading sample data...")

  for sampNum in 1..module.numSamples:
    let sampLen = module.samples[sampNum].length
    if sampLen > 0:
      debug(fmt"  Reading sample {sampNum} ({sampLen} bytes)")
      # Read signed 8-bit sample data
      var byteData: seq[int8]
      newSeq(byteData, sampLen)
      read(f, byteData[0].addr, sampLen)

      # Convert sample data to float
      var floatData: seq[float32]
      const SamplePadding = 1   # padding for easier interpolation
      newSeq(floatData, byteData.len + SamplePadding)

      # Normalise sample data to (-1.0, 1.0) range
      for i in 0..byteData.high:
        floatData[i] = byteData[i].float32 / 128

      # repeat the last sample value for easier linear interpolation
      floatData[sampLen] = floatData[sampLen-1]

      module.samples[sampNum].data = floatData


proc validateSampleInfo(sample: Sample, sampleNum: Natural): seq[string] =
  result = newSeq[string]()

  if sample.repeatOffset > sample.length:
    result.add(
      fmt"Repeat offset {sample.repeatOffset} greater than " &
      fmt"sample length {sample.length} for sample {sampleNum}")

  if sample.length == 0 and sample.repeatLength != MinSampleRepLen:
    warn(fmt"Repeat length of empty sample {sampleNum} is " &
         fmt"{sample.repeatLength} instead of {MinSampleRepLen}")

  if sample.length > 0:
    var repeatEnd = sample.repeatOffset + sample.repeatLength
    if repeatEnd > sample.length:
      result.add(
        "Repeat offset plus repeat length " &
        fmt"({sample.repeatOffset} + {sample.repeatLength} = {repeatEnd}) " &
        fmt"greater than sample length {sample.length} for sample {sampleNum}")


proc validateModule(module: Module): seq[string] =
  result = newSeq[string]()

  for i in 1..module.numSamples:
    result.add(validateSampleInfo(module.samples[i], i))

  if not (module.songLength >= 1 and module.songLength <= NumSongPositions):
    result.add(
      fmt"Invalid song length {module.songLength}, " &
      fmt"must be between 1 and {NumSongPositions}")

  if not (module.songRestartPos >= 0 and
          module.songRestartPos <= NumSongPositions):
    result.add(
      fmt"Invalid song restart position {module.songRestartPos}, " &
      fmt"must be between 0 and {NumSongPositions}")

  for songPos, patternNum in module.songPositions.pairs:
    if patternNum > MaxPatterns:
      result.add(
        fmt"Invalid pattern number {patternNum} at song position {songPos}, " &
        fmt"must be between 0 and {MaxPatterns}")


proc readModule*(f: File): Module =
  var module = newModule()

  # We want to check the tag first, but instead of seeking we read ahead so we
  # can read from streams as well.
  var buf = newSeq[uint8](TagOffset + TagLen)
  var pos: Natural = 0

  read(f, buf[0].addr, buf.len)

  # Try to determine module type from the tag
  var tagBuf: array[TagLen + 1, uint8]
  copyMem(tagBuf.addr, buf[TagOffset].addr, TagLen)
  let tagString = $cast[cstring](tagBuf[0].addr)
  debug(fmt"Module tag: {tagString}")

  let tag = mkTag(tagString)
  (module.moduleType, module.numChannels) = determineModuleType(tag)
  info(fmt"Detected module type: {module.moduleType}, " &
       fmt"{module.numChannels} channels")

  # Read song name
  var songName = cast[cstring](alloc0(SongTitleLen + 1))
  copyMem(songName, buf[pos].addr, SongTitleLen)
  module.songName = $songName
  nonPrintableCharsToSpace(module.songName)
  info(fmt"Songname: {songname}")
  inc(pos, SongTitleLen)

  # Read sample info
  let numSamples = if module.moduleType == mtSoundTracker:
    NumSamplesSoundTracker
  else:
    MaxSamples

  module.numSamples = numSamples
  info(fmt"Number of samples: {numSamples}")

  debug(fmt"Reading sample info...")
  for i in 1..numSamples:
    let sample = readSampleInfo(buf, pos)
    debug(fmt"  Sample {i}: {sample}")
    module.samples[i] = sample

  # Read song length
  module.songLength = buf[pos].Natural
  info(fmt"Song length: {module.songLength}")
  inc(pos)

  # Read song restart position
  module.songRestartPos = buf[pos].Natural
  info(fmt"Song restart position: {module.songRestartPos}")
  inc(pos)

  # Read song positions
  for i in 0..<NumSongPositions:
    var patternNum = buf[pos].Natural
    module.songPositions[i] = patternNum
    inc(pos)

  # Raise exception if the module seems to be invalid
  let errors = validateModule(module)
  if errors.len > 0:
    raise newException(ModuleReadError, errors.join("\n"))

  # Determine the number of patterns:
  # the pattern with the highest number in the songpos table + 1
  var numPatterns = 0
  for sp in module.songPositions:
    numPatterns = max(sp, numPatterns)
  inc(numPatterns)
  info(fmt"Number of patterns: {numPatterns}")

  readPatternData(f, buf, pos, module, numPatterns)

  # Detect whether we should use Amiga notes and the ProTracker period table
  # or extended FT2 notes & periods
  if allNotesWithinAmigaLimits(module):
    convertToAmigaNotes(module)
    module.useAmigaLimits = true

  readSampleData(f, module)

  info(fmt"Module read successfully")
  result = module


proc readModule*(fname: string): Module =
  info(fmt"Reading module '{fname}'")

  var f: File
  if not open(f, fname, fmRead):
    raise newException(IOError, fmt"Cannot open file: '{fname}'")

  result = readModule(f)
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

