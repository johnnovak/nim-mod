import math, strformat

import fmod

import common
export common

var
  gInitialised = false
  gLastError = ""
  gAudioCallback: AudioCallback


proc pcmReadCallback(sound: ptr FmodSound, data: pointer,
                     datalen: cuint): FmodResult {.cdecl.} =

  setupForeignThreadGc()
  var audioBufferPtr = cast[AudioBufferPtr](data)
  var numFrames = (datalen div 4).int   # 16 bit * 2 channels
  gAudioCallback(audioBufferPtr, numFrames)
  return FMOD_OK


proc pcmSetPosCallback(sound: ptr FmodSound, subsound: cint, position: cuint,
                       postype: FmodTimeUnit): FmodResult {.cdecl.} =
  return FMOD_OK


proc checkResult(res: FmodResult) =
  if res != FMOD_OK:
    var errString = FMOD_ErrorString(res)
    echo(fmt"FMOD error! ({res}) {errString}")
    quit(QuitFailure)


var
  res: FmodResult
  system: ptr FmodSystem
  sound: ptr FmodSound
  channel: ptr FmodChannel
  mode = FMOD_OPENUSER or FMOD_LOOP_NORMAL or FMOD_CREATESTREAM
  exInfo: FmodCreateSoundExInfo


proc getLastError*(): string =
  result = gLastError

proc isInitialised*(): bool =
  result = gInitialised

proc initAudio*(audioCb: AudioCallback): bool =
  if gInitialised:
    return false

  res = create(system.addr)
  checkResult(res)

  res = system.init(2, FMOD_INIT_NORMAL, nil)
  checkResult(res)

  gAudioCallback = audioCb

  exInfo.cbSize            = sizeof(FmodCreateSoundExInfo).int32
  exInfo.numChannels       = 2                               # Number of channels in the sound.
  exInfo.defaultFrequency  = 44100                           # Default playback rate of sound.
  exInfo.decodeBufferSize  = 2048                             # Chunk size of stream update in samples. This will be the amount of data passed to the user callback.
  exInfo.length            = (exInfo.defaultfrequency * exInfo.numChannels * sizeof(int16) * 4).uint32 # Length of PCM data in bytes of whole song (for Sound::getLength)
  exInfo.format            = FMOD_SOUND_FORMAT_PCM16         # Data format of sound.
  exInfo.pcmReadCallback   = pcmReadCallback                 # User callback for reading.
  exInfo.pcmSetPosCallback = pcmSetPosCallback               # User callback for seeking.

  res = system.createSound(nil, mode, exInfo.addr, sound.addr)
  checkResult(res)
  gInitialised = true
  return true


proc startPlayback*(): bool =
  if not gInitialised:
    gLastError = "Not initialised"
    return false

  res = system.playSound(sound, nil, 0, channel.addr)
  checkResult(res)
  return true


proc closeAudio*(): bool =
  if not gInitialised:
    gLastError = "Not initialised"
    return false

  res = sound.release()
  checkResult(res)

  res = system.close()
  checkResult(res)

  res = system.release()
  checkResult(res)

  gLastError = ""
  return true

