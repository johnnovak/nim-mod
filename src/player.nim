import math

import module

import audio/common

#
# Protracker V1.1B Playroutine
# http://16-bits.org/pt_src/replayer/PT1.1b_replay_cia.s

const
  DEFAULT_TEMPO         = 125
  DEFAULT_TICKS_PER_ROW = 6
  REPEAT_LENGTH_MIN     = 3
  MAX_VOLUME            = 0x40
  MIN_PERIOD            = periodTable[NUM_NOTES - 1]
  MAX_PERIOD            = periodTable[0]

const
  AMIGA_BASE_FREQ_PAL  = 7093789.2
  AMIGA_BASE_FREQ_NTSC = 7159090.5

const
  AMPLIFICATION     = 128
  STEREO_SEPARATION = 0.3

const vibratoTable = [
    0,  24,  49,  74,  97, 120, 141, 161,
  180, 197, 212, 224, 235, 244, 250, 253,
  255, 253, 250, 244, 235, 224, 212, 197,
  180, 161, 141, 120,  97,  74,  49,  24
]

type ChannelState* = enum
  csPlaying, csMuted, csDimmed

type Channel = ref object
  currSample:     Sample
  swapSample:     Sample
  samplePos:      float
  period:         int
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

type PlaybackState* = object
  module*:             Module
  sampleRate:          int
  tempo*:              int
  ticksPerRow*:        int
  songPos*:            int
  currRow*:            int
  currTick:            int
  tickFramesRemaining: int
  channels:            seq[Channel]
  channelState*:       seq[ChannelState]
  jumpRow:             int
  jumpSongPos:         int
  nextSongPos*:        int    # TODO this should be done in a better way

proc newChannel(): Channel =
  var ch = new Channel
  ch.period = -1
  ch.portaToNote = NOTE_NONE
  ch.vibratoSign = 1
  result = ch

proc initPlaybackState*(ps: var PlaybackState,
                        sampleRate: int, module: Module) =
  ps.module = module
  ps.sampleRate = sampleRate
  ps.tempo = DEFAULT_TEMPO
  ps.ticksPerRow = DEFAULT_TICKS_PER_ROW
  ps.currRow = -1
  ps.currTick = DEFAULT_TICKS_PER_ROW - 1
  ps.jumpRow = -1
  ps.jumpSongPos = -1
  ps.nextSongPos = -1 # TODO clean this up

  ps.channels = newSeq[Channel]()
  ps.channelState = newSeq[ChannelState]()
  for ch in 0..<module.numChannels:
    ps.channels.add(newChannel())
    ps.channelState.add(csPlaying)

  # TODO clean up panning
  if module.numChannels == 4:
    ps.channels[0].pan = 0x00
    ps.channels[1].pan = 0x80
    ps.channels[2].pan = 0x80
    ps.channels[3].pan = 0x00


proc framesPerTick(ps: PlaybackState): int =
  let
    # 2500 / 125 (default tempo) gives the default 20 ms per tick
    # that corresponds to 50Hz PAL VBL
    # See: "FAQ: BPM/SPD/Rows/Ticks etc"
    # https://modarchive.org/forums/index.php?topic=2709.0
    millisPerTick  = 2500 / ps.tempo
    framesPerMilli = ps.sampleRate / 1000

  result = int(millisPerTick * framesPerMilli)


proc sampleSwap(ch: Channel) =
  if ch.swapSample != nil:
    ch.currSample = ch.swapSample
    ch.swapSample = nil

proc isLooped(s: Sample): bool =
  return s.repeatLength >= REPEAT_LENGTH_MIN

# TODO use float mix buffer
proc render(ch: Channel, samples: AudioBufferPtr,
            frameOffset, numFrames: int) =

  for i in 0..<numFrames:
    var s: float
    if ch.currSample == nil:
      s = 0
    else:
      if ch.period == -1 or ch.samplePos >= (ch.currSample.length).float:
        s = 0
      else:
        # no interpolation
        #s = ch.currSample.data[ch.samplePos.int].float * ch.volumeScalar

        # linear interpolation
        let
          posInt = ch.samplePos.int
          s1 = ch.currSample.data[posInt].float
          s2 = ch.currSample.data[posInt + 1].float
          f = ch.samplePos - posInt.float

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
      samples[(frameOffset + i)*2 + 0] += int16(s * (1.0 - STEREO_SEPARATION))
      samples[(frameOffset + i)*2 + 1] += int16(s *        STEREO_SEPARATION)
    else:
      samples[(frameOffset + i)*2 + 0] += int16(s *        STEREO_SEPARATION)
      samples[(frameOffset + i)*2 + 1] += int16(s * (1.0 - STEREO_SEPARATION))


proc periodToFreq(period: int): float =
  result = AMIGA_BASE_FREQ_PAL / float(period * 2)

proc findClosestNote(finetune, period: int): int =
  result = -1
  for n in 0..<NUM_NOTES:
    if period >= periodTable[finetune + n]:
      result = n
      break
  assert result > -1

proc finetunedNote(s: Sample, note: int): int =
  result = s.finetune * FINETUNE_PAD + note

proc setSampleStep(ch: Channel, sampleRate: int) =
  ch.sampleStep = periodToFreq(ch.period) / float(sampleRate)

