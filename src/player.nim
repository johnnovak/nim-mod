import locks, math

import audio/common
import module

# Reference: Protracker V1.1B Playroutine
# http://16-bits.org/pt_src/replayer/PT1.1b_replay_cia.s

const
  DEFAULT_TEMPO         = 125
  DEFAULT_TICKS_PER_ROW = 6
  REPEAT_LENGTH_MIN     = 3
  MAX_VOLUME            = 0x40
  MIN_PERIOD            = periodTable[NOTE_MAX]
  MAX_PERIOD            = periodTable[NOTE_MIN]

  AMIGA_BASE_FREQ_PAL  = 7093789.2
  AMIGA_BASE_FREQ_NTSC = 7159090.5

  AMPLIFICATION     = 128
  STEREO_SEPARATION = 0.3

  NO_VALUE = -1


const vibratoTable = [
    0,  24,  49,  74,  97, 120, 141, 161,
  180, 197, 212, 224, 235, 244, 250, 253,
  255, 253, 250, 244, 235, 224, 212, 197,
  180, 161, 141, 120,  97,  74,  49,  24
]

type
  PlaybackState* = object
    module*:             Module
    sampleRate:          Natural
    tempo*:              Natural
    ticksPerRow*:        Natural
    currSongPos*:        Natural
    currRow*:            int
    currTick:            Natural
    tickFramesRemaining: Natural
    channels:            seq[Channel]
    channelState*:       seq[ChannelState]
    jumpRow:             int
    jumpSongPos:         int
    loopStartRow:        Natural
    loopCount:           Natural
    nextSongPos*:        int  # TODO this should be done in a better way
#    lock:                Lock TODO not needed?

  Channel = ref object
    currSample:     Sample
    swapSample:     Sample
    samplePos:      float
    period:         int #
    pan:            int
    volume:         int
    volumeScalar:   float
    sampleStep:     float
    portaToNote:    int
    portaSpeed:     int
    vibratoPos:     int
    vibratoSign:    int
    vibratoSpeed:   int
    vibratoDepth:   int
    offset:         int

  ChannelState* = enum
    csPlaying, csMuted, csDimmed

  MixBuffer = array[1024, float32]


proc resetChannel(ch: var Channel) =
  ch.currSample = nil
  ch.swapSample = nil
  ch.samplePos = 0
  ch.period = NO_VALUE
  ch.pan = 0
  ch.volume = 0
  ch.volumeScalar = 0
  ch.sampleStep = 0
  ch.portaToNote = NOTE_NONE
  ch.portaSpeed = 0
  ch.vibratoPos = 0
  ch.vibratoSign = 1
  ch.vibratoSpeed = 0
  ch.vibratoDepth = 0
  ch.offset = 0

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
  ps.tickFramesRemaining = 0

  ps.jumpRow = NO_VALUE
  ps.jumpSongPos = NO_VALUE
  ps.loopStartRow = 0
  ps.loopCount = 0
  ps.nextSongPos = NO_VALUE

proc initPlaybackState*(ps: var PlaybackState,
                        sampleRate: int, module: Module) =
  ps.module = module
  ps.sampleRate = sampleRate
  ps.tempo = DEFAULT_TEMPO
  ps.ticksPerRow = DEFAULT_TICKS_PER_ROW

  ps.resetPlaybackState()

  ps.channels = newSeq[Channel]()
  ps.channelState = newSeq[ChannelState]()
  for ch in 0..<module.numChannels:
    ps.channels.add(newChannel())
    ps.channelState.add(csPlaying)

  # TODO making pan separation configurable
  for i, ch in ps.channels.pairs:
    ch.pan = if i mod 2 == 0: 0x00 else: 0x80

proc framesPerTick(ps: PlaybackState): Natural =
  let
    # 2500 / 125 (default tempo) gives the default 20 ms per tick
    # that corresponds to 50Hz PAL VBL
    # See: "FAQ: BPM/SPD/Rows/Ticks etc"
    # https://modarchive.org/forums/index.php?topic=2709.0
    millisPerTick  = 2500 / ps.tempo
    framesPerMilli = ps.sampleRate / 1000

  result = (millisPerTick * framesPerMilli).int


proc sampleSwap(ch: Channel) =
  if ch.swapSample != nil:
    ch.currSample = ch.swapSample
    ch.swapSample = nil

proc isLooped(s: Sample): bool =
  return s.repeatLength >= REPEAT_LENGTH_MIN

