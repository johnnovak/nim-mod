import math, strformat

import audio/common
import config
import module

# Reference: Protracker V1.1B Playroutine
# http://16-bits.org/pt_src/replayer/PT1.1b_replay_cia.s

const
  DEFAULT_TEMPO         = 125
  DEFAULT_TICKS_PER_ROW = 6

  AMIGA_PAL_CLOCK       = 3546895
  AMIGA_MIN_PERIOD      = amigaPeriodTable[AMIGA_NOTE_MAX]
  AMIGA_MAX_PERIOD      = amigaPeriodTable[AMIGA_NOTE_MIN]
  AMIGA_FINETUNE_PAD    = 37

  MAX_VOLUME            = 0x40
  NUM_CHANNELS          = 2
  NO_VALUE              = -1

const vibratoTable = [
    0,  24,  49,  74,  97, 120, 141, 161,
  180, 197, 212, 224, 235, 244, 250, 253,
  255, 253, 250, 244, 235, 224, 212, 197,
  180, 161, 141, 120,  97,  74,  49,  24
]

type
  PlaybackState* = object
    # These two are set when initialising the object and should only read
    # from after that.
    config*:             Config
    module*:             Module

    # The mute state of the channels can be set from the outside
    channels*:           seq[Channel]

    # This can be set from the outside to signal the renderer to change the
    # song position (defaults to -1)
    nextSongPos*:        int

    # This can be set from the outside to signal the renderer that the
    # playback should be paused.
    paused*:             bool

    # Song tempo & position, should only be read from the outside
    tempo*:              Natural
    ticksPerRow*:        Natural
    currSongPos*:        Natural
    currRow*:            int

    # Total unlooped song length in frames, should only be read from the
    # outside
    songLengthFrames*:   Natural

    # Play position in frames, should only be read from the outside
    # (it's also used internally in the precalc phase)
    playPositionFrame*:  Natural

    # --- INTERNAL STUFF ---
    mode:                RenderMode

    # During a pattern delay (EEy), currTick only counts up to ticksPerRow
    # then resets to zero.
    currTick:            Natural

    # Actual ellapsed ticks for the current row during a pattern delay (EEy)
    ellapsedTicks:       Natural

    # For implementing pattern-level effects
    jumpSongPos:         int
    jumpRow:             int
    patternDelayCount:   int

    # Used for detecting song loops during the precalc phase
    jumpHistory:         seq[JumpPos]

    # Only used to signal the precalc loop that the end of the song has been
    # found
    hasSongEnded:        bool
    songRestartType:     SongRestartType
    songRestartPos:      Natural

    # Built in the precalc phase; it's used during playback to obviate the
    # need for tempo/speed/playtime chasing
    songPosCache:        array[NUM_SONG_POSITIONS, SongPosInfo]

    # Used by the audio renderer
    tickFramesRemaining: Natural

  Channel* = object
    # Can be set from the outside to mute/unmute channels
    state*:          ChannelState

    currSample:      Sample
    period:          Natural
    pan:             float32
    volume:          Natural

    # Per-channel effect memory
    portaToNote:     int
    portaSpeed:      Natural
    vibratoSpeed:    Natural
    vibratoDepth:    Natural
    vibratoWaveform: WaveformType
    tremoloSpeed:    Natural
    tremoloDepth:    Natural
    tremoloWaveform: WaveformType
    offset:          Natural
    delaySample:     Sample

    delaySampleNextRowNote:  int  # kind of a special case...

    loopStartRow:    Natural
    loopRow:         int
    loopCount:       Natural

    # Used by the audio renderer
    samplePos:       float32
    volumeScalar:    float32
    sampleStep:      float32

    # Vibrato state
    vibratoPos:      Natural

    # For emulating the ProTracker swap sample quirk
    swapSample:      Sample

  ChannelState* = enum
    csPlaying, csMuted, csDimmed

  RenderMode = enum
    rmPrecalc, rmPlayback

  JumpPos = object
    songPos: Natural
    row: Natural

  SongPosInfo = object
    visited:      bool
    frame:        Natural
    tempo*:       Natural
    ticksPerRow*: Natural
    startRow*:    Natural

  SongRestartType* = enum
    srNoRestart      = (0, "no restart"),
    srNormalRestart  = (1, "normal restart"),
    srSongRestartPos = (2, "song restart pos"),
    srPositionJump   = (3, "position jump")

  WaveformType* = enum
    wfSine             = (0, "sine"),
    wfRampDown         = (1, "ramp down"),
    wfSquare           = (2, "square"),
    # Random is the same as square in ProTracker classic
    wfRandom           = (3, "random"),
    # These are not supported in ProTracker classic
    wfSineNoRetrig     = (4, "sine (no retrig)"),
    wfRampDownNoRetrig = (5, "ramp down (no retrig)"),
    wfSquareNoRetrig   = (6, "square (no retrig)"),
    wfRandomNoRetrig   = (7, "random (no retrig)")


