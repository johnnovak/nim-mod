{.deadCodeElim: on.}

const Lib = "libasound.so(|.2)(|.0.0)"

type
  PcmAccess* = enum
    # mmap access with simple interleaved channels
    SND_PCM_ACCESS_MMAP_INTERLEAVED = 0,
    # mmap access with simple non interleaved channels
    SND_PCM_ACCESS_MMAP_NONINTERLEAVED,
    # mmap access with complex placement
    SND_PCM_ACCESS_MMAP_COMPLEX,
    # snd_pcm_readi/snd_pcm_writei access
    SND_PCM_ACCESS_RW_INTERLEAVED,
    # snd_pcm_readn/snd_pcm_writen access
    SND_PCM_ACCESS_RW_NONINTERLEAVED

# PCM sample format
type
  PcmFormat* = enum
    SND_PCM_FORMAT_UNKNOWN = - 1,
    SND_PCM_FORMAT_S8 = 0,    # Signed 8 bit
    SND_PCM_FORMAT_U8,        # Unsigned 8 bit
    SND_PCM_FORMAT_S16_LE,    # Signed 16 bit Little Endian
    SND_PCM_FORMAT_S16_BE,    # Signed 16 bit Big Endian
    SND_PCM_FORMAT_U16_LE,    # Unsigned 16 bit Little Endian
    SND_PCM_FORMAT_U16_BE,    # Unsigned 16 bit Big Endian
    SND_PCM_FORMAT_S24_LE,    # Signed 24 bit Little Endian using
                              # low three bytes in 32-bit word
    SND_PCM_FORMAT_S24_BE,    # Signed 24 bit Big Endian using
                              # low three bytes in 32-bit word
    SND_PCM_FORMAT_U24_LE,    # Unsigned 24 bit Little Endian using
                              # low three bytes in 32-bit word
    SND_PCM_FORMAT_U24_BE,    # Unsigned 24 bit Big Endian using
                              # low three bytes in 32-bit word
    SND_PCM_FORMAT_S32_LE,    # Signed 32 bit Little Endian
    SND_PCM_FORMAT_S32_BE,    # Signed 32 bit Big Endian
    SND_PCM_FORMAT_U32_LE,    # Unsigned 32 bit Little Endian
    SND_PCM_FORMAT_U32_BE     # Unsigned 32 bit Big Endian

const
  SND_PCM_FORMAT_S16* = SND_PCM_FORMAT_S16_LE
  SND_PCM_FORMAT_U16* = SND_PCM_FORMAT_U16_LE
  SND_PCM_FORMAT_S24* = SND_PCM_FORMAT_S24_LE
  SND_PCM_FORMAT_U24* = SND_PCM_FORMAT_U24_LE
  SND_PCM_FORMAT_S32* = SND_PCM_FORMAT_S32_LE
  SND_PCM_FORMAT_U32* = SND_PCM_FORMAT_U32_LE

# PCM state
type
  PcmState* = enum
    SND_PCM_STATE_OPEN = 0,   # Open
    SND_PCM_STATE_SETUP,      # Setup installed
    SND_PCM_STATE_PREPARED,   # Ready to start
    SND_PCM_STATE_RUNNING,    # Running
    SND_PCM_STATE_XRUN,       # Stopped: underrun (playback) or
                              # overrun (capture) detected
    SND_PCM_STATE_DRAINING,   # Draining: running (playback) or
                              # stopped (capture)
    SND_PCM_STATE_PAUSED,     # Paused
    SND_PCM_STATE_SUSPENDED,  # Hardware is suspended
    SND_PCM_STATE_DISCONNECTED# Hardware is disconnected

# PCM stream (direction)
type
  PcmStream* = enum
    SND_PCM_STREAM_PLAYBACK = 0,
    SND_PCM_STREAM_CAPTURE

# PCM area specification
type
  ChannelArea* = object
    address*: pointer          # base address of channel samples
    first*: cuint              # offset to first sample in bits
    step*: cuint               # samples distance in bits

  ChannelAreaPtr* = ptr ChannelArea

type
  SFrames* = clong
  UFrames* = culong