proc render(ch: Channel, mixBuffer: var MixBuffer, frameOffset, numFrames: Natural) =
  for i in 0..<numFrames:
    var s: float32
    if ch.currSample == nil:
      s = 0
    else:
      if ch.period == NO_VALUE or ch.samplePos >= (ch.currSample.length).float32:
        s = 0
      else:
        # no interpolation
        #s = ch.currSample.data[ch.samplePos.int].float * ch.volumeScalar

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
                              ch.currSample.repeatLength).float:
            sampleSwap(ch)
            ch.samplePos = ch.currSample.repeatOffset.float
        else:
          if ch.samplePos >= (ch.currSample.length).float and
             ch.swapSample != nil and ch.swapSample.isLooped():

            sampleSwap(ch)
            ch.samplePos = ch.currSample.repeatOffset.float

    # TODO clean up panning
    if ch.pan == 0:
      mixBuffer[(frameOffset + i)*2 + 0] += s * (1.0 - STEREO_SEPARATION)
      mixBuffer[(frameOffset + i)*2 + 1] += s *        STEREO_SEPARATION
    else:
      mixBuffer[(frameOffset + i)*2 + 0] += s *        STEREO_SEPARATION
      mixBuffer[(frameOffset + i)*2 + 1] += s * (1.0 - STEREO_SEPARATION)


proc periodToFreq(period: int): float =
  result = AMIGA_BASE_FREQ_PAL / (period * 2).float

proc findClosestNote(finetune, period: int): int =
  result = -1
  for n in NOTE_MIN..<NOTE_MAX:
    if period >= periodTable[finetune + n]:
      result = n
      break
  assert result > -1

proc finetunedNote(s: Sample, note: int): int =
  result = s.finetune * FINETUNE_PAD + note

proc setSampleStep(ch: Channel, sampleRate: int) =
  ch.sampleStep = periodToFreq(ch.period) / sampleRate.float

proc setSampleStep(ch: Channel, period, sampleRate: int) =
  ch.sampleStep = periodToFreq(period) / sampleRate.float

proc setVolume(ch: Channel, vol: int) =
  ch.volume = vol
  if vol == 0:
    ch.volumeScalar = 0
  else:
    let vol_dB = 20 * log10(vol / MAX_VOLUME)
    ch.volumeScalar = pow(10.0, vol_dB / 20) * AMPLIFICATION

# Effects

proc doArpeggio(ps: PlaybackState, ch: Channel, note1, note2: int) =
  if ps.currTick > 0:
    if ch.currSample != nil and ch.volume > 0:
      var period = ch.period
      case ps.currTick mod 3:
      of 0: discard
      of 1:
        if note1 > 0:
          period = periodTable[
            findClosestNote(ch.currSample.finetune, ch.period) + note1]
      of 2:
        if note2 > 0:
          period = periodTable[
            findClosestNote(ch.currSample.finetune, ch.period) + note2]

      else: assert false
      setSampleStep(ch, period, ps.sampleRate)


proc doSlideUp(ps: PlaybackState, ch: Channel, speed: int) =
  if ps.currTick > 0:
    ch.period = max(ch.period - speed, MIN_PERIOD)
    setSampleStep(ch, ps.sampleRate)

proc doSlideDown(ps: PlaybackState, ch: Channel, speed: int) =
  if ps.currTick > 0:
    ch.period = min(ch.period + speed, MAX_PERIOD)
    setSampleStep(ch, ps.sampleRate)


proc tonePortamento(ps: PlaybackState, ch: Channel) =
  if ch.portaToNote != NOTE_NONE and ch.period > -1 and ch.currSample != nil:
    let toPeriod = periodTable[finetunedNote(ch.currSample, ch.portaToNote)]
    if ch.period < toPeriod:
      ch.period = min(ch.period + ch.portaSpeed, toPeriod)
      setSampleStep(ch, ps.sampleRate)

    elif ch.period > toPeriod:
      ch.period = max(ch.period - ch.portaSpeed, toPeriod)
      setSampleStep(ch, ps.sampleRate)

    if ch.period == toPeriod:
      ch.portaToNote = NOTE_NONE


proc doTonePortamento(ps: PlaybackState, ch: Channel, speed: int, note: int) =
  if ps.currTick == 0:
    if note != NOTE_NONE:
      ch.portaToNote = note
    if speed != 0:
      ch.portaSpeed = speed
  else:
    tonePortamento(ps, ch)