proc resetChannel(ch: var Channel) =
  # mute state & panning doesn't get reset
  ch.currSample = nil
  ch.period = 0
  ch.volume = 0

  ch.portaToNote = NOTE_NONE
  ch.portaSpeed = 0
  ch.vibratoSpeed = 0
  ch.vibratoDepth = 0
  ch.vibratoWaveform = wfSine
  ch.tremoloSpeed = 0
  ch.tremoloDepth = 0
  ch.tremoloWaveform = wfSine
  ch.offset = 0
  ch.delaySample = nil
  ch.delaySampleNextRowNote = NOTE_NONE
  ch.loopStartRow = 0
  ch.loopRow = NO_VALUE
  ch.loopCount = 0

  ch.samplePos = 0
  ch.volumeScalar = 0
  ch.sampleStep = 0

  ch.vibratoPos = 0

  ch.swapSample = nil


proc initChannel(): Channel =
  result.resetChannel()

proc resetPlaybackState(ps: var PlaybackState) =
  ps.nextSongPos = NO_VALUE

  ps.tempo = DEFAULT_TEMPO
  ps.ticksPerRow = DEFAULT_TICKS_PER_ROW
  ps.currSongPos = 0

  ps.mode = rmPlayback

  # These initial values ensure that the very first row & tick of the playback
  # are handled correctly
  ps.currRow = 0
  ps.currTick = 0

  ps.ellapsedTicks = 0
  ps.jumpSongPos = NO_VALUE
  ps.jumpRow = NO_VALUE
  ps.patternDelayCount = NO_VALUE

  ps.playPositionFrame = 0
  ps.hasSongEnded = false

  ps.tickFramesRemaining = 0


proc resetChannels(ps: var PlaybackState) =
  for i in 0..ps.channels.high:
    ps.channels[i].resetChannel()


proc initPlaybackState*(config: Config, module: Module): PlaybackState =
  var ps: PlaybackState
  ps.config = config
  ps.module = module

  ps.channels = newSeq[Channel]()
  for ch in 0..<module.numChannels:
    var chan = initChannel()
    var modCh = ch mod 4
    if modCh == 0 or modch == 3:
      chan.pan = -1.0
    else:
      chan.pan =  1.0
    ps.channels.add(chan)

  ps.jumpHistory = @[JumpPos(songPos: 0, row: 0)]

  ps.songPosCache[0].visited = true
  ps.songPosCache[0].frame = 0
  ps.songPosCache[0].tempo = DEFAULT_TEMPO
  ps.songPosCache[0].ticksPerRow = DEFAULT_TICKS_PER_ROW
  ps.songPosCache[0].startRow = 0

  ps.resetPlaybackState()
  result = ps


proc setStartPos*(ps: var PlaybackState, startPos, startRow: Natural) =
  ps.currSongPos = startPos
  ps.currRow = startRow.int
  # TODO fake precalc until currRow?


proc checkHasSongEnded(ps: var PlaybackState, songPos: Natural, row: Natural,
                       restartType: SongRestartType) =
  let p = JumpPos(songPos: ps.currSongPos, row: ps.currRow)
  if ps.jumpHistory.contains(p):
    ps.hasSongEnded = true
    ps.songRestartType = restartType
    ps.songRestartPos = p.songPos
  else:
    ps.jumpHistory.add(p)

proc storeSongPosInfo(ps: var PlaybackState) =
  if not ps.songPosCache[ps.currSongPos].visited:
    var spi: SongPosInfo
    spi.visited = true
    spi.frame = ps.playPositionFrame
    spi.tempo = ps.tempo
    spi.ticksPerRow = ps.ticksPerRow
    spi.startRow = ps.currRow
    ps.songPosCache[ps.currSongPos] = spi


proc swapSample(ch: var Channel) =
  if ch.swapSample != nil:
    ch.currSample = ch.swapSample
    ch.swapSample = nil

proc linearPanLeft (p: float32): float32 = -0.5 * p + 0.5
proc linearPanRight(p: float32): float32 =  0.5 * p + 0.5