type
  HwParams* {.pure, final.} = object
  HwParamsPtr* = ptr HwParams

  SwParams* {.pure, final.} = object
  SwParamsPtr* = ptr SwParams

  Pcm* {.pure, final.} = object
  PcmPtr* = ptr Pcm

  SndOutput* {.pure, final.} = object
  SndOutputPtr* = ptr SndOutput

  AsyncHandler* {.pure, final.} = object
  AsyncHandlerPtr* = ptr AsyncHandler


type AsyncCallback* = proc (handler: AsyncHandlerPtr) {.cdecl.}


proc snd_async_add_pcm_handler*(handler: ptr AsyncHandlerPtr,
                                pcm: PcmPtr, callback: AsyncCallback,
                                private_data: pointer): cint
    {.cdecl, dynlib: Lib, importc: "snd_async_add_pcm_handler".}

proc snd_async_handler_get_callback_private*(handler: AsyncHandlerPtr): pointer
    {.cdecl, dynlib: Lib, importc: "snd_async_handler_get_callback_private".}

proc snd_async_handler_get_pcm*(handler: ptr AsyncHandler): PcmPtr
    {.cdecl, dynlib: Lib, importc: "snd_async_handler_get_pcm".}

proc snd_pcm_avail_update*(pcm: PcmPtr): SFrames
    {.cdecl, dynlib: Lib, importc: "snd_pcm_avail_update".}

proc snd_pcm_close*(pcm: PcmPtr): cint
    {.cdecl, dynlib: Lib, importc: "snd_pcm_close".}

proc snd_pcm_dump*(pcm: PcmPtr, output: SndOutputPtr): cint
    {.cdecl, dynlib: Lib, importc: "snd_pcm_dump".}

proc snd_pcm_format_name*(format: PcmFormat): cstring
    {.cdecl, dynlib: Lib, importc: "snd_pcm_format_name".}

proc snd_pcm_format_physical_width*(format: PcmFormat): cint
    {.cdecl, dynlib: Lib, importc: "snd_pcm_format_physical_width".}

proc snd_pcm_hw_params*(pcm: PcmPtr, params: HwParamsPtr): cint
    {.cdecl, dynlib: Lib, importc: "snd_pcm_hw_params".}

proc snd_pcm_hw_params_malloc*(hwptr: ptr HwParamsPtr): cint
    {.cdecl, dynlib: Lib, importc: "snd_pcm_hw_params_malloc".}

proc snd_pcm_hw_params_any*(pcm: PcmPtr, params: HwParamsPtr): cint
    {.cdecl, dynlib: Lib, importc: "snd_pcm_hw_params_any".}

proc snd_pcm_hw_params_get_buffer_size*(params: HwParamsPtr,
                                        val: ptr UFrames): cint
    {.cdecl, dynlib: Lib, importc: "snd_pcm_hw_params_get_buffer_size".}

proc snd_pcm_hw_params_get_period_size*(params: HwParamsPtr,
                                        frames: ptr UFrames,
                                        dir: ptr cint): cint
    {.cdecl, dynlib: Lib, importc: "snd_pcm_hw_params_get_period_size".}

proc snd_pcm_hw_params_set_access*(pcm: PcmPtr,
                                   params: HwParamsPtr,
                                   access: PcmAccess): cint
   {.cdecl, dynlib: Lib, importc: "snd_pcm_hw_params_set_access".}

proc snd_pcm_hw_params_set_buffer_time_near*(pcm: PcmPtr,
                                             params: HwParamsPtr,
                                             val: ptr cuint,
                                             dir: ptr cint): cint
   {.cdecl, dynlib: Lib, importc: "snd_pcm_hw_params_set_buffer_time_near".}

proc snd_pcm_hw_params_set_channels*(pcm: PcmPtr,
                                     params: HwParamsPtr, val: cuint): cint
    {.cdecl, dynlib: Lib, importc: "snd_pcm_hw_params_set_channels".}

proc snd_pcm_hw_params_set_format*(pcm: PcmPtr, params: HwParamsPtr,
                                   val: PcmFormat): cint
    {.cdecl, dynlib: Lib, importc: "snd_pcm_hw_params_set_format".}