proc vibrato(ps: PlaybackState, ch: Channel) =
  if ps.currTick > 0:
    ch.vibratoPos += ch.vibratoSpeed
    if ch.vibratoPos > vibratoTable.high:
      ch.vibratoPos -= vibratoTable.len
      ch.vibratoSign *= -1

    let vibratoPeriod = ch.vibratoSign * ((vibratoTable[ch.vibratoPos] *
                                           ch.vibratoDepth) div 128)
    setSampleStep(ch, ch.period + vibratoPeriod, ps.sampleRate)

proc doVibrato(ps: PlaybackState, ch: Channel, speed, depth: int, note: int) =
  if ps.currTick == 0:
    if note != NOTE_NONE:
      ch.vibratoPos = 0
      ch.vibratoSign = 1
    if speed > 0: ch.vibratoSpeed = speed
    if depth > 0: ch.vibratoDepth = depth
  else:
    vibrato(ps, ch)


proc volumeSlide(ps: PlaybackState, ch: Channel, upSpeed, downSpeed: int) =
  if ps.currTick > 0:
    if upSpeed > 0:
      setVolume(ch, min(ch.volume + upSpeed, MAX_VOLUME))
    elif downSpeed > 0:
      setVolume(ch, max(ch.volume - downSpeed, 0))

proc doTonePortamentoAndVolumeSlide(ps: PlaybackState, ch: Channel,
                                    upSpeed, downSpeed: int, note: int) =
  if ps.currTick == 0:
    if note != NOTE_NONE:
      ch.portaToNote = note
  else:
    tonePortamento(ps, ch)
    volumeSlide(ps, ch, upSpeed, downSpeed)

proc doVibratoAndVolumeSlide(ps: PlaybackState, ch: Channel,
                             upSpeed, downSpeed: int) =
  if ps.currTick > 0:
    vibrato(ps, ch)
    volumeSlide(ps, ch, upSpeed, downSpeed)

proc doTremolo(ps: PlaybackState, ch: Channel, speed, depth: int) =
  discard

proc doSetSampleOffset(ps: PlaybackState, ch: Channel, offset: int,
                       note: int) =
  if ps.currTick == 0:
    if note != NOTE_NONE and ch.currSample != nil:
      var offs: int
      if offset > 0:
        offs = offset shl 8
        ch.offset = offs
      else:
        offs = ch.offset

      if offs <= ch.currSample.length:
        ch.samplePos = offs.float
      else:
        setVolume(ch, 0)


proc doVolumeSlide(ps: PlaybackState, ch: Channel, upSpeed, downSpeed: int) =
  volumeSlide(ps, ch, upSpeed, downSpeed)

proc doPositionJump(ps: var PlaybackState, ch: Channel, songPos: int) =
  ps.jumpRow = 0
  ps.jumpSongPos = songPos
  if ps.currSongPos >= ps.module.songLength:
    ps.currSongPos = 0

proc doSetVolume(ps: PlaybackState, ch: Channel, volume: int) =
  if ps.currTick == 0:
    setVolume(ch, min(volume, MAX_VOLUME))

proc doPatternBreak(ps: var PlaybackState, ch: Channel, breakPos: int) =
  if ps.currTick == 0:
    if ps.currSongPos < ps.module.songLength-1:
      ps.jumpSongPos = ps.currSongPos + 1
    else:
      ps.jumpSongPos = 0
    ps.jumpRow = min(breakPos, ROWS_PER_PATTERN-1)

proc doSetFilter(ps: PlaybackState, ch: Channel, state: int) =
  discard

proc doFineSlideUp(ps: PlaybackState, ch: Channel, value: int) =
  if ps.currTick == 0:
    ch.period = max(ch.period - value, MIN_PERIOD)
    setSampleStep(ch, ps.sampleRate)

proc doFineSlideDown(ps: PlaybackState, ch: Channel, value: int) =
  if ps.currTick == 0:
    ch.period = min(ch.period + value, MAX_PERIOD)
    setSampleStep(ch, ps.sampleRate)

proc doGlissandoControl(ps: PlaybackState, ch: Channel, state: int) =
  discard

proc doSetVibratoWaveform(ps: PlaybackState, ch: Channel, value: int) =
  discard

proc doSetFinetune(ps: PlaybackState, ch: Channel, value: int) =
  if ps.currTick == 0:
    if ch.currSample != nil:
      ch.currSample.finetune = value  # XXX is this correct?

proc doPatternLoop(ps: var PlaybackState, ch: Channel, numRepeats: int) =
  if ps.currTick == 0:
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
  if ps.currTick > 0:
    if note != NOTE_NONE and ticks != 0 and ps.currTick mod ticks == 0:
      ch.samplePos = 0

