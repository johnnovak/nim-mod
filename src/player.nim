import math

import audio/common
import config
import module

# Reference: Protracker V1.1B Playroutine
# http://16-bits.org/pt_src/replayer/PT1.1b_replay_cia.s

const
  DEFAULT_TEMPO         = 125
  DEFAULT_TICKS_PER_ROW = 6
  MAX_VOLUME            = 0x40
  MIN_PERIOD            = periodTable[NOTE_MAX]
  MAX_PERIOD            = periodTable[NOTE_MIN]

  AMIGA_BASE_FREQ_PAL  = 7093789.2
  AMIGA_BASE_FREQ_NTSC = 7159090.5

  AMPLIFICATION = 128

  NO_VALUE = -1


const vibratoTable = [
    0,  24,  49,  74,  97, 120, 141, 161,
  180, 197, 212, 224, 235, 244, 250, 253,
  255, 253, 250, 244, 235, 224, 212, 197,
  180, 161, 141, 120,  97,  74,  49,  24
]

type
  PlaybackState* = object
    config*:             Config
    module*:             Module

    channels:            seq[Channel]
    channelState*:       seq[ChannelState]

    # Song state
    tempo*:              Natural # TODO readonly
    ticksPerRow*:        Natural # TODO readonly
    currSongPos*:        Natural # TODO readonly
    currRow*:            int # TODO readonly
    currTick:            Natural # this gets reset to zero by pattern delay
                                 # on every new "delayed" row
    ellapsedTicks:       Natural # actual ellapsed ticks per row

    # For implementing pattern-level effects
    jumpRow:             int
    jumpSongPos:         int
    loopStartRow:        Natural
    loopCount:           Natural
    patternDelayCount:   int

    # Used by the audio renderer
    tickFramesRemaining: Natural

    # This is only used for changing the song position by the user during
    # playback
    nextSongPos*:        int

  Channel = ref object
    # Channel state
    currSample:     Sample
    period:         int #
    pan:            float32
    volume:         int

    # Per-channel effect memory
    portaToNote:    int
    portaSpeed:     int
    vibratoSpeed:   int
    vibratoDepth:   int
    offset:         int
    delaySample:    Sample

    # Used by the audio renderer
    samplePos:      float32
    volumeScalar:   float32
    sampleStep:     float32

    # Vibrate state
    vibratoPos:     int
    vibratoSign:    int

    # For emulating the ProTracker swap sample quirk
    swapSample:     Sample

  ChannelState* = enum
    csPlaying, csMuted, csDimmed

  MixBuffer = array[1024, float32]


proc resetChannel(ch: var Channel) =
  ch.currSample = nil
  ch.period = NO_VALUE
  # panning doesn't get reset
  ch.volume = 0

  ch.portaToNote = NOTE_NONE
  ch.portaSpeed = 0
  ch.vibratoSpeed = 0
  ch.vibratoDepth = 0
  ch.offset = 0
  ch.delaySample = nil

  ch.samplePos = 0
  ch.volumeScalar = 0
  ch.sampleStep = 0

  ch.vibratoPos = 0
  ch.vibratoSign = 1

  ch.swapSample = nil


proc newChannel(): Channel =
  var ch = new Channel
  ch.resetChannel()
  result = ch

proc resetPlaybackState(ps: var PlaybackState) =
  ps.currSongPos = 0

  # These initial values ensure that the very first row & tick of the playback
  # are handled correctly
  ps.currRow = -1
  ps.currTick = ps.ticksPerRow - 1
  ps.ellapsedTicks = 0

  ps.jumpRow = NO_VALUE
  ps.jumpSongPos = NO_VALUE
  ps.loopStartRow = 0
  ps.loopCount = 0
  ps.patternDelayCount = NO_VALUE

  ps.tickFramesRemaining = 0

  ps.nextSongPos = NO_VALUE


proc initPlaybackState*(config: Config, module: Module): PlaybackState =
  var ps: PlaybackState
  ps.config = config
  ps.module = module

  ps.channels = newSeq[Channel]()
  ps.channelState = newSeq[ChannelState]()
  for ch in 0..<module.numChannels:
    var chan = newChannel()
    var modCh = ch mod 4
    if modCh == 0 or modch == 3:
      chan.pan = -1.0
    else:
      chan.pan =  1.0

    ps.channels.add(chan)
    ps.channelState.add(csPlaying)

  ps.tempo = DEFAULT_TEMPO
  ps.ticksPerRow = DEFAULT_TICKS_PER_ROW

  ps.resetPlaybackState()
  result = ps