proc snd_pcm_hw_params_set_rate_near*(pcm: PcmPtr,
                                      params: HwParamsPtr,
                                      val: ptr cuint, dir: ptr cint): cint
    {.cdecl, dynlib: Lib, importc: "snd_pcm_hw_params_set_rate_near".}

proc snd_pcm_hw_params_set_period_time_near*(pcm: PcmPtr, params: HwParamsPtr,
                                             val: ptr cuint,
                                             dir: ptr cint): cint
    {.cdecl, dynlib: Lib, importc: "snd_pcm_hw_params_set_period_time_near".}

proc snd_pcm_mmap_begin*(pcm: PcmPtr, areas: ptr ChannelAreaPtr,
                         offset: ptr UFrames,
                         frames: ptr UFrames): cint
    {.cdecl, dynlib: Lib, importc: "snd_pcm_mmap_begin".}

proc snd_pcm_mmap_commit*(pcm: PcmPtr, offset: UFrames,
                         frames: UFrames): SFrames
    {.cdecl, dynlib: Lib, importc: "snd_pcm_mmap_commit".}

proc snd_pcm_open*(pcm: ptr PcmPtr, name: cstring, stream: PcmStream,
                   mode: cint): cint
    {.cdecl, dynlib: Lib, importc: "snd_pcm_open".}

proc snd_pcm_prepare*(pcm: PcmPtr): cint
    {.cdecl, dynlib: Lib, importc: "snd_pcm_prepare".}

proc snd_pcm_resume*(pcm: PcmPtr): cint
    {.cdecl, dynlib: Lib, importc: "snd_pcm_resume".}

proc snd_pcm_start*(pcm: PcmPtr): cint
    {.cdecl, dynlib: Lib, importc: "snd_pcm_start".}

proc snd_pcm_drop*(pcm: PcmPtr): cint
    {.cdecl, dynlib: Lib, importc: "snd_pcm_drop".}

proc snd_pcm_drain*(pcm: PcmPtr): cint
    {.cdecl, dynlib: Lib, importc: "snd_pcm_drain".}

proc snd_pcm_pause*(pcm: PcmPtr, enable: cint): cint
    {.cdecl, dynlib: Lib, importc: "snd_pcm_pause".}

proc snd_pcm_state*(pcm: PcmPtr): PcmState
    {.cdecl, dynlib: Lib, importc: "snd_pcm_state".}

proc snd_pcm_sw_params*(pcm: PcmPtr, params: SwParamsPtr): cint
    {.cdecl, dynlib: Lib, importc: "snd_pcm_sw_params".}

proc snd_pcm_sw_params_malloc*(swptr: ptr SwParamsPtr): cint
    {.cdecl, dynlib: Lib, importc: "snd_pcm_sw_params_malloc".}

proc snd_pcm_sw_params_current*(pcm: PcmPtr, params: SwParamsPtr): cint
    {.cdecl, dynlib: Lib, importc: "snd_pcm_sw_params_current".}

proc snd_pcm_sw_params_set_avail_min*(pcm: PcmPtr,
                                     params: SwParamsPtr,
                                     val: UFrames): cint
    {.cdecl, dynlib: Lib, importc: "snd_pcm_sw_params_set_avail_min".}

proc snd_pcm_sw_params_set_start_threshold*(pcm: PcmPtr,
                                            params: SwParamsPtr,
                                            val: UFrames): cint
    {.cdecl, dynlib: Lib, importc: "snd_pcm_sw_params_set_start_threshold".}

proc snd_pcm_writei*(pcm: PcmPtr, buffer: pointer, size: UFrames): SFrames
    {.cdecl, dynlib: Lib, importc: "snd_pcm_writei".}

proc snd_output_stdio_attach*(outputp: ptr SndOutputPtr, f: File,
                              close: cint): cint
    {.cdecl, dynlib: Lib, importc: "snd_output_stdio_attach".}

proc snd_strerror*(errnum: cint): cstring
    {.cdecl, dynlib: Lib, importc: "snd_strerror".}

