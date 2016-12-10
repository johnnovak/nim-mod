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
  samplePos:      float
  period:         int
  pan:            int
  volume:         int
  volumeScalar:   float
  sampleStep:     float
  portaToNote:    int
  portaSpeed:     int
  volumeSlide:    int
  vibratoPos:     int
  vibratoSign:    int
  vibratoSpeed:   int
  vibratoDepth:   int
  offset:         int

type PlaybackState* = object
  module*:             Module
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

proc initPlaybackState*(ps: var PlaybackState, module: Module) =
  ps.module = module
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


proc framesPerTick(ps: PlaybackState, sampleRate: int): int =
  let
    # 2500 / 125 (default tempo) gives the default 20 ms per tick
    # that corresponds to 50Hz PAL VBL
    # See: "FAQ: BPM/SPD/Rows/Ticks etc"
    # https://modarchive.org/forums/index.php?topic=2709.0
    millisPerTick  = 2500 / ps.tempo
    framesPerMilli = sampleRate / 1000

  result = int(millisPerTick * framesPerMilli)


# TODO use float mix buffer
proc render(ch: Channel, samples: AudioBufferPtr,
            frameOffset, numFrames: int) =

  for i in 0..<numFrames:
    var s: float
    if ch.currSample != nil:
      if ch.volume == 0 or ch.period == -1:
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

        if ch.currSample.repeatLength >= REPEAT_LENGTH_MIN:
          if ch.samplePos.int >= ch.currSample.repeatOffset +
                                 ch.currSample.repeatLength:
            ch.samplePos = ch.currSample.repeatOffset.float

        elif ch.samplePos > (ch.currSample.length - 1).float:
          ch.volume = 0     # sample has finished playing, nothing to do
    else:
      s = 0

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

proc updateSampleStep(ch: Channel, sampleRate: int) =
  ch.sampleStep = periodToFreq(ch.period) / float(sampleRate)

proc updateSampleStep(ch: Channel, period, sampleRate: int) =
  ch.sampleStep = periodToFreq(period) / float(sampleRate)

proc updateVolumeScalar(ch: Channel) =
  let vol_dB = 20 * log10(ch.volume / MAX_VOLUME)
  ch.volumeScalar = pow(10.0, vol_dB / 20) * AMPLIFICATION