proc swapSample(ch: Channel) =
  if ch.swapSample != nil:
    ch.currSample = ch.swapSample
    ch.swapSample = nil

proc linearPanLeft (p: float32): float32 = -0.5 * p + 0.5
proc linearPanRight(p: float32): float32 =  0.5 * p + 0.5


proc render(ch: Channel, ps: PlaybackState,
            mixBuffer: var MixBuffer, frameOffset, numFrames: Natural) =
  for i in 0..<numFrames:
    var s: float32
    if ch.currSample == nil:
      s = 0
    else:
      if ch.period == NO_VALUE or ch.samplePos >= (ch.currSample.length).float32:
        s = 0
      else:
        # no interpolation
#        s = ch.currSample.data[ch.samplePos.int].float * ch.volumeScalar

        # linear interpolation
        let
          posInt = ch.samplePos.int
          s1 = ch.currSample.data[posInt]
          s2 = ch.currSample.data[posInt + 1]
          f = ch.samplePos - posInt.float32

        s = (s1*(1.0-f) + s2*f) * ch.volumeScalar

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
      stereoSep = ps.config.stereoSeparation
      panLeft = linearPanLeft(ch.pan * stereoSep)
      panRight = linearPanRight(ch.pan* stereoSep)

    mixBuffer[(frameOffset + i)*2 + 0] += s * panLeft
    mixBuffer[(frameOffset + i)*2 + 1] += s * panRight


proc finetunedNote(s: Sample, note: int): int =
  result = s.finetune * FINETUNE_PAD + note

proc periodToFreq(period: int): float32 =
  result = AMIGA_BASE_FREQ_PAL / (period * 2).float32

proc setSampleStep(ch: Channel, sampleRate: int) =
  ch.sampleStep = periodToFreq(ch.period) / sampleRate.float32

proc setSampleStep(ch: Channel, period, sampleRate: int) =
  ch.sampleStep = periodToFreq(period) / sampleRate.float32

proc setVolume(ch: Channel, vol: int) =
  ch.volume = vol
  if vol == 0:
    ch.volumeScalar = 0
  else:
    let vol_dB = 20 * log10(vol / MAX_VOLUME)
    ch.volumeScalar = pow(10.0, vol_dB / 20) * AMPLIFICATION

proc isFirstTick(ps: PlaybackState): bool =
  result = ps.ellapsedTicks == 0


# Effects

proc doArpeggio(ps: PlaybackState, ch: Channel, note1, note2: int) =

  proc findClosestPeriodIndex(finetune, period: int): int =
    result = -1
    let offs = finetune * FINETUNE_PAD
    for idx in (offs + NOTE_MIN)..(offs + NOTE_MAX):
      if period >= periodTable[idx]:
        result = idx
        break
    assert result > -1

  if not isFirstTick(ps):
    if ch.currSample != nil and ch.volume > 0:
      var period = ch.period
      case ps.currTick mod 3:
      of 0: discard
      of 1:
        if note1 > 0:
          let idx = findClosestPeriodIndex(ch.currSample.finetune, ch.period)
          period = periodTable[idx + note1]

      of 2:
        if note2 > 0:
          let idx = findClosestPeriodIndex(ch.currSample.finetune, ch.period)
          period = periodTable[idx + note2]

      else: assert false
      setSampleStep(ch, period, ps.config.sampleRate)


proc doSlideUp(ps: PlaybackState, ch: Channel, speed: int) =
  if not isFirstTick(ps):
    ch.period = max(ch.period - speed, MIN_PERIOD)
    setSampleStep(ch, ps.config.sampleRate)

proc doSlideDown(ps: PlaybackState, ch: Channel, speed: int) =
  if not isFirstTick(ps):
    ch.period = min(ch.period + speed, MAX_PERIOD)
    setSampleStep(ch, ps.config.sampleRate)


proc tonePortamento(ps: PlaybackState, ch: Channel) =
  if ch.portaToNote != NOTE_NONE and ch.period > -1 and ch.currSample != nil:
    let toPeriod = periodTable[finetunedNote(ch.currSample, ch.portaToNote)]
    if ch.period < toPeriod:
      ch.period = min(ch.period + ch.portaSpeed, toPeriod)
      setSampleStep(ch, ps.config.sampleRate)

    elif ch.period > toPeriod:
      ch.period = max(ch.period - ch.portaSpeed, toPeriod)
      setSampleStep(ch, ps.config.sampleRate)

    if ch.period == toPeriod:
      ch.portaToNote = NOTE_NONE


