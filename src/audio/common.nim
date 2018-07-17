type
  # ``buf`` is a pointer to the audio buffer,
  # ``bufLen`` is the length of the buffer in bytes.
  AudioCallback* = proc(buf: pointer, bufLen: Natural)