proc updateChannelsInbetweenTick(ps: var PlaybackState, sampleRate: int) =
  let patt = ps.module.patterns[ps.module.songPositions[ps.songPos]]

  for chanIdx in 0..ps.channels.high:
    let cell = patt.tracks[chanIdx].rows[ps.currRow]
    var ch = ps.channels[chanIdx]

    let
      cmd = (cell.effect and 0xf00) shr 8
      x   = (cell.effect and 0x0f0) shr 4
      y   =  cell.effect and 0x00f
      xy  =  cell.effect and 0x0ff

    case cmd:
    of 0x0:   # arpeggio
      if ch.volume > 0 and x > 0 and y > 0:
        var period: int
        case ps.currTick mod 3:
        of 0: period = ch.period
        of 1: period = periodTable[findClosestNote(ch.currSample.finetune,
                                                   ch.period) + x]
        of 2: period = periodTable[findClosestNote(ch.currSample.finetune,
                                                   ch.period) + y]
        else: discard
        updateSampleStep(ch, period, sampleRate)

    of 0x1:   # portamento up
      ch.period = max(ch.period - xy, MIN_PERIOD)
      updateSampleStep(ch, sampleRate)

    of 0x2:   # portamento down
      ch.period = min(ch.period + xy, MAX_PERIOD)
      updateSampleStep(ch, sampleRate)

    of 0x7:   # tremolo
      discard

    of 0xe:   # extended effects
      case x:
      of 0x9:   # retrigger
        if cell.note != NOTE_NONE and y != 0 and ps.currTick mod y == 0:
          ch.samplePos = 0
          updateSampleStep(ch, sampleRate)

      of 0xc:   # note cut
        if ps.currTick == y:
          ch.volume = 0

      of 0xd:   # note delay
        if cell.note != NOTE_NONE and ps.currTick == y:
          ch.volume = ch.currSample.volume
          updateVolumeScalar(ch)

      of 0xe:   # pattern delay
        discard
      of 0xf:   # invert loop
        discard
      else: discard

    else: discard

    # tone portamento
    if cmd == 0x3 or  # tone portamento
       cmd == 0x5:    # volume slide + tone portamento

      if ch.portaToNote != NOTE_NONE and ch.period > -1:
        let toPeriod = periodTable[finetunedNote(ch.currSample,
                                                 ch.portaToNote)]
        if ch.period < toPeriod:
          ch.period = min(ch.period + ch.portaSpeed, toPeriod)
          updateSampleStep(ch, sampleRate)

        elif ch.period > toPeriod:
          ch.period = max(ch.period - ch.portaSpeed, toPeriod)
          updateSampleStep(ch, sampleRate)

    if cmd == 0x4 or  # vibrato
       cmd == 0x6:    # volume slide + vibrato

      ch.vibratoPos += ch.vibratoSpeed
      if ch.vibratoPos > vibratoTable.high:
        ch.vibratoPos -= vibratoTable.len
        ch.vibratoSign *= -1

      let vibratoPeriod = ch.vibratoSign * ((vibratoTable[ch.vibratoPos] *
                                             ch.vibratoDepth) div 128)
      updateSampleStep(ch, ch.period + vibratoPeriod, sampleRate)

    # volume slide
    if cmd == 0xa or  # volume slide
       cmd == 0x5 or  # volume slide + tone portamento
       cmd == 0x6:    # volume slide + vibrato

      if x > 0:
        ch.volume = min(ch.volume + x, MAX_VOLUME)
        updateVolumeScalar(ch)
        ch.volumeSlide = x
      elif y > 0:
        ch.volume = max(ch.volume - y, 0)
        updateVolumeScalar(ch)
        ch.volumeSlide = -y
      else:
        if ch.volumeSlide > 0:
          ch.volume = min(ch.volume + x, MAX_VOLUME)
          updateVolumeScalar(ch)
        elif ch.volumeSlide < 0:
          ch.volume = max(ch.volume - y, 0)
          updateVolumeScalar(ch)