proc doTonePortamento(ps: PlaybackState, ch: Channel, speed: int, note: int) =
  if isFirstTick(ps):
    if note != NOTE_NONE:
      ch.portaToNote = note
    if speed != 0:
      ch.portaSpeed = speed
  else:
    tonePortamento(ps, ch)


proc vibrato(ps: PlaybackState, ch: Channel) =
  inc(ch.vibratoPos, ch.vibratoSpeed)
  if ch.vibratoPos > vibratoTable.high:
    dec(ch.vibratoPos, vibratoTable.len)
    ch.vibratoSign *= -1

  let vibratoPeriod = ch.vibratoSign * ((vibratoTable[ch.vibratoPos] *
                                         ch.vibratoDepth) div 128)
  setSampleStep(ch, ch.period + vibratoPeriod, ps.config.sampleRate)

proc doVibrato(ps: PlaybackState, ch: Channel, speed, depth: int, note: int) =
  if isFirstTick(ps):
    if note != NOTE_NONE:
      ch.vibratoPos = 0
      ch.vibratoSign = 1
    if speed > 0: ch.vibratoSpeed = speed
    if depth > 0: ch.vibratoDepth = depth
  else:
    vibrato(ps, ch)

proc volumeSlide(ps: PlaybackState, ch: Channel, upSpeed, downSpeed: int) =
  if upSpeed > 0:
    setVolume(ch, min(ch.volume + upSpeed, MAX_VOLUME))
  elif downSpeed > 0:
    setVolume(ch, max(ch.volume - downSpeed, 0))

proc doTonePortamentoAndVolumeSlide(ps: PlaybackState, ch: Channel,
                                    upSpeed, downSpeed: int, note: int) =
  if isFirstTick(ps):
    if note != NOTE_NONE:
      ch.portaToNote = note
  else:
    tonePortamento(ps, ch)
    volumeSlide(ps, ch, upSpeed, downSpeed)

proc doVibratoAndVolumeSlide(ps: PlaybackState, ch: Channel,
                             upSpeed, downSpeed: int) =
  if not isFirstTick(ps):
    vibrato(ps, ch)
    volumeSlide(ps, ch, upSpeed, downSpeed)

proc doTremolo(ps: PlaybackState, ch: Channel, speed, depth: int) =
  discard

proc doSetSampleOffset(ps: PlaybackState, ch: Channel, offset: int,
                       note: int) =
  if isFirstTick(ps):
    if note != NOTE_NONE and ch.currSample != nil:
      var offs: int
      if offset > 0:
        offs = offset shl 8
        ch.offset = offs
      else:
        offs = ch.offset
      if offs <= ch.currSample.length:
        ch.samplePos = offs.float32
      else:
        setVolume(ch, 0)

proc doVolumeSlide(ps: PlaybackState, ch: Channel, upSpeed, downSpeed: int) =
  if not isFirstTick(ps):
    volumeSlide(ps, ch, upSpeed, downSpeed)

proc doPositionJump(ps: var PlaybackState, ch: Channel, songPos: int) =
  if isFirstTick(ps):
    ps.jumpRow = 0
    ps.jumpSongPos = songPos
    if ps.currSongPos >= ps.module.songLength:
      ps.currSongPos = 0

proc doSetVolume(ps: PlaybackState, ch: Channel, volume: int) =
  if isFirstTick(ps):
    setVolume(ch, min(volume, MAX_VOLUME))

proc doPatternBreak(ps: var PlaybackState, ch: Channel, row: int) =
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
        # TODO test if this actually wraps around into the next song pos if the
        # target is the last row
        if ps.jumpSongPos >= ps.module.songLength:
          ps.currSongPos = 0


proc doSetFilter(ps: PlaybackState, ch: Channel, state: int) =
  discard

proc doFineSlideUp(ps: PlaybackState, ch: Channel, value: int) =
  if ps.currTick == 0:
    ch.period = max(ch.period - value, MIN_PERIOD)
    setSampleStep(ch, ps.config.sampleRate)

proc doFineSlideDown(ps: PlaybackState, ch: Channel, value: int) =
  if ps.currTick == 0:
    ch.period = min(ch.period + value, MAX_PERIOD)
    setSampleStep(ch, ps.config.sampleRate)

proc doGlissandoControl(ps: PlaybackState, ch: Channel, state: int) =
  discard

proc doSetVibratoWaveform(ps: PlaybackState, ch: Channel, value: int) =
  discard

