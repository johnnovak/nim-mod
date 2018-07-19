import endians, strformat

type
  WaveWriter* = object
    sampleFormat: SampleFormat
    sampleRate:   Natural
    numChannels:  Natural
    filename:     string
    file:         File
    dataLen:      Natural
    fileLen:      Natural
    writeBuf:     seq[uint8]

  SampleFormat* = enum
    sf16Bit, sf24Bit, sf32BitFloat

  WaveWriterError* = object of Exception

const
  RIFF_HEADER_SIZE  = 12
  CHUNK_ID_SIZE     = 4
  CHUNK_HEADER_SIZE = 8
  FORMAT_CHUNK_SIZE = 16

  WAVE_FORMAT_PCM = 1
  WAVE_FORMAT_IEEE_FLOAT = 3

  RIFF_CHUNK_SIZE_OFFSET = 4
  DATA_CHUNK_SIZE_OFFSET = RIFF_HEADER_SIZE +
                           CHUNK_HEADER_SIZE + FORMAT_CHUNK_SIZE +
                           CHUNK_ID_SIZE


proc sampleFormat*(ww: WaveWriter): SampleFormat = ww.sampleFormat
proc sampleRate*(ww: WaveWriter): Natural = ww.sampleRate
proc numChannels*(ww: WaveWriter): Natural = ww.numChannels
proc filename*(ww: WaveWriter): string = ww.filename
proc dataLen*(ww: WaveWriter): Natural = ww.dataLen
proc fileLen*(ww: WaveWriter): Natural = ww.fileLen


proc initWaveWriter*(filename: string, sampleFormat: SampleFormat,
                     sampleRate: Natural, numChannels: Natural,
                     bufSizeInSamples: Natural = 4096): WaveWriter =
  var ww: WaveWriter
  ww.sampleFormat = sampleFormat
  ww.sampleRate = sampleRate
  ww.numChannels = numChannels

  ww.filename = filename
  if not open(ww.file, ww.filename, fmWrite):
    raise newException(WaveWriterError, "Error opening file for writing")

  case ww.sampleFormat
  of sf16Bit:      newSeq(ww.writeBuf, bufSizeInSamples * 2)
  of sf24Bit:      newSeq(ww.writeBuf, bufSizeInSamples * 3)
  of sf32BitFloat: newSeq(ww.writeBuf, bufSizeInSamples * 4)
  result = ww


proc writeBuffer(ww: var WaveWriter, dest: pointer, numBytes: Natural) =
  let numBytesWritten = writeBuffer(ww.file, dest, numBytes)
  if numBytesWritten != numBytes:
    raise newException(WaveWriterError, "Error writing file")
  inc(ww.fileLen, numBytes)

proc writeChunkId(ww: var WaveWriter, id: string) =
  var buf = id
  ww.writeBuffer(buf[0].addr, 4)

proc writeUInt16LE(ww: var WaveWriter, n: uint16) =
  var i = n.int16
  var buf: array[2, uint8]
  littleEndian16(buf[0].addr, i.addr)
  ww.writeBuffer(buf[0].addr, 2)

proc writeUInt32LE(ww: var WaveWriter, n: uint32) =
  var i = n.int32
  var buf: array[4, uint8]
  littleEndian32(buf[0].addr, i.addr)
  ww.writeBuffer(buf[0].addr, 4)

proc raiseNotInitalisedError() =
  raise newException(WaveWriterError, "Wave writer is not initialised")


proc writeHeaders*(ww: var WaveWriter, numDataBytes: Natural = 0) =
  if ww.file == nil:
    raiseNotInitalisedError()

  # Master RIFF chunk
  var chunkSize = CHUNK_ID_SIZE +
                  CHUNK_HEADER_SIZE + FORMAT_CHUNK_SIZE +
                  CHUNK_HEADER_SIZE + numDataBytes

  ww.writeChunkId("RIFF")
  ww.writeUInt32LE(chunkSize.uint32)
  ww.writeChunkId("WAVE")

  # Format chunk
  var formatTag: uint16
  var bitsPerSample: uint16

  case ww.sampleFormat
  of sf16Bit:      formatTag = WAVE_FORMAT_PCM;        bitsPerSample = 16
  of sf24Bit:      formatTag = WAVE_FORMAT_PCM;        bitsPerSample = 24
  of sf32BitFloat: formatTag = WAVE_FORMAT_IEEE_FLOAT; bitsPerSample = 32

  var blockAlign = (ww.numChannels.uint16 * bitsPerSample div 8).uint16
  var avgBytesPerSec = ww.sampleRate.uint32 * blockAlign

  ww.writeChunkId("fmt ")
  ww.writeUInt32LE(FORMAT_CHUNK_SIZE)
  ww.writeUInt16LE(formatTag)
  ww.writeUInt16LE(ww.numChannels.uint16)
  ww.writeUInt32LE(ww.sampleRate.uint32)
  ww.writeUInt32LE(avgBytesPerSec)
  ww.writeUInt16LE(blockAlign)
  ww.writeUInt16LE(bitsPerSample)

  # Data chunk (header only)
  ww.writeChunkId("data")

  chunkSize = numDataBytes  # the padding should NOT be added to the chunk size!
  ww.writeUInt32LE(chunkSize.uint32)