proc render(ch: var Channel, ps: PlaybackState,
            mixBuffer: var openArray[float32],
            frameOffset, numFrames: Natural) =
  let
    width = ps.config.stereoWidth.float32 / 100
    ampGain = pow(10, ps.config.ampGain / 20)

  for i in 0..<numFrames:
    var s: float32
    if ch.currSample == nil:
      s = 0
    else:
      if ch.period == 0 or ch.samplePos >= (ch.currSample.length).float32:
        s = 0
      else:
        case ps.config.resampler
        of rsNearestNeighbour:
          s = ch.currSample.data[ch.samplePos.int].float * ch.volumeScalar
        of rsLinear:
          let
            posInt = ch.samplePos.int
            s1 = ch.currSample.data[posInt]
            s2 = ch.currSample.data[posInt + 1]
            f = ch.samplePos - posInt.float32
          s = (s1*(1.0-f) + s2*f) * ch.volumeScalar

        s *= ampGain

        # Advance sample position
        ch.samplePos += ch.sampleStep

        if ch.currSample.isLooped():
          if ch.samplePos >= (ch.currSample.repeatOffset +
                              ch.currSample.repeatLength).float32:
            swapSample(ch)
            ch.samplePos = ch.currSample.repeatOffset.float32
        else:
          if ch.samplePos >= (ch.currSample.length).float32 and
             ch.swapSample != nil and ch.swapSample.isLooped():
            swapSample(ch)
            ch.samplePos = ch.currSample.repeatOffset.float32

    var
      panLeft = linearPanLeft(ch.pan * width)
      panRight = linearPanRight(ch.pan * width)

    var pos = (frameOffset + i) * NUM_CHANNELS

    mixBuffer[pos  ] += s * panLeft
    mixBuffer[pos+1] += s * panRight


proc finetunedNote(s: Sample, note: int): int =
  result = s.finetune * AMIGA_FINETUNE_PAD + note

proc getPeriod(ps: PlaybackState, sample: Sample, note: int): Natural =
  if ps.module.useAmigaLimits:
    result = amigaPeriodTable[finetunedNote(sample, note)]
  else:
    # convert signed nibble to signed int
    result = round(extPeriodTable[note].float32 *
                   pow(2, -sample.signedFinetune()/(12*8))).Natural

proc periodToFreq(period: int): float32 =
  result = AMIGA_PAL_CLOCK / period

proc setSampleStep(ch: var Channel, sampleRate: int) =
  ch.sampleStep = periodToFreq(ch.period) / sampleRate.float32

proc setSampleStep(ch: var Channel, period, sampleRate: int) =
  ch.sampleStep = periodToFreq(period) / sampleRate.float32

proc setVolume(ch: var Channel, vol: int) =
  ch.volume = vol
  ch.volumeScalar = vol / MAX_VOLUME

proc isFirstTick(ps: PlaybackState): bool =
  result = ps.ellapsedTicks == 0


# Effects

proc doArpeggio(ps: PlaybackState, ch: var Channel, note1, note2: int) =
  # TODO implement arpeggio for extended octaves
  if ps.module.useAmigaLimits:

    proc findClosestPeriodIndex(finetune, period: int): int =
      result = 0
      let offs = finetune * AMIGA_FINETUNE_PAD
      for idx in (offs + AMIGA_NOTE_MIN)..(offs + AMIGA_NOTE_MAX):
        if period >= amigaPeriodTable[idx]:
          result = idx
          break
      assert result > 0

    if not isFirstTick(ps):
      if ch.currSample != nil and ch.volume > 0:
        var period = ch.period
        case ps.currTick mod 3:
        of 0: discard
        of 1:
          if note1 > 0:
            let idx = findClosestPeriodIndex(ch.currSample.finetune, ch.period)
            period = amigaPeriodTable[idx + note1]

        of 2:
          if note2 > 0:
            let idx = findClosestPeriodIndex(ch.currSample.finetune, ch.period)
            period = amigaPeriodTable[idx + note2]

        else: assert false
        setSampleStep(ch, period, ps.config.sampleRate)
  else:
    discard

proc doSlideUp(ps: PlaybackState, ch: var Channel, speed: int) =
  if not isFirstTick(ps):
    ch.period = max(ch.period - speed, AMIGA_MIN_PERIOD)
    setSampleStep(ch, ps.config.sampleRate)

proc doSlideDown(ps: PlaybackState, ch: var Channel, speed: int) =
  if not isFirstTick(ps):
    ch.period = min(ch.period + speed, AMIGA_MAX_PERIOD)
    setSampleStep(ch, ps.config.sampleRate)