proc doSetFinetune(ps: PlaybackState, ch: Channel, value: int) =
  if isFirstTick(ps):
    if ch.currSample != nil:
      ch.currSample.finetune = value  # XXX is this correct?

# TODO pattern loop memory should be per channel
proc doPatternLoop(ps: var PlaybackState, ch: Channel, numRepeats: int) =
  if isFirstTick(ps):
    if numRepeats == 0:
      ps.loopStartRow = ps.currRow
    else:
      if ps.loopCount < numRepeats:
        ps.jumpSongPos = ps.currSongPos
        ps.jumpRow = ps.loopStartRow
        inc(ps.loopCount)
      else:
        ps.loopStartRow = 0
        ps.loopCount = 0


proc doSetTremoloWaveform(ps: PlaybackState, ch: Channel, value: int) =
  discard

proc doRetrigNote(ps: PlaybackState, ch: Channel, ticks, note: int) =
  if not isFirstTick(ps):
    if note != NOTE_NONE and ticks != 0 and ps.currTick mod ticks == 0:
      ch.samplePos = 0

proc doFineVolumeSlideUp(ps: PlaybackState, ch: Channel, value: int) =
  if ps.currTick == 0:
    setVolume(ch, min(ch.volume + value, MAX_VOLUME))

proc doFineVolumeSlideDown(ps: PlaybackState, ch: Channel, value: int) =
  if ps.currTick == 0:
    setVolume(ch, max(ch.volume - value, 0))

proc doNoteCut(ps: PlaybackState, ch: Channel, ticks: int) =
  if isFirstTick(ps):
    if ticks == 0:
      setVolume(ch, 0)
  else:
    if ps.currTick == ticks:
      setVolume(ch, 0)

proc doNoteDelay(ps: PlaybackState, ch: Channel, ticks, note: int) =
  if not isFirstTick(ps):
    if note != NOTE_NONE and ps.currTick == ticks:
      ch.currSample = ch.delaySample
      ch.delaySample = nil
      if ch.currSample != nil:
        ch.period = periodTable[finetunedNote(ch.currSample, note)]
        ch.samplePos = 0
        setSampleStep(ch, ps.config.sampleRate)

proc doPatternDelay(ps: var PlaybackState, ch: Channel, rows: int) =
  if isFirstTick(ps):
    if ps.patternDelayCount == NO_VALUE:
      ps.patternDelayCount = rows

proc doInvertLoop(ps: PlaybackState, ch: Channel, speed: int) =
  discard

proc doSetSpeed(ps: var PlaybackState, ch: Channel, value: int) =
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
      if sampleNum > 0:
        var sample = ps.module.samples[sampleNum]
        if sample.data == nil:  # empty sample
          setVolume(ch, 0)

        else: # valid sample
          setVolume(ch, sample.volume)
          if note == NOTE_NONE:
            ch.swapSample = sample
          else:
            var extCmd = cell.effect and 0xff0
            if extCmd == 0xED0:
              ch.delaySample = sample
            elif cmd == 0x3 or cmd == 0x5:
              ch.swapSample = sample
            else:
              ch.currSample = sample
              ch.period = periodTable[finetunedNote(ch.currSample, note)]
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
            ch.period = periodTable[finetunedNote(ch.currSample, note)]
            ch.samplePos = 0

    setSampleStep(ch, ps.config.sampleRate)

    case cmd:
    of 0x0: doArpeggio(ps, ch, x, y)
    of 0x1: doSlideUp(ps, ch, xy)
    of 0x2: doSlideDown(ps, ch, xy)
    of 0x3: doTonePortamento(ps, ch, xy, note)
    of 0x4: doVibrato(ps, ch, x, y, note) # TODO waveforms
    of 0x5: doTonePortamentoAndVolumeSlide(ps, ch, x, y, note)
    of 0x6: doVibratoAndVolumeSlide(ps, ch, x, y)
    of 0x7: doTremolo(ps, ch, x, y) # TODO
    of 0x8: discard  # TODO set Panning
    of 0x9: doSetSampleOffset(ps, ch, xy, note)
    of 0xA: doVolumeSlide(ps, ch, x, y)
    of 0xB: doPositionJump(ps, ch, xy)
    of 0xC: doSetVolume(ps, ch, xy)
    of 0xD: doPatternBreak(ps, ch, x*10 + y)

    of 0xe:
      case x:
      of 0x0: doSetFilter(ps, ch, y) # TODO

      # Extended effects
      of 0x1: doFineSlideUp(ps, ch, y)
      of 0x2: doFineSlideDown(ps, ch, y)
      of 0x3: doGlissandoControl(ps, ch, y) # TODO
      of 0x4: doSetVibratoWaveform(ps, ch, y) # TODO
      of 0x5: doSetFinetune(ps, ch, y)
      of 0x6: doPatternLoop(ps, ch, y)
      of 0x7: doSetTremoloWaveform(ps, ch, y) # TODO
      of 0x8: discard  # TODO SetPanning (coarse)
      of 0x9: doRetrigNote(ps, ch, y, note)
      of 0xA: doFineVolumeSlideUp(ps, ch, y)
      of 0xB: doFineVolumeSlideDown(ps, ch, y)
      of 0xC: doNoteCut(ps, ch, y)
      of 0xD: doNoteDelay(ps, ch, y, note)
      of 0xE: doPatternDelay(ps, ch, y)
      of 0xF: doInvertLoop(ps, ch, y) # TODO
      else: assert false

    of 0xF: doSetSpeed(ps, ch, xy)
    else: assert false


