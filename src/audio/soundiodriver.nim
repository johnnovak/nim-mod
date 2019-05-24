import math, strformat

import soundiowrap

import ../config, common
export common

var
  gInitialised = false
  gLastError = ""
  gAudioCallback: AudioCallback

var
  outstream: ptr SoundIoOutStream
  sio: ptr SoundIo
  device: ptr SoundIoDevice

let channelAreaSize = sizeof SoundIoChannelArea

proc `[]`*(areas: ptr SoundIoChannelArea; channel: int): ptr SoundIoChannelArea =
  let memLoc = cast[int](areas)
  result = cast[ptr SoundIoChannelArea](memLoc + channel * channelAreaSize)

proc write_sample(area: ptr SoundIoChannelArea; sample: float; frame: int) =
  let apointer = cast[int](area.ptr)
  var ptrChannel = cast[ptr float32](apointer + area.step * frame)
  ptrChannel[] = sample

proc write_callback(outstream: ptr SoundIoOutStream, frameCountMin: cint, frameCountMax: cint) {.cdecl.} =
  setupForeignThreadGc()

  var buffer: array[16384, float32]
  gAudioCallback(addr buffer, 1024 * outstream.bytes_per_frame)

  var areas: ptr SoundIoChannelArea
  var framesLeft = frameCountMax
  var err: cint

  while framesLeft > 0:
    var frameCount = framesLeft

    err = soundio_outstream_begin_write(outstream, areas.addr, frameCount.addr)
    if err > 0:
      gLastError = "Unrecoverable stream error: " & $err.soundio_strerror
      break

    if frameCount <= 0:
      break

    for frame in 0 ..< frameCount:
      for channel in 0 ..< outstream.layout.channelCount:
        write_sample(areas[channel], buffer[channel + frame * 2], frame)

    err = soundio_outstream_end_write(outstream)
    if err > 0:
      gLastError = "Unrecoverable stream error: " & $err.soundio_strerror
      break

    framesLeft -= frameCount

proc getLastError*(): string =
  result = gLastError

proc isInitialised*(): bool =
  result = gInitialised

proc initAudio*(config: Config, audioCb: AudioCallback): bool =
  if gInitialised:
    return false

  gAudioCallback = audioCb

  sio = soundio_create()
  discard soundio_connect(sio)

  soundio_flush_events(sio)

  let default_out_device_index = soundio_default_output_device_index(sio)
  device = soundio_get_output_device(sio, default_out_device_index)

  outstream = soundio_outstream_create(device)
  discard soundio_outstream_open(outstream)

  outstream.write_callback = write_callback

  outstream.format = SoundIoFormatFloat32LE
  outstream.sample_rate = config.sampleRate.cint
  outstream.software_latency = 0.1

  if outstream.layout_error > 0:
    gLastError = "unable to set channel layout: " & $soundio_strerror(outstream.layout_error)

  gInitialised = true
  return true

proc startPlayback*(): bool =
  if not gInitialised:
    gLastError = "Not initialised"
    return false

  discard soundio_outstream_start(outstream)
  discard soundio_outstream_clear_buffer(outstream)
  return true

proc closeAudio*(): bool =
  if not gInitialised:
    gLastError = "Not initialised"
    return false

  soundio_outstream_destroy(outstream)
  soundio_device_unref(device)
  soundio_destroy(sio)

  gLastError = ""
  return true