proc tonePortamento(ps: PlaybackState, ch: var Channel) =
  if ch.portaToNote != NOTE_NONE and ch.period > -1 and ch.currSample != nil:
    let toPeriod = getPeriod(ps, ch.currSample, ch.portaToNote)
    if ch.period < toPeriod:
      ch.period = min(ch.period + ch.portaSpeed, toPeriod)
      setSampleStep(ch, ps.config.sampleRate)

    elif ch.period > toPeriod:
      ch.period = max(ch.period - ch.portaSpeed, toPeriod)
      setSampleStep(ch, ps.config.sampleRate)

    if ch.period == toPeriod:
      ch.portaToNote = NOTE_NONE


proc doTonePortamento(ps: PlaybackState, ch: var Channel,
                      speed: int, note: int) =
  if isFirstTick(ps):
    if note != NOTE_NONE:
      ch.portaToNote = note
    if speed != 0:
      ch.portaSpeed = speed
  else:
    tonePortamento(ps, ch)


proc vibrato(ps: PlaybackState, ch: var Channel) =
  var vibratoValue = 0

  case ch.vibratoWaveform:
  of wfSine:
    vibratoValue = vibratoTable[ch.vibratoPos mod vibratoTable.len]

  of wfRampDown:
    if ch.vibratoPos < vibratoTable.len:
      vibratoValue = ((ch.vibratoPos mod vibratoTable.len) * 8)
    else:
      vibratoValue = 255 - (ch.vibratoPos mod vibratoTable.len) * 8

  of wfSquare, wfRandom:
    vibratoValue = 255

  else: discard   # not supported in ProTracker classic

  let periodOffs = vibratoValue * ch.vibratoDepth div 128

  if ch.vibratoPos < vibratoTable.len:
    setSampleStep(ch, ch.period + periodOffs, ps.config.sampleRate)
  else:
    setSampleStep(ch, ch.period - periodOffs, ps.config.sampleRate)

  inc(ch.vibratoPos, ch.vibratoSpeed)
  if ch.vibratoPos >= vibratoTable.len * 2:
    dec(ch.vibratoPos, vibratoTable.len * 2)


proc doVibrato(ps: PlaybackState, ch: var Channel, speed,
               depth: int, note: int) =
  if isFirstTick(ps):
    if note != NOTE_NONE:
      ch.vibratoPos = 0
    if speed > 0: ch.vibratoSpeed = speed
    if depth > 0: ch.vibratoDepth = depth
  else:
    vibrato(ps, ch)

proc volumeSlide(ps: PlaybackState, ch: var Channel, upSpeed, downSpeed: int) =
  if upSpeed > 0:
    setVolume(ch, min(ch.volume + upSpeed, MAX_VOLUME))
  elif downSpeed > 0:
    setVolume(ch, max(ch.volume - downSpeed, 0))

proc doTonePortamentoAndVolumeSlide(ps: PlaybackState, ch: var Channel,
                                    upSpeed, downSpeed: int, note: int) =
  if isFirstTick(ps):
    if note != NOTE_NONE:
      ch.portaToNote = note
  else:
    tonePortamento(ps, ch)
    volumeSlide(ps, ch, upSpeed, downSpeed)

proc doVibratoAndVolumeSlide(ps: PlaybackState, ch: var Channel,
                             upSpeed, downSpeed: int) =
  if not isFirstTick(ps):
    vibrato(ps, ch)
    volumeSlide(ps, ch, upSpeed, downSpeed)

proc doTremolo(ps: PlaybackState, ch: Channel, speed, depth: int) =
  discard

proc doSetSampleOffset(ps: PlaybackState, ch: var Channel, offset: int,
                       note: int) =
  if isFirstTick(ps):
    if note != NOTE_NONE and ch.currSample != nil:
      if offset > 0:
        var offs = offset shl 8
        if offs <= ch.currSample.length:
          ch.samplePos = offs.float32
        else:
          if ch.currSample.isLooped():
            ch.samplePos = ch.currSample.repeatOffset.float32
          else:
            ch.currSample = nil   # TODO should never set the currSample to nil!

proc doVolumeSlide(ps: PlaybackState, ch: var Channel,
                   upSpeed, downSpeed: int) =
  if not isFirstTick(ps):
    volumeSlide(ps, ch, upSpeed, downSpeed)

proc doPositionJump(ps: var PlaybackState, songPos: int) =
  if isFirstTick(ps):
    ps.jumpRow = 0
    ps.jumpSongPos = songPos
    if ps.currSongPos >= ps.module.songLength:
      ps.currSongPos = 0

proc doSetVolume(ps: PlaybackState, ch: var Channel, volume: int) =
  if isFirstTick(ps):
    setVolume(ch, min(volume, MAX_VOLUME))

