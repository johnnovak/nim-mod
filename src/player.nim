import math

# FAQ: BPM/SPD/Rows/Ticks etc
# https://modarchive.org/forums/index.php?topic=2709.0
#
# Protracker V1.1B Playroutine
# http://16-bits.org/pt_src/replayer/PT1.1b_replay_cia.s
#
#

const
  DEFAULT_BEATS_PER_MIN = 125
  DEFAULT_TICKS_PER_ROW = 6
  DEFAULT_VOLUME        = 0x40
  DEFAULT_PAN           = 0x40
  ROWS_PER_BEAT         = 4
  MILLIS_PER_MINUTE     = 60 * 1000
  REPEAT_LENGTH_MIN     = 3
  MAX_VOLUME            = 0x40

const
  AMIGA_BASE_FREQ_PAL  = 7093789.2
  AMIGA_BASE_FREQ_NTSC = 7159090.5

const
  AMPLIFICATION = 8


type Channel = ref object
  currSample:   Sample
  samplePos:    float
  pan:          int
  volume:       int
  volumeScalar: float
  period:       int
  sampleStep:   float
  portaToNote:  int
  portaSpeed:   int
  volumeSlide:  int
  cutTick:      int

type PlaybackState = object
  module:              Module
  beatsPerMin:         int
  ticksPerRow:         int
  songPos:             int
  currRow:             int
  currTick:            int
  tickFramesRemaining: int
  channels:            seq[Channel]
  nextSongPos:         int

proc newChannel(): Channel =
  var ch = new Channel
  result = ch

proc initPlaybackState(ps: var PlaybackState, module: Module) =
  ps.module = module
  ps.beatsPerMin = DEFAULT_BEATS_PER_MIN
  ps.ticksPerRow = DEFAULT_TICKS_PER_ROW
  ps.songPos = 0
  ps.currRow = 0
  ps.currTick = 0
  ps.nextSongPos = -1 #XXX

  ps.channels = newSeq[Channel]()
  for ch in 0..<module.numChannels:
    ps.channels.add(newChannel())

  # XXX
  if module.numChannels == 4:
    ps.channels[0].pan = 0x00
    ps.channels[1].pan = 0x80
    ps.channels[2].pan = 0x80
    ps.channels[3].pan = 0x00


proc framesPerTick(ps: PlaybackState, sampleRate: int): int =
  let
    # 2500 / 125 (default BPM) gives the default 20 ms per tick
    # (equals to 50Hz PAL VBL)
    millisPerTick  = int(2500 / ps.beatsPerMin)
    framesPerMilli = sampleRate div 1000

  result = millisPerTick * framesPerMilli


proc render(ch: Channel, samples: AudioBufferPtr,
            frameOffset, numFrames: int) =

  for i in 0..<numFrames:
    var s: int16
    if ch.currSample != nil:
      if ch.volume == 0:
        s = 0
      else:
        # no interpolation
        s = int16(ch.currSample.data[ch.samplePos.int].float *
                  ch.volumeScalar)

        # Advance sample position
        ch.samplePos += ch.sampleStep

        if ch.currSample.repeatLength >= REPEAT_LENGTH_MIN:
          if ch.samplePos.int >= ch.currSample.repeatOffset +
                                 ch.currSample.repeatLength:
            ch.samplePos = ch.currSample.repeatOffset.float

        elif ch.samplePos.int >= ch.currSample.length:
          ch.volume = 0     # sample has finished playing, nothing to do
    else:
      s = 0

    # XXX
    if ch.pan == 0:
      samples[(frameOffset + i)*2 + 0] += s
    else:
      samples[(frameOffset + i)*2 + 1] += s


proc periodToFreq(period: int): float =
  result = AMIGA_BASE_FREQ_PAL / float(period * 2)