proc doFineVolumeSlideUp(ps: PlaybackState, ch: Channel, value: int) =
  if ps.currTick == 0:
    setVolume(ch, min(ch.volume + value, MAX_VOLUME))

proc doFineVolumeSlideDown(ps: PlaybackState, ch: Channel, value: int) =
  if ps.currTick == 0:
    setVolume(ch, max(ch.volume - value, 0))

proc doNoteCut(ps: PlaybackState, ch: Channel, ticks: int) =
  if ps.currTick == 0:
    if ticks == 0:
      setVolume(ch, 0)
  else:
    if ps.currTick == ticks:
      setVolume(ch, 0)

proc doNoteDelay(ps: PlaybackState, ch: Channel, ticks, note: int) =
  if ps.currTick > 0:
    if note != NOTE_NONE and ps.currTick == ticks:
      sampleSwap(ch)
      if ch.currSample != nil:
        ch.period = periodTable[finetunedNote(ch.currSample, note)]
        ch.samplePos = 0
        setSampleStep(ch, ps.sampleRate)

proc doPatternDelay(ps: PlaybackState, ch: Channel, delay: int) =
  discard

proc doInvertLoop(ps: PlaybackState, ch: Channel, speed: int) =
  discard

proc doSetSpeed(ps: var PlaybackState, ch: Channel, value: int) =
  if ps.currTick == 0:
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
      note =  cell.note
      cmd  = (cell.effect and 0xf00) shr 8
      x    = (cell.effect and 0x0f0) shr 4
      y    =  cell.effect and 0x00f
      xy   =  cell.effect and 0x0ff

    if ps.currTick == 0:
      if cell.sampleNum > 0:
        if ps.module.samples[cell.sampleNum].data == nil:  # empty sample
          setVolume(ch, 0)
        else:
          setVolume(ch, ps.module.samples[cell.sampleNum].volume)

          if cmd != 0x3 and cmd != 0x5 and            # tone portamento
             ((cell.effect and 0xff0) != 0xed0) and   # note delay
             note != NOTE_NONE:

            ch.currSample = ps.module.samples[cell.sampleNum]
            ch.period = periodTable[finetunedNote(ch.currSample, note)]
            ch.samplePos = 0
          else:
            ch.swapSample = ps.module.samples[cell.sampleNum]

      else: # cell.sampleNum == 0
        if cmd != 0x3 and cmd != 0x5 and            # tone portamento
           ((cell.effect and 0xff0) != 0xed0) and   # node delay
           note != NOTE_NONE:

          sampleSwap(ch)
          if ch.currSample != nil:
            ch.period = periodTable[finetunedNote(ch.currSample, note)]
            ch.samplePos = 0

    setSampleStep(ch, ps.sampleRate)

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
    of 0xa: doVolumeSlide(ps, ch, x, y)
    of 0xb: doPositionJump(ps, ch, xy)
    of 0xc: doSetVolume(ps, ch, xy)
    of 0xd: doPatternBreak(ps, ch, x*10 + y)

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
      of 0xa: doFineVolumeSlideUp(ps, ch, y)
      of 0xb: doFineVolumeSlideDown(ps, ch, y)
      of 0xc: doNoteCut(ps, ch, y)
      of 0xd: doNoteDelay(ps, ch, y, note)
      of 0xe: doPatternDelay(ps, ch, y) # TODO
      of 0xf: doInvertLoop(ps, ch, y) # TODO
      else: assert false

    of 0xf: doSetSpeed(ps, ch, xy)
    else: assert false


proc advancePlayPosition(ps: var PlaybackState) =
  # TODO changing play position should be done properly
  if ps.nextSongPos >= 0:
    var nextSongPos = ps.nextSongPos
    ps.resetPlaybackState()
    ps.currSongPos = nextSongPos

    for i in 0..ps.channels.high:
      ps.channels[i].resetChannel()

  inc(ps.currTick, 1)

  if ps.currTick > ps.ticksPerRow-1:
    ps.currTick = 0

    if ps.jumpRow == NO_VALUE:
      inc(ps.currRow, 1)

      if ps.currRow > ROWS_PER_PATTERN-1:
        inc(ps.currSongPos, 1)
        # TODO check song length
        ps.currRow = 0
        ps.loopStartRow = 0
        ps.loopCount = 0
    else:
      ps.currSongPos = ps.jumpSongPos
      ps.currRow = ps.jumpRow
      ps.jumpSongPos = NO_VALUE
      ps.jumpRow = NO_VALUE


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
        ch.render(mixBuffer, framePos, frameCount)

    framePos += frameCount
    ps.tickFramesRemaining -= frameCount
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