proc doPatternBreak(ps: var PlaybackState, row: int) =
  if isFirstTick(ps):
    ps.jumpRow = min(row, ROWS_PER_PATTERN-1)
    if ps.jumpSongPos == NO_VALUE:
      ps.jumpSongPos = ps.currSongPos + 1
      if ps.jumpSongPos >= ps.module.songLength:
        ps.jumpSongPos = 0

    # If there is a pattern break (Dxx) and pattern delay (EEx) on the sam
    # row, the target row is not played but the next row.
    if ps.patternDelayCount != NO_VALUE:
      inc(ps.jumpRow)
      if ps.jumpRow >= ROWS_PER_PATTERN:
        ps.jumpRow = 0
        inc(ps.jumpSongPos)
        if ps.jumpSongPos >= ps.module.songLength:
          ps.currSongPos = 0


proc doSetFilter(ps: PlaybackState, state: int) =
  discard

proc doFineSlideUp(ps: PlaybackState, ch: var Channel, value: int) =
  if ps.currTick == 0:
    ch.period = max(ch.period - value, AMIGA_MIN_PERIOD)
    setSampleStep(ch, ps.config.sampleRate)

proc doFineSlideDown(ps: PlaybackState, ch: var Channel, value: int) =
  if ps.currTick == 0:
    ch.period = min(ch.period + value, AMIGA_MAX_PERIOD)
    setSampleStep(ch, ps.config.sampleRate)

proc doGlissandoControl(ps: PlaybackState, ch: Channel, state: int) =
  discard

proc doSetVibratoWaveform(ps: PlaybackState, ch: var Channel, value: int) =
  ch.vibratoWaveform = WaveformType(value and 3)

proc doSetFinetune(ps: PlaybackState, ch: Channel, value: int) =
  if isFirstTick(ps):
    if ch.currSample != nil:
      ch.currSample.finetune = value

proc doPatternLoop(ps: var PlaybackState, ch: var Channel, numRepeats: int) =
  if isFirstTick(ps):
    if numRepeats == 0:
      ch.loopStartRow = ps.currRow
    else:
      if ch.loopCount < numRepeats:
        ch.loopRow = ch.loopStartRow
        inc(ch.loopCount)
      else:
        ch.loopStartRow = 0
        ch.loopCount = 0


proc doSetTremoloWaveform(ps: PlaybackState, ch: var Channel, value: int) =
  if value <= WaveformType.high.ord:
    ch.tremoloWaveform = WaveformType(value)

proc doRetrigNote(ps: PlaybackState, ch: var Channel, ticks, note: int) =
  if not isFirstTick(ps):
    if note != NOTE_NONE and ticks != 0 and ps.currTick mod ticks == 0:
      ch.samplePos = 0

proc doFineVolumeSlideUp(ps: PlaybackState, ch: var Channel, value: int) =
  if ps.currTick == 0:
    setVolume(ch, min(ch.volume + value, MAX_VOLUME))

proc doFineVolumeSlideDown(ps: PlaybackState, ch: var Channel, value: int) =
  if ps.currTick == 0:
    setVolume(ch, max(ch.volume - value, 0))

proc doNoteCut(ps: PlaybackState, ch: var Channel, ticks: int) =
  if isFirstTick(ps):
    if ticks == 0:
      setVolume(ch, 0)
  else:
    if ps.currTick == ticks:
      setVolume(ch, 0)

proc doNoteDelay(ps: PlaybackState, ch: var Channel, ticks, note: int) =
  if not isFirstTick(ps):
    if note != NOTE_NONE and ps.ellapsedTicks == ticks and ch.delaySample != nil:
      ch.currSample = ch.delaySample
      ch.delaySample = nil
      ch.period = getPeriod(ps, ch.currSample, note)
      ch.samplePos = 0
      ch.swapSample = nil
      setSampleStep(ch, ps.config.sampleRate)

proc doPatternDelay(ps: var PlaybackState, rows: int) =
  if isFirstTick(ps):
    if ps.patternDelayCount == NO_VALUE:
      ps.patternDelayCount = rows

proc doInvertLoop(ps: PlaybackState, ch: Channel, speed: int) =
  discard

proc doSetSpeed(ps: var PlaybackState, value: int) =
  if isFirstTick(ps):
    if value < 0x20:
      ps.ticksPerRow = value
    else:
      ps.tempo = value


