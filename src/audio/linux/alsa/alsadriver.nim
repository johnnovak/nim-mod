import posix

import ../../common
export common

import alsa

# http://www.volkerschatz.com/noise/alsa.html

type
  AreasArray {.unchecked.} = array[1, ChannelArea]
  AreasArrayPtr = ptr AreasArray

let
  device = "plughw:0,0"

const
  NUM_CHANNELS = 2
  BYTES_PER_FRAME = 2

var
  gHandle: PcmPtr
  gOutput: SndOutputPtr

var
  format = SND_PCM_FORMAT_S16_LE
  rate = cuint(44100)
  buffer_time = cuint(30000)
  period_time = cuint(10000)
  freq = 110.0
  buffer_size: SFrames
  period_size: SFrames


proc setHwParams(handle: PcmPtr, params: HwParamsPtr,
                 access: PcmAccess): (cint, string) =

  var err: cint

  # choose all parameters
  err = snd_pcm_hw_params_any(ghandle, params)
  if err < 0:
    let msg =
      "Broken configuration for playback: no configurations available: " &
      $snd_strerror(err)
    return (err, msg)

  # set the interleaved read/write format
  err = snd_pcm_hw_params_set_access(handle, params, access)
  if err < 0:
    let msg = "Access type not available for playback: " &
              $snd_strerror(err)
    return (err, msg)

  # set the sample format
  err = snd_pcm_hw_params_set_format(handle, params, format)
  if err < 0:
    let msg = "Sample format not available for playback: " &
              $snd_strerror(err)
    return (err, msg)

  # set the count of channels
  err = snd_pcm_hw_params_set_channels(handle, params, NUM_CHANNELS)
  if err < 0:
    let msg = "Channels count (" & $NUM_CHANNELS &
              $") not available for playback: " & $snd_strerror(err)
    return (err, msg)

  # set the stream rate
  err = snd_pcm_hw_params_set_rate_near(handle, params, rate.addr, nil)
  if err < 0:
    let msg = "Rate " & $rate & "Hz not available for playback " &
               $snd_strerror(err)
    return (err, msg)

  # set the buffer time
  var dir: cint
  err = snd_pcm_hw_params_set_buffer_time_near(handle, params,
                                               buffer_time.addr, dir.addr)
  if err < 0:
    let msg = "Unable to set buffer time " & $buffer_time &
              " for playback: " & $snd_strerror(err)
    return (err, msg)

  var size: UFrames
  err = snd_pcm_hw_params_get_buffer_size(params, size.addr)
  if err < 0:
    let msg = "Unable to get buffer size for playback: "  & $snd_strerror(err)
    return (err, msg)

  buffer_size = SFrames(size)

  # set the period time
  err = snd_pcm_hw_params_set_period_time_near(handle, params,
                                               period_time.addr, dir.addr)
  if err < 0:
    let msg = "Unable to set period time " & $period_time &
              " for playback: " & $snd_strerror(err)
    return (err, msg)

  err = snd_pcm_hw_params_get_period_size(params, size.addr, dir.addr)
  if err < 0:
    let msg = "Unable to get period size for playback: " & $snd_strerror(err)
    return (err, msg)

  period_size = SFrames(size)

  # write the parameters to device
  err = snd_pcm_hw_params(handle, params)
  if err < 0:
    let msg = "Unable to set hw params for playback: " & $snd_strerror(err)
    return (err, msg)

  return (cint(0), "")


proc setSwParams(handle: PcmPtr, swparams: SwParamsPtr): (cint, string) =
  var err: cint

  # get the current swparams
  err = snd_pcm_sw_params_current(handle, swparams)
  if err < 0:
    let msg = "Unable to determine current swparams for playback: " &
              $snd_strerror(err)
    return (err, msg)

  # start the transfer when the buffer is almost full:
  # (buffer_size / avail_min) * avail_min
  let frames = UFrames((buffer_size / period_size).SFrames * period_size)
  err = snd_pcm_sw_params_set_start_threshold(handle, swparams, frames)
  if err < 0:
    let msg = "Unable to set start threshold mode for playback: " &
              $snd_strerror(err)
    return (err, msg)

  # allow the transfer when at least period_size samples can be processed or
  # disable this mechanism when period event is enabled (aka interrupt like
  # style processing)
  err = snd_pcm_sw_params_set_avail_min(handle, swparams,
                                        UFrames(period_size))
  if err < 0:
    let msg = "Unable to set avail min for playback: " & $snd_strerror(err)
    return (err, msg)

  # write the parameters to the playback device */
  err = snd_pcm_sw_params(handle, swparams)
  if err < 0:
    let msg = "Unable to set sw params for playback: " & $snd_strerror(err)
    return (err, msg)

  return (cint(0), "")


var ESTRPIPE* {.importc, header: "<errno.h>".}: cint

proc xrun_recovery(handle: PcmPtr, err: cint): cint =
#  echo "stream recovery"
  var error: cint

  if err == -EPIPE:     # under-run
    error = snd_pcm_prepare(handle)
    if error < 0:
      echo "Can't recovery from underrun, prepare failed: " &
           $snd_strerror(error)
    return 0

  elif err == -ESTRPIPE:
    error = snd_pcm_resume(handle)
    while error == -EAGAIN:
      discard sleep(1)       # wait until the suspend flag is released
      error = snd_pcm_resume(handle)

    if error < 0:
      error = snd_pcm_prepare(handle)
      if error < 0:
        echo "Can't recovery from suspend, prepare failed: " &
              $snd_strerror(error)
    return 0

  return error