proc updateSampleStep(ch: Channel, sampleRate: int) =
  ch.sampleStep = periodToFreq(ch.period) / float(sampleRate)

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
      discard

    of 0x1:   # portamento up
      ch.period = max(ch.period - xy, periodTable[periodTable.high])  # XXX
      updateSampleStep(ch, sampleRate)

    of 0x2:   # portamento down
      ch.period = min(ch.period + xy, periodTable[0])
      updateSampleStep(ch, sampleRate)

    of 0x4:   # vibrato
      discard

    of 0x6:   # volume slide + vibrato
      discard

    of 0x7:   # tremolo
      discard

    of 0xe:   # extended effects
      case x:
      of 0x9:   # retrigger
        discard

      of 0xc:   # note cut
        if ps.currTick == ch.cutTick:
          ch.volume = 0
          ch.volumeScalar = 0
          ps.cutTick = 0

      of 0xd:   # note delay
        discard
      of 0xe:   # pattern delay
        discard
      of 0xf:   # invert loop
        discard
      else: discard

    else: discard

    if cmd == 0x3 or  # tone portamento or
       cmd == 0x5:    # volume slide + tone portamento

      let toPeriod = periodTable[ch.currSample.finetune * NUM_NOTES +
                                 ch.portaToNote]
      if ch.period < toPeriod:
        ch.period = min(ch.period + ch.portaSpeed, toPeriod)
        updateSampleStep(ch, sampleRate)

      elif ch.period > toPeriod:
        ch.period = max(ch.period - ch.portaSpeed, toPeriod)
        updateSampleStep(ch, sampleRate)

    if cmd == 0xa or  # volume slide or
       cmd == 0x5:    # volume slide + tone portamento

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
      ch.currSample = ps.module.samples[cell.sampleNum]
      ch.volume = ch.currSample.volume
      updateVolumeScalar(ch)

    if cmd != 0x3 and cell.note != NOTE_NONE:
      ch.period = periodTable[ch.currSample.finetune * NUM_NOTES + cell.note]
      updateSampleStep(ch, sampleRate)
      ch.samplePos = 0

    case cmd:
    of 0x0:   # arpeggio
      discard

    of 0x3:   # tone portamento
      if cell.note != NOTE_NONE:
        ch.portaToNote = cell.note
      if xy != 0:
        ch.portaSpeed = xy

    of 0x6:   # volume slide + vibrato
      discard

    of 0x7:   # tremolo
      discard

    of 0x8:   # set panning
      discard

    of 0x9:   # sample offset
      let offset = xy shl 7   # because offset is in words, not bytes
      if offset <= ch.currSample.length div 2:
        ch.samplePos = offset.float
      else:
        ch.volume = 0
        ch.volumeScalar = 0

    of 0xb:   # position jump
      discard

    of 0xc:   # set volume
      ch.volume = min(xy, MAX_VOLUME)
      updateVolumeScalar(ch)

    of 0xd:   # pattern break
      if ps.songPos < ps.module.songLength-1:
        ps.songPos += 1
      else:
        ps.songPos = 0
      ps.currRow = min(x*10 + y, ROWS_PER_PATTERN-1)
      updateChannelsFirstTick(ps, sampleRate)

    of 0xe:   # extended effects
      case x:
      of 0x1:   # fine portamento up
        ch.period = ch.period + y
        updateSampleStep(ch, sampleRate)

      of 0x2:   # fine portamento down
        ch.period = ch.period - y
        updateSampleStep(ch, sampleRate)

      of 0x3:   # glissando control
        discard

      of 0x4:   # set vibrato waveform
        discard

      of 0x5:   # set finetune
        discard

      of 0x6:   # pattern loop start / pattern loop
        discard

      of 0x7:   # set tremolo waveform
        discard

      of 0x8:   # set panning
        discard

      of 0x9:   # retrigger
        discard

      of 0xa:   # fine volume slide up
        ch.volume = min(ch.volume + y, MAX_VOLUME)
        updateVolumeScalar(ch)

      of 0xb:   # fine volume slide down
        ch.volume = max(ch.volume - y, 0)
        updateVolumeScalar(ch)

      of 0xc:   # note cut
        ch.cutTick = y

      of 0xd:   # note delay
        discard

      of 0xe:   # pattern delay
        discard

      of 0xf:   # invert loop
        discard

      else: discard

    of 0xf:   # set speed / tempo
      if xy < 0x20:
        ps.ticksPerRow = xy
      else:
        ps.beatsPerMin = xy

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
      ch.currSample = nil

  else:
    ps.currTick += 1

    if ps.currTick > ps.ticksPerRow-1:
      ps.currTick = 0
      ps.currRow += 1

      if ps.currRow > ROWS_PER_PATTERN-1:
        ps.currRow = 0
        ps.songPos += 1
        # TODO check song length

      updateChannelsFirstTick(ps, sampleRate)
    else:
      updateChannelsInbetweenTick(ps, sampleRate)


proc render(ps: var PlaybackState, samples: AudioBufferPtr, numFrames: int,
            sampleRate: int) =

  # TODO get rid of this, only needed on init or after the sample rate has
  # changed
  assert ps.tickFramesRemaining >= 0
  if ps.tickFramesRemaining == 0:
    updateChannelsFirstTick(ps, sampleRate)
    ps.tickFramesRemaining = framesPerTick(ps, sampleRate)

  # XXX clear buffer
  for i in 0..<numFrames:
    samples[i*2] = 0
    samples[i*2+1] = 0

  var framePos = 0

  while framePos < numFrames-1:
    var frameCount = min(numFrames - framePos, ps.tickFramesRemaining)

    for ch in ps.channels:
      ch.render(samples, framePos, frameCount)

    framePos += frameCount
    ps.tickFramesRemaining -= frameCount
    assert ps.tickFramesRemaining >= 0

    if ps.tickFramesRemaining == 0:
      advancePlayPosition(ps, sampleRate)
      ps.tickFramesRemaining = framesPerTick(ps, sampleRate)