proc doTick(ps: var PlaybackState) =
  let patt = ps.module.patterns[ps.module.songPositions[ps.currSongPos]]

  for chanIdx in 0..ps.channels.high:
    let cell = patt.tracks[chanIdx].rows[ps.currRow]
    var ch = ps.channels[chanIdx]

    let
      note      = cell.note
      sampleNum = cell.sampleNum
      cmd  = (cell.effect and 0xf00) shr 8
      x    = (cell.effect and 0x0f0) shr 4
      y    =  cell.effect and 0x00f
      xy   =  cell.effect and 0x0ff

    if isFirstTick(ps):
      if ch.delaySampleNextRowNote != NOTE_NONE:
        ch.period = getPeriod(ps, ch.currSample, ch.delaySampleNextRowNote)
        ch.delaySampleNextRowNote = NOTE_NONE

      if sampleNum > 0:
        var sample = ps.module.samples[sampleNum]
        if sample.data == @[]:  # empty sample
          setVolume(ch, 0)

        else: # valid sample
          setVolume(ch, sample.volume)
          if note == NOTE_NONE:
            ch.swapSample = sample
          else:
            var extCmd = cell.effect and 0xff0
            if extCmd == 0xED0 and y > 0:
              if y < ps.ticksPerRow:
                ch.delaySample = sample
              else:
                ch.delaySampleNextRowNote = note
            elif cmd == 0x3 or cmd == 0x5:
              ch.swapSample = sample
            else:
              ch.currSample = sample
              ch.period = getPeriod(ps, ch.currSample, note)
              ch.samplePos = 0
              ch.swapSample = nil

      else: # no sampleNum
        var extCmd = cell.effect and 0xff0
        if extCmd == 0xED0:
          if ch.swapSample != nil:
            ch.delaySample = ch.swapSample
            ch.swapSample = nil
          else:
            ch.delaySample = ch.currSample
        elif note != NOTE_NONE and cmd != 0x3 and cmd != 0x5:
          swapSample(ch)
          if ch.currSample != nil:
            ch.period = getPeriod(ps, ch.currSample, note)
            ch.samplePos = 0
        # TODO if there's a note, set curr sample to nil?

    # TODO move into first tick processing
    setSampleStep(ch, ps.config.sampleRate)

    case cmd:
    of 0x0: doArpeggio(ps, ch, x, y)
    of 0x1: doSlideUp(ps, ch, xy)
    of 0x2: doSlideDown(ps, ch, xy)
    of 0x3: doTonePortamento(ps, ch, xy, note)
    of 0x4: doVibrato(ps, ch, x, y, note)
    of 0x5: doTonePortamentoAndVolumeSlide(ps, ch, x, y, note)
    of 0x6: doVibratoAndVolumeSlide(ps, ch, x, y)
    of 0x7: doTremolo(ps, ch, x, y) # TODO implement
    of 0x8: discard  # TODO implement set panning
    of 0x9: doSetSampleOffset(ps, ch, xy, note)
    of 0xA: doVolumeSlide(ps, ch, x, y)
    of 0xB: doPositionJump(ps, xy)
    of 0xC: doSetVolume(ps, ch, xy)
    of 0xD: doPatternBreak(ps, x*10 + y)

    of 0xe:
      case x:
      of 0x0: doSetFilter(ps, y) # TODO implement filter

      # Extended effects
      of 0x1: doFineSlideUp(ps, ch, y)
      of 0x2: doFineSlideDown(ps, ch, y)
      of 0x3: doGlissandoControl(ps, ch, y) # TODO implement
      of 0x4: doSetVibratoWaveform(ps, ch, y)
      of 0x5: doSetFinetune(ps, ch, y)
      of 0x6: doPatternLoop(ps, ch, y)
      of 0x7: doSetTremoloWaveform(ps, ch, y) # TODO implement
      of 0x8: discard  # TODO implement set panning (coarse)
      of 0x9: doRetrigNote(ps, ch, y, note)
      of 0xA: doFineVolumeSlideUp(ps, ch, y)
      of 0xB: doFineVolumeSlideDown(ps, ch, y)
      of 0xC: doNoteCut(ps, ch, y)
      of 0xD: doNoteDelay(ps, ch, y, note)
      of 0xE: doPatternDelay(ps, y)
      of 0xF: doInvertLoop(ps, ch, y) # TODO MAYBE implement...
      else: discard

    of 0xF: doSetSpeed(ps, xy)
    else: discard

    ps.channels[chanIdx] = ch


