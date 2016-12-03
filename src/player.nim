const
  DEFAULT_BEATS_PER_MIN = 125
  DEFAULT_TICKS_PER_ROW = 6
  DEFAULT_VOLUME        = 0x40
  DEFAULT_PAN           = 0x40
  ROWS_PER_BEAT         = 4
  MILLIS_PER_MINUTE     = 60 * 1000
  REPEAT_LENGTH_MIN     = 3

const
  AMIGA_BASE_FREQ_PAL  = 7093789.2
  AMIGA_BASE_FREQ_NTSC = 7159090.5

const
  AMPLIFICATION = 8


type Channel = ref object
  pan:        int
  volume:     int
  currSample: Sample
  samplePos:  float
  sampleStep: float

type PlaybackState = object
  module:              Module
  beatsPerMin:         int
  ticksPerRow:         int
  songPos:             int
  currRow:             int
  currTick:            int
  tickFramesRemaining: int
  channels:            seq[Channel]

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

  ps.channels = newSeq[Channel]()
  for ch in 0..<module.numChannels:
    ps.channels.add(newChannel())
    ps.channels[ch].pan = ch mod 2 * 0x80 #XXX


proc framesPerTick(ps: PlaybackState, sampleRate: int): int =
  let
    millisPerBeat   = MILLIS_PER_MINUTE / ps.beatsPerMin
    ticksPerBeat    = ROWS_PER_BEAT * ps.ticksPerRow
    millisPerTick   = int(millisPerBeat / ticksPerBeat.float)
    samplesPerMilli = sampleRate div 1000

  result = millisPerTick * samplesPerMilli


proc render(ch: Channel, samples: AudioBufferPtr,
            frameOffset, numFrames: int) =

  for i in 0..<numFrames:
    var s: int16
    if ch.currSample != nil:
      if ch.volume == 0:
        s = 0
      else:
        s = int16(ch.currSample.data[ch.samplePos.int])  # no interpolation

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
      samples[(frameOffset + i)*2 + 0] += s * AMPLIFICATION
    else:
      samples[(frameOffset + i)*2 + 1] += s * AMPLIFICATION


proc noteToFreq(note: int): float =
  assert note >= 0 and note <= periodTable.high
  result = AMIGA_BASE_FREQ_PAL / float(periodTable[note] * 2)


proc updateChannelsFirstTick(ps: var PlaybackState, sampleRate: int) =
  let patt = ps.module.patterns[ps.module.songPositions[ps.songPos]]

  for chanIdx in 0..ps.channels.high:
    let cell = patt.tracks[chanIdx].rows[ps.currRow]
    var ch = ps.channels[chanIdx]

    if cell.sampleNum > 0:
      ch.currSample = ps.module.samples[cell.sampleNum]
      ch.volume = ch.currSample.volume
      ch.samplePos = 0

    if cell.note != NOTE_NONE:
      let noteFreq = noteToFreq(cell.note)
      ch.sampleStep = noteFreq / float(sampleRate)


proc advancePlayPosition(ps: var PlaybackState, sampleRate: int) =
  ps.currTick += 1

  if ps.currTick > ps.ticksPerRow-1:
    ps.currTick = 0
    ps.currRow += 1

    if ps.currRow > ROWS_PER_PATTERN-1:
      ps.currRow = 0
      ps.songPos += 1
      # TODO check song length

    updateChannelsFirstTick(ps, sampleRate)


proc render(ps: var PlaybackState, samples: AudioBufferPtr, numFrames: int,
            sampleRate: int) =

  # TODO get rid of this, only needed on init or after the sample rate has
  # changed
  assert ps.tickFramesRemaining >= 0 
  if ps.tickFramesRemaining == 0:
    ps.tickFramesRemaining = framesPerTick(ps, sampleRate)

  # XXX
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
      ps.tickFramesRemaining = framesPerTick(ps, sampleRate)

      advancePlayPosition(ps, sampleRate)

