import math, posix
import alsa/alsadriver

const
  FREQ = 110.0
  RATE = 44100.0

var gPhase = 0.0


proc generateSine(samples: AudioBufferPtr, frames: int) {.cdecl.} =

  const MAX_PHASE = 2*PI
  var
    step = MAX_PHASE * FREQ / RATE

  for i in 0..<frames:
    var s = (sin(gPhase) * 32768.0).int16
    samples[i*2 + 0] = s
    samples[i*2 + 1] = s

    gPhase += step
    if gPhase >= MAX_PHASE:
      gPhase -= MAX_PHASE


proc main() =
  initAudio(generateSine)

  while true:
    echo "*"

  closeAudio()


main()