proc setNextSongPos(ps: var PlaybackState) =
  if ps.nextSongPos == ps.currSongPos:
    ps.nextSongPos = NO_VALUE
  else:
    var nextSongPos = ps.nextSongPos
    ps.resetPlaybackState()
    ps.resetChannels()
    ps.currSongPos = nextSongPos

    # This effectively achieves tempo & speed command chasing very cheaply!
    ps.playPositionFrame = ps.songPosCache[ps.currSongPos].frame
    ps.tempo             = ps.songPosCache[ps.currSongPos].tempo
    ps.ticksPerRow       = ps.songPosCache[ps.currSongPos].ticksPerRow
    ps.currRow           = ps.songPosCache[ps.currSongPos].startRow
    ps.currTick          = 0


proc advancePlayPosition(ps: var PlaybackState) =
  inc(ps.currTick)
  inc(ps.ellapsedTicks)

  if ps.ticksPerRow == 0:  # zero speed
    ps.hasSongEnded = true
    ps.songRestartType = srNoRestart
    return

  if ps.currTick > ps.ticksPerRow-1:
    if ps.patternDelayCount > 0:  # handle pattern delay
      ps.currTick = 0
      dec(ps.patternDelayCount)
    else:  # no pattern delay
      ps.currTick = 0
      ps.ellapsedTicks = 0
      ps.patternDelayCount = NO_VALUE

      if ps.jumpRow != NO_VALUE:  # handle position jump and/or pattern break
        let prevSongPos = ps.currSongPos
        ps.currSongPos = ps.jumpSongPos
        ps.currRow = ps.jumpRow
        ps.jumpSongPos = NO_VALUE
        ps.jumpRow = NO_VALUE

        if ps.mode == rmPrecalc:
          checkHasSongEnded(ps, ps.currSongPos, ps.currRow, srPositionJump)
          storeSongPosInfo(ps)
        elif ps.currSongPos != prevSongPos:
          ps.playPositionFrame = ps.songPosCache[ps.currSongPos].frame

      else:
        # handle loop pattern
        var loopFound = false
        for i in 0..ps.channels.high:
          if ps.channels[i].loopRow != NO_VALUE:
            ps.currRow = ps.channels[i].loopRow
            ps.channels[i].loopRow = NO_VALUE
            loopFound = true
            break

        if not loopFound:  # move to next row normally
          var restartType: SongRestartType

          inc(ps.currRow, 1)
          if ps.currRow > ROWS_PER_PATTERN-1:
            inc(ps.currSongPos, 1)
            if ps.currSongPos >= ps.module.songLength:
              ps.currSongPos = ps.module.songRestartPos
              if ps.currSongPos >= ps.module.songLength:
                ps.currSongPos = 0
                restartType = srNormalRestart
              else:
                restartType = srSongRestartPos
            ps.currRow = 0
            for i in 0..ps.channels.high:
              ps.channels[i].loopStartRow = 0
              ps.channels[i].loopCount = 0

            if ps.mode == rmPrecalc:
              checkHasSongEnded(ps, ps.currSongPos, ps.currRow, restartType)
              storeSongPosInfo(ps)
            else:
              ps.playPositionFrame = ps.songPosCache[ps.currSongPos].frame


proc framesPerTick(ps: PlaybackState): Natural =
  let
    # 2500 / 125 (default tempo) gives the default 20 ms per tick
    # that corresponds to 50Hz PAL VBL
    # See: "FAQ: BPM/SPD/Rows/Ticks etc"
    # https://modarchive.org/forums/index.php?topic=2709.0
    millisPerTick  = 2500 / ps.tempo
    framesPerMilli = ps.config.sampleRate / 1000

  result = (millisPerTick * framesPerMilli).int


proc handleChangeSongPosRequested(ps: var PlaybackState) =
  # The user has changed the play position, let's do something about it :)
  if ps.nextSongPos != NO_VALUE:
    setNextSongPos(ps)


proc renderInternal(ps: var PlaybackState, mixBuffer: var openArray[float32],
                    numFrames: int) =
  # Clear mixbuffer
  let numSamples = numFrames * NUM_CHANNELS
  for i in 0..<numSamples:
    mixBuffer[i] = 0

  # Just return silence if paused
  if ps.paused:
    handleChangeSongPosRequested(ps)
    return

  # Otherwise render some audio
  var framePos = 0
  while framePos < numFrames:
    if ps.tickFramesRemaining == 0:
      handleChangeSongPosRequested(ps)
      doTick(ps)
      advancePlayPosition(ps)
      ps.tickFramesRemaining = framesPerTick(ps)

    let frameCount = min(numFrames - framePos, ps.tickFramesRemaining)

    for i in 0..ps.channels.high:
      if ps.channels[i].state == csPlaying:
        render(ps.channels[i], ps, mixBuffer, framePos, frameCount)

    inc(framePos, frameCount)
    dec(ps.tickFramesRemaining, frameCount)

    # TODO is the if needed?
    if ps.ticksPerRow > 0:
      inc(ps.playPositionFrame, frameCount)

    assert ps.tickFramesRemaining >= 0