proc writeData16Bit(ww: var WaveWriter, data: var openArray[uint8]) =
  assert data.len mod 2 == 0
  const bytesPerSample = 2
  var bufPos = 0
  let bufLen = ww.writeBuf.len

  var i = 0
  while i < data.len:
    littleEndian16(ww.writeBuf[bufPos].addr, data[i].addr)
    inc(bufPos, bytesPerSample)
    inc(i, bytesPerSample)
    if bufPos >= bufLen:
      ww.writeBuffer(ww.writeBuf[0].addr, bufLen)
      bufPos = 0

  if bufPos > 0:
    ww.writeBuffer(ww.writeBuf[0].addr, bufPos - bytesPerSample)


proc writeData24Bit*(ww: var WaveWriter, data: var openArray[uint8]) =
  assert data.len mod 3 == 0
  const bytesPerSample = 3
  var bufPos = 0
  let bufLen = ww.writeBuf.len
  var int32Buf: array[4, uint8]

  var i = 0
  while i < data.len:
    littleEndian32(int32Buf[0].addr, data[i].addr)
    ww.writeBuf[bufPos  ] = int32Buf[1]
    ww.writeBuf[bufPos+1] = int32Buf[2]
    ww.writeBuf[bufPos+2] = int32Buf[3]
    inc(bufPos, bytesPerSample)
    inc(i, bytesPerSample)

    if bufPos >= bufLen:
      ww.writeBuffer(ww.writeBuf[0].addr, bufLen)
      bufPos = 0

  if bufPos > 0:
    ww.writeBuffer(ww.writeBuf[0].addr, bufPos - bytesPerSample)


proc writeData32BitFloat*(ww: var WaveWriter, data: var openArray[uint8]) =
  assert data.len mod 4 == 0
  const bytesPerSample = 4
  var bufPos = 0
  let bufLen = ww.writeBuf.len

  var i = 0
  while i < data.len:
    littleEndian32(ww.writeBuf[bufPos].addr, data[i].addr)
    inc(bufPos, bytesPerSample)
    inc(i, bytesPerSample)
    if bufPos >= bufLen:
      ww.writeBuffer(ww.writeBuf[0].addr, bufLen)
      bufPos = 0

  if bufPos > 0:
    ww.writeBuffer(ww.writeBuf[0].addr, bufPos - bytesPerSample)


proc writeData*(ww: var WaveWriter, data: var openArray[uint8]) =
  if ww.file == nil:
    raiseNotInitalisedError()

  case ww.sampleFormat:
  of sf16Bit:      writeData16Bit(ww, data)
  of sf24Bit:      writeData24Bit(ww, data)
  of sf32BitFloat: writeData32BitFloat(ww, data)
  inc(ww.dataLen, data.len)


proc updateHeaders*(ww: var WaveWriter) =
  if ww.file == nil:
    raiseNotInitalisedError()

  if ww.dataLen mod 2 == 1:
    var pad: uint8 = 0
    ww.writeBuffer(pad.addr, 1)

  ww.file.setFilePos(RIFF_CHUNK_SIZE_OFFSET)
  ww.writeUInt32LE((ww.fileLen - 8).uint32)

  ww.file.setFilePos(DATA_CHUNK_SIZE_OFFSET)
  ww.writeUInt32LE(ww.dataLen.uint32)


proc close*(ww: var WaveWriter) =
  if ww.file == nil:
    raiseNotInitalisedError()

  ww.file.close()
  ww.filename = ""
  ww.file = nil
  ww.dataLen = 0
  ww.fileLen = 0

