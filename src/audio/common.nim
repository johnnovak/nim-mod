type
  AudioBuffer* = UncheckedArray[int16]
  AudioBufferPtr* = ptr AudioBuffer

  AudioCallback* = proc(samples: AudioBufferPtr, numFrames: int)