var gMixBuffer: array[1024, float32]
let gNumFramesMixBuffer = gMixBuffer.len div (sizeof(float32) * NUM_CHANNELS)

proc render16Bit(ps: var PlaybackState, buf: pointer, bufLen: Natural) =
  const BYTES_PER_SAMPLE = 2
  assert bufLen mod BYTES_PER_SAMPLE == 0

  const MAX_AMPLITUDE = (2^15-1).float32
  var
    framesLeft = bufLen div (BYTES_PER_SAMPLE * NUM_CHANNELS)
    sampleBuf = cast[ptr UncheckedArray[int16]](buf)
    sampleBufOffs = 0

  while framesLeft > 0:
    let
      numFrames = min(gNumFramesMixBuffer, framesLeft)
      numSamples = numFrames * NUM_CHANNELS

    renderInternal(ps, gMixBuffer, numFrames)

    for i in 0..<numSamples:
      var s = gMixBuffer[i].clamp(-1.0, 1.0)
      sampleBuf[sampleBufOffs + i] = (s * MAX_AMPLITUDE).int16

    dec(framesLeft, numFrames)
    inc(sampleBufOffs, numSamples)


proc render24Bit(ps: var PlaybackState, buf: pointer, bufLen: Natural) =
  const BYTES_PER_SAMPLE = 3
  assert bufLen mod BYTES_PER_SAMPLE == 0

  const MAX_AMPLITUDE = (2^23-1).float32
  var
    framesLeft = bufLen div (BYTES_PER_SAMPLE * NUM_CHANNELS)
    dataBuf = cast[ptr UncheckedArray[uint8]](buf)
    dataBufOffs = 0

  while framesLeft > 0:
    let
      numFrames = min(gNumFramesMixBuffer, framesLeft)
      numSamples = numFrames * NUM_CHANNELS

    renderInternal(ps, gMixBuffer, numFrames)

    for i in 0..<numSamples:
      var
        s = gMixBuffer[i].clamp(-1.0, 1.0)
        s24 = (s * MAX_AMPLITUDE).int32

      dataBuf[dataBufOffs + i*3  ] = ( s24         and 0xff).uint8
      dataBuf[dataBufOffs + i*3+1] = ((s24 shr  8) and 0xff).uint8
      dataBuf[dataBufOffs + i*3+2] = ((s24 shr 16) and 0xff).uint8

    dec(framesLeft, numFrames)
    inc(dataBufOffs, numSamples * BYTES_PER_SAMPLE)


proc render32BitFloat(ps: var PlaybackState, buf: pointer, bufLen: Natural) =
  const BYTES_PER_SAMPLE = 4
  assert bufLen mod BYTES_PER_SAMPLE == 0

  var numFrames = bufLen div (BYTES_PER_SAMPLE * NUM_CHANNELS)
  # ugly but works...
  renderInternal(ps, cast[ptr array[1000000, float32]](buf)[], numFrames)


proc render*(ps: var PlaybackState, buf: pointer, bufLen: Natural) =
  case ps.config.bitDepth
  of bd16Bit:      render16Bit(ps, buf, bufLen)
  of bd24Bit:      render24Bit(ps, buf, bufLen)
  of bd32BitFloat: render32BitFloat(ps, buf, bufLen)


proc precalcSongPosCacheAndSongLength*(ps: var PlaybackState):
    (Natural, SongRestartType, Natural) =

  ps.mode = rmPrecalc
  while not ps.hasSongEnded:
    doTick(ps)
    advancePlayPosition(ps)
    inc(ps.playPositionFrame, framesPerTick(ps))

  # Store result and reset state for the real playback
  ps.songLengthFrames = ps.playPositionFrame
  result = (ps.playPositionFrame, ps.songRestartType, ps.songRestartPos)
  ps.resetPlaybackState()
  ps.resetChannels()

  # Initialise remaining unvisited song positions with safe defaults
  for i in 0..ps.songPosCache.high:
    if not ps.songPosCache[i].visited:
      ps.songPosCache[i].visited = true
      ps.songPosCache[i].frame = 0
      ps.songPosCache[i].tempo = DEFAULT_TEMPO
      ps.songPosCache[i].ticksPerRow = DEFAULT_TICKS_PER_ROW
      ps.songPosCache[i].startRow = 0