proc async_direct_callback(ahandler: AsyncHandlerPtr) {.cdecl.} =
  var handle = snd_async_handler_get_pcm(ahandler)
  var audioCallback = cast[AudioCallback](
      snd_async_handler_get_callback_private(ahandler))

  var
    first = false
    err: cint

  while true:
    var state = snd_pcm_state(handle)
    if state == SND_PCM_STATE_XRUN:
      err = xrun_recovery(handle, -EPIPE)
      if err < 0:
        echo "XRUN recovery failed: " & $snd_strerror(err)
        quit(1)

      first = true

    elif state == SND_PCM_STATE_SUSPENDED:
      err = xrun_recovery(handle, -ESTRPIPE)
      if err < 0:
        echo "SUSPEND recovery failed: " & $snd_strerror(err)
        quit(1)

    var avail = snd_pcm_avail_update(handle)
    if avail < 0:
      err = xrun_recovery(handle, avail.cint)
      if err < 0:
        echo "avail update failed: " & $snd_strerror(err)
        quit(1)

      first = true
      continue

    if avail < period_size:
      if first:
        first = false
        err = snd_pcm_start(handle)
        if err < 0:
          echo "Start error: " & $snd_strerror(err)
          quit(1)
      else:
        break
      continue

    var offset, frames, size: UFrames
    size = UFrames(period_size)

    while size > 0'u:
      frames = size

      var areas: AreasArrayPtr
      err = snd_pcm_mmap_begin(handle,
                               cast[ptr ChannelAreaPtr](areas.addr),
                               offset.addr, frames.addr)
      if err < 0:
        err = xrun_recovery(handle, err)
        if err < 0:
          echo "MMAP begin avail error: " & $snd_strerror(err)
          quit(1)

        first = true

      var buffer =
        cast[AudioBufferPtr](cast[ByteAddress](areas[0].address) +%
                             offset.int * NUM_CHANNELS * BYTES_PER_FRAME)

      audioCallback(buffer, frames.int)

      var commitres = snd_pcm_mmap_commit(handle, offset, frames)
      if commitres < 0 or UFrames(commitres) != frames:
        var error = cint(if commitres >= 0: -EPIPE else: commitres.int32)
        err = xrun_recovery(handle, error)
        if err < 0:
          echo "MMAP commit error: " & $snd_strerror(err)
          quit(1)

        first = true

      size -= frames


proc startPlayback(handle: PcmPtr,
                   audioCallback: AudioCallback): (bool, string) =
  var err, count: cint

  var ahandler: AsyncHandlerPtr
  err = snd_async_add_pcm_handler(ahandler.addr, handle,
                                  async_direct_callback,
                                  audioCallback)
  if err < 0:
    return (false, "Unable to register async handler")

  var
    offset, frames, size: UFrames
    commitres: SFrames
    areas: AreasArrayPtr

  for count in 1..2:
    size = UFrames(period_size)
    while size > 0'u:
      frames = size
      err = snd_pcm_mmap_begin(handle,
                               cast[ptr ChannelAreaPtr](areas.addr),
                               offset.addr, frames.addr)
      if err < 0:
        err = xrun_recovery(handle, err)
        if err < 0:
          return (false, "MMAP begin avail error: " & $snd_strerror(err))

      var buffer =
        cast[AudioBufferPtr](cast[ByteAddress](areas[0].address) +%
                             offset.int * NUM_CHANNELS * BYTES_PER_FRAME)

      audioCallback(buffer, frames.int)

      commitres = snd_pcm_mmap_commit(handle, offset, frames)

      if commitres < 0 or commitres.UFrames != frames:
        var error = cint(if commitres >= 0: -EPIPE else: commitres.int32)
        err = xrun_recovery(handle, error)
        if err < 0:
          return (false, "MMAP commit error: " & $snd_strerror(err))

      size -= frames

  err = snd_pcm_start(handle)
  if err < 0:
    return (false, "Start error: %s\n" & $snd_strerror(err))

  return (true, "")


var
  gInitialised = false
  gLastError = ""

proc getLastError*(): string =
  result = gLastError

proc isInitialised*(): bool =
  result = gInitialised

proc initAudio*(): bool =
  if gInitialised:
    return false

  var
    err: cint
    msg: string
    hwparams: HwParamsPtr
    swparams: SwParamsPtr

  discard snd_pcm_hw_params_malloc(hwparams.addr)
  discard snd_pcm_sw_params_malloc(swparams.addr)

  err = snd_output_stdio_attach(gOutput.addr, stdout, 0)
  if err < 0:
    gLastError = "Output failed: %s\n" & $snd_strerror(err)
    return false

  err = snd_pcm_open(gHandle.addr, device, SND_PCM_STREAM_PLAYBACK, 0)
  if err < 0:
    gLastError = "Playback open error: " & $snd_strerror(err)
    return false

  var errStr = ""
  (err, msg) = setHwParams(gHandle, hwparams, SND_PCM_ACCESS_MMAP_INTERLEAVED)
  if err < 0:
    gLastError = "Setting of hwparams failed: " & msg
    return false

  (err, msg) = setSwParams(gHandle, swparams)
  if err < 0:
    gLastError = "Setting of swparams failed: " & msg
    return false

  gInitialised = true
  gLastError = ""
  return true


proc getSampleRate*(): int =
  if gInitialised:
    result = int(rate)
  else:
    result = -1


proc startPlayback*(callback: AudioCallback): bool =
  if not gInitialised:
    gLastError = "Not initialised"
    return false

  let (ok, msg) = startPlayback(gHandle, callback)
  gLastError = msg
  result = ok


proc closeAudio*(): bool =
  if not gInitialised:
    gLastError = "Not initialised"
    return false

  discard snd_pcm_close(gHandle)

  gLastError = ""
  return true

