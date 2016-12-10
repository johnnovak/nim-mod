type
  AudioBuffer* {.unchecked.} = array[1, int16]
  AudioBufferPtr* = ptr AudioBuffer


type AudioCallback* = proc (samples: AudioBufferPtr,
                            numFrames: int) {.cdecl, gcsafe.}