proc updateChannelsFirstTick(ps: var PlaybackState, sampleRate: int) =
  let patt = ps.module.patterns[ps.module.songPositions[ps.songPos]]

  for chanIdx in 0..ps.channels.high:
    let cell = patt.tracks[chanIdx].rows[ps.currRow]
    var ch = ps.channels[chanIdx]

    let
      cmd = (cell.effect and 0xf00) shr 8
      x   = (cell.effect and 0x0f0) shr 4
      y   =  cell.effect and 0x00f
      xy  =  cell.effect and 0x0ff

    if cell.sampleNum > 0:
      if cell.sampleNum <= ps.module.samples.high and
         ps.module.samples[cell.sampleNum].data != nil:

        ch.currSample = ps.module.samples[cell.sampleNum]
        ch.volume = ch.currSample.volume
        updateVolumeScalar(ch)
      else:
        ch.volume = 0
        ch.volumeScalar = 0

    if cmd != 0x3 and cmd != 0x5 and
       cell.note != NOTE_NONE and ch.currSample != nil:

      ch.period = periodTable[finetunedNote(ch.currSample, cell.note)]
      updateSampleStep(ch, sampleRate)
      ch.samplePos = 0

    updateSampleStep(ch, sampleRate)

    case cmd:
    of 0x3:   # tone portamento
      if cell.note != NOTE_NONE:
        ch.portaToNote = cell.note
      if xy != 0:
        ch.portaSpeed = xy

    of 0x4:   # vibrato
      if cell.note != NOTE_NONE:
        ch.vibratoPos = 0
        ch.vibratoSign = 1

      if x > 0: ch.vibratoSpeed = x 
      if y > 0: ch.vibratoDepth = y 

    of 0x5:   # volume slide + tone portamento
      if cell.note != NOTE_NONE:
        ch.portaToNote = cell.note

    of 0x7:   # tremolo
      discard

    of 0x8:   # set panning
      discard

    of 0x9:   # sample offset
      if cell.note != NOTE_NONE:
        var offset: int
        if xy > 0:
          offset = xy shl 8
          ch.offset = offset
        else:
          offset = ch.offset

        if offset <= ch.currSample.length:
          ch.samplePos = offset.float
        else:
          ch.volume = 0       # XXX vol 0 or don't play at all?

    of 0xb:   # position jump
      discard

    of 0xc:   # set volume
      ch.volume = min(xy, MAX_VOLUME)
      updateVolumeScalar(ch)

    of 0xd:   # pattern break
      if ps.songPos < ps.module.songLength-1:
        ps.jumpSongPos = ps.songPos + 1
      else:
        ps.jumpSongPos = 0
      ps.jumpRow = min(x*10 + y, ROWS_PER_PATTERN-1)

    of 0xe:   # extended effects
      case x:
      of 0x1:   # fine portamento up
        ch.period = max(ch.period - y, MIN_PERIOD)
        updateSampleStep(ch, sampleRate)

      of 0x2:   # fine portamento down
        ch.period = min(ch.period + y, MAX_PERIOD)
        updateSampleStep(ch, sampleRate)

      of 0x3:   # glissando control
        discard

      of 0x4:   # set vibrato waveform
        discard

      of 0x5:   # set finetune
        if ch.currSample != nil:
          ch.currSample.finetune = y  # XXX is this correct?
        discard

      of 0x6:   # pattern loop start / pattern loop
        discard

      of 0x7:   # set tremolo waveform
        discard

      of 0x8:   # set panning
        discard

      of 0xa:   # fine volume slide up
        ch.volume = min(ch.volume + y, MAX_VOLUME)
        updateVolumeScalar(ch)

      of 0xb:   # fine volume slide down
        ch.volume = max(ch.volume - y, 0)
        updateVolumeScalar(ch)

      of 0xc:   # note cut
        if y == 0:
          ch.volume = 0

      of 0xd:   # note delay
        ch.volume = 0
        ch.volumeScalar = 0

      of 0xe:   # pattern delay
        discard

      of 0xf:   # invert loop
        discard

      else: discard

    of 0xf:   # set speed / tempo
      if xy < 0x20:   # TODO multiple speeds on same row
        ps.ticksPerRow = xy
      else:
        ps.tempo = xy

    else: discard


proc advancePlayPosition(ps: var PlaybackState, sampleRate: int) =
  # XXX
  if ps.nextSongPos >= 0:
    ps.songPos = ps.nextSongPos
    ps.currRow = 0
    ps.currTick = 0
    ps.nextSongPos = -1
    for ch in ps.channels:
      ch.volume = 0
      ch.volumeScalar = 0

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

      updateChannelsFirstTick(ps, sampleRate)
    else:
      updateChannelsInbetweenTick(ps, sampleRate)


proc render*(ps: var PlaybackState, samples: AudioBufferPtr, numFrames: int,
             sampleRate: int) =

  for i in 0..<numFrames:
    samples[i*2] = 0
    samples[i*2+1] = 0

  var framePos = 0

  while framePos < numFrames-1:
    if ps.tickFramesRemaining == 0:
      advancePlayPosition(ps, sampleRate)
      ps.tickFramesRemaining = framesPerTick(ps, sampleRate)

    var frameCount = min(numFrames - framePos, ps.tickFramesRemaining)

    for chNum, ch in pairs(ps.channels):
      if ps.channelState[chNum] == csPlaying:
        ch.render(samples, framePos, frameCount)

    framePos += frameCount
    ps.tickFramesRemaining -= frameCount
    assert ps.tickFramesRemaining >= 0