proc advancePlayPosition(ps: var PlaybackState) =
  # The user has changed the play position
  if ps.nextSongPos >= 0:
    var nextSongPos = ps.nextSongPos
    ps.resetPlaybackState()
    ps.currSongPos = nextSongPos

    for i in 0..ps.channels.high:
      ps.channels[i].resetChannel()

  inc(ps.currTick)
  inc(ps.ellapsedTicks)

  if ps.ticksPerRow == 0: return

  if ps.currTick > ps.ticksPerRow-1:
    if ps.patternDelayCount > 0:
      ps.currTick = 0
      dec(ps.patternDelayCount)
    else:
      ps.currTick = 0
      ps.ellapsedTicks = 0
      ps.patternDelayCount = NO_VALUE

      if ps.jumpRow == NO_VALUE:
        inc(ps.currRow, 1)
        if ps.currRow > ROWS_PER_PATTERN-1:
          inc(ps.currSongPos, 1)
          if ps.currSongPos >= ps.module.songLength:
            ps.currSongPos = ps.module.songRestartPos
            if ps.currSongPos >= ps.module.songLength:
              ps.currSongPos = 0

          ps.currRow = 0
          ps.loopStartRow = 0
          ps.loopCount = 0
      else:
        ps.currSongPos = ps.jumpSongPos
        ps.currRow = ps.jumpRow
        ps.jumpSongPos = NO_VALUE
        ps.jumpRow = NO_VALUE


proc framesPerTick(ps: PlaybackState): Natural =
  let
    # 2500 / 125 (default tempo) gives the default 20 ms per tick
    # that corresponds to 50Hz PAL VBL
    # See: "FAQ: BPM/SPD/Rows/Ticks etc"
    # https://modarchive.org/forums/index.php?topic=2709.0
    millisPerTick  = 2500 / ps.tempo
    framesPerMilli = ps.config.sampleRate / 1000

  result = (millisPerTick * framesPerMilli).int


proc renderInternal(ps: var PlaybackState, mixBuffer: var MixBuffer,
                    numFrames: int) =
  for i in 0..<numFrames * 2:
    mixBuffer[i] = 0

  var framePos = 0

  while framePos < numFrames-1:
    if ps.tickFramesRemaining == 0:
      advancePlayPosition(ps)
      ps.tickFramesRemaining = framesPerTick(ps)
      doTick(ps)

    var frameCount = min(numFrames - framePos, ps.tickFramesRemaining)

    for chNum, ch in pairs(ps.channels):
      if ps.channelState[chNum] == csPlaying:
        ch.render(ps, mixBuffer, framePos, frameCount)

    inc(framePos, frameCount)
    dec(ps.tickFramesRemaining, frameCount)
    assert ps.tickFramesRemaining >= 0


var gMixBuffer: MixBuffer

proc render*(ps: var PlaybackState, samples: AudioBufferPtr,
             numFrames: Natural) =

  let numFramesMixBuffer = gMixBuffer.len div 2
  var
    framesLeft = numFrames.int
    samplesOffs = 0

  while framesLeft > 0:
    let frames = min(numFramesMixBuffer, framesLeft)

    renderInternal(ps, gMixBuffer, frames)

    for i in 0..<frames * 2:
      samples[samplesOffs + i] = gMixBuffer[i].int16

    dec(framesLeft, numFramesMixBuffer)
    inc(samplesOffs, frames * 2)