proc setSampleStep(ch: Channel, period, sampleRate: int) =
  ch.sampleStep = periodToFreq(period) / float(sampleRate)

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
          period = periodTable[findClosestNote(ch.currSample.finetune,
                                                   ch.period) + note1]
      of 2:
        if note2 > 0:
          period = periodTable[findClosestNote(ch.currSample.finetune,
                                                   ch.period) + note2]
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
    let toPeriod = periodTable[finetunedNote(ch.currSample,
                                             ch.portaToNote)]
    if ch.period < toPeriod:
      ch.period = min(ch.period + ch.portaSpeed, toPeriod)
      setSampleStep(ch, ps.sampleRate)

    elif ch.period > toPeriod:
      ch.period = max(ch.period - ch.portaSpeed, toPeriod)
      setSampleStep(ch, ps.sampleRate)

    if ch.period == toPeriod:
      ch.portaToNote = NOTE_NONE


proc doTonePortamento(ps: PlaybackState, ch: Channel, speed: int,
                      note: int) =
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

proc doVibrato(ps: PlaybackState, ch: Channel, speed, depth: int,
               note: int) =
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
                                    upSpeed, downSpeed: int,
                                    note: int) =
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

proc doPositionJump(ps: PlaybackState, ch: Channel, songPos: int) =
  discard

proc doSetVolume(ps: PlaybackState, ch: Channel, volume: int) =
  if ps.currTick == 0:
    setVolume(ch, min(volume, MAX_VOLUME))

proc doPatternBreak(ps: var PlaybackState, ch: Channel, breakPos: int) =
  if ps.currTick == 0:
    if ps.songPos < ps.module.songLength-1:
      ps.jumpSongPos = ps.songPos + 1
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
  discard

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
  let patt = ps.module.patterns[ps.module.songPositions[ps.songPos]]

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
          ch.period = periodTable[finetunedNote(ch.currSample, note)]
          ch.samplePos = 0

    setSampleStep(ch, ps.sampleRate)

    case cmd:
    of 0x0: doArpeggio(ps, ch, x, y)
    of 0x1: doSlideUp(ps, ch, xy)
    of 0x2: doSlideDown(ps, ch, xy)
    of 0x3: doTonePortamento(ps, ch, xy, note)
    of 0x4: doVibrato(ps, ch, x, y, note)
    of 0x5: doTonePortamentoAndVolumeSlide(ps, ch, x, y, note)
    of 0x6: doVibratoAndVolumeSlide(ps, ch, x, y)
    of 0x7: doTremolo(ps, ch, x, y)
    of 0x8: discard  # SetPanning
    of 0x9: doSetSampleOffset(ps, ch, xy, note)
    of 0xa: doVolumeSlide(ps, ch, x, y)
    of 0xb: doPositionJump(ps, ch, xy)
    of 0xc: doSetVolume(ps, ch, xy)
    of 0xd: doPatternBreak(ps, ch, x*10 + y)

    of 0xe:
      case x:
      of 0x0: doSetFilter(ps, ch, y)
      # extended effects
      of 0x1: doFineSlideUp(ps, ch, y)
      of 0x2: doFineSlideDown(ps, ch, y)
      of 0x3: doGlissandoControl(ps, ch, y)
      of 0x4: doSetVibratoWaveform(ps, ch, y)
      of 0x5: doSetFinetune(ps, ch, y)
      of 0x6: doPatternLoop(ps, ch, y)
      of 0x7: doSetTremoloWaveform(ps, ch, y)
      of 0x8: discard  # SetPanning (coarse)
      of 0x9: doRetrigNote(ps, ch, y, note)
      of 0xa: doFineVolumeSlideUp(ps, ch, y)
      of 0xb: doFineVolumeSlideDown(ps, ch, y)
      of 0xc: doNoteCut(ps, ch, y)
      of 0xd: doNoteDelay(ps, ch, y, note)
      of 0xe: doPatternDelay(ps, ch, y)
      of 0xf: doInvertLoop(ps, ch, y)
      else: assert false

    of 0xf: doSetSpeed(ps, ch, xy)
    else: assert false


proc advancePlayPosition(ps: var PlaybackState) =
  # TODO changing play position should be done properly
  if ps.nextSongPos >= 0:
    ps.songPos = ps.nextSongPos
    ps.currRow = 0
    ps.currTick = 0
    ps.nextSongPos = -1
    for ch in ps.channels:
      setVolume(ch, 0)

  else:
    ps.currTick += 1

    if ps.currTick > ps.ticksPerRow-1:
      ps.currTick = 0

      if ps.jumpRow > -1:
        ps.songPos = ps.jumpSongPos
        ps.currRow = ps.jumpRow
        ps.jumpSongPos = -1
        ps.jumpRow = -1
      else:
        ps.currRow += 1

        if ps.currRow > ROWS_PER_PATTERN-1:
          ps.currRow = 0
          ps.songPos += 1
          # TODO check song length

    doTick(ps)


proc render*(ps: var PlaybackState, samples: AudioBufferPtr, numFrames: int) =

  # clear buffer
  for i in 0..<numFrames:
    samples[i*2] = 0
    samples[i*2+1] = 0

  var framePos = 0

  while framePos < numFrames-1:
    if ps.tickFramesRemaining == 0:
      advancePlayPosition(ps)
      ps.tickFramesRemaining = framesPerTick(ps)

    var frameCount = min(numFrames - framePos, ps.tickFramesRemaining)

    for chNum, ch in pairs(ps.channels):
      if ps.channelState[chNum] == csPlaying:
        ch.render(samples, framePos, frameCount)

    framePos += frameCount
    ps.tickFramesRemaining -= frameCount
    assert ps.tickFramesRemaining >= 0

