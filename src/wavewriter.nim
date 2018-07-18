import endians

type
  SampleFormat* = enum
    sf16Bit, sf24Bit, sf32BitFloat

type WaveWriterError* = object of Exception


const
  CHUNK_ID_SIZE     = 4
  CHUNK_HEADER_SIZE = 8
  FORMAT_CHUNK_SIZE = 16

  WAVE_FORMAT_PCM = 1
  WAVE_FORMAT_IEEE_FLOAT = 3

  DATA_CHUNK_SIZE_OFFSET = CHUNK_ID_SIZE +
                           CHUNK_HEADER_SIZE + FORMAT_CHUNK_SIZE +



proc writeBuf(f: File, dest: pointer, numBytes: Natural) =
  let numBytesWritten = f.writeBuffer(dest, numBytes)
  if numBytesWritten != numBytes:
    raise newException(WaveWriterError, "Error writing WAVE file")

proc writeChunkId(f: File, id: string) =
  var buf = id
  f.writeBuf(buf[0].addr, 4)

proc writeUInt16LE(f: File, n: uint16) =
  var i = n.int16
  var buf: array[2, uint8]
  littleEndian16(buf[0].addr, i.addr)
  f.writeBuf(buf[0].addr, 2)

proc writeUInt32LE(f: File, n: uint32) =
  var i = n.int32
  var buf: array[4, uint8]
  littleEndian32(buf[0].addr, i.addr)
  f.writeBuf(buf[0].addr, 4)


proc writeHeaders*(f: File, sampleRate: Natural, sampleFormat: SampleFormat,
                   numChannels: Natural, numDataBytes: Natural = 0) =
  ## Call this with the correct parameters to write the WAVE file headers to
  ## a new file. After that, write ``numDataBytes`` length of bytes (must be
  ## even) of sample data in little-endian format.

  # Master RIFF chunk
  var chunkSize = CHUNK_ID_SIZE +
                  CHUNK_HEADER_SIZE + FORMAT_CHUNK_SIZE +
                  CHUNK_HEADER_SIZE + numDataBytes

  f.writeChunkId("RIFF")
  f.writeUInt32LE(chunkSize.uint32)
  f.writeChunkId("WAVE")

  # Format chunk
  var formatTag: uint16
  var bitsPerSample: uint16

  case sampleFormat
  of sf16Bit:      formatTag = WAVE_FORMAT_PCM;        bitsPerSample = 16
  of sf24Bit:      formatTag = WAVE_FORMAT_PCM;        bitsPerSample = 24
  of sf32BitFloat: formatTag = WAVE_FORMAT_IEEE_FLOAT; bitsPerSample = 32

  var blockAlign = numChannels.uint16 * bitsPerSample div 8
  var avgBytesPerSec = sampleRate.uint16 * blockAlign

  f.writeChunkId("fmt ")
  f.writeUInt16LE(FORMAT_CHUNK_SIZE)
  f.writeUInt16LE(formatTag)
  f.writeUInt16LE(numChannels.uint16)
  f.writeUInt32LE(sampleRate.uint32)
  f.writeUInt32LE(avgBytesPerSec)
  f.writeUInt16LE(blockAlign)
  f.writeUInt16LE(bitsPerSample)

  # Data chunk (header only)
  f.writeChunkId("data")

  chunkSize = numDataBytes  # the padding should NOT be added to the chunk size!
  f.writeUInt32LE(chunkSize.uint32)


var gWriteBuf: seq[uint8]

proc writeDataStart*(format: SampleFormat, bufSizeInSamples: Natural = 4096) =
  case format
  of sf16Bit:      newSeq(gWriteBuf, bufSizeInSamples * 2)
  of sf24Bit:      newSeq(gWriteBuf, bufSizeInSamples * 3)
  of sf32BitFloat: newSeq(gWriteBuf, bufSizeInSamples * 4)

proc writeData16Bit*(f: File, data: var openArray[uint8], dataLen: Natural) =
  assert dataLen mod 2 == 0
  const bytesPerSample = 2
  var bufPos = 0
  let bufLen = gWriteBuf.len - (gWriteBuf.len mod bytesPerSample)

  var i = 0
  while i <  dataLen:
    littleEndian16(gWriteBuf[bufPos].addr, data[i].addr)
    inc(bufPos, bytesPerSample)
    inc(i, bytesPerSample)
    if bufPos >= bufLen:
      f.writeBuf(gWriteBuf[0].addr, bufLen)
      bufPos = 0

  if bufPos > 0:
    f.writeBuf(gWriteBuf[0].addr, bufPos - bytesPerSample)


proc writeData24Bit*(f: File, data: var openArray[int32], numBytes: Natural) =
  const bytesPerSample = 3
  var bufPos = 0
  let bufLen = gWriteBuf.len - (gWriteBuf.len mod bytesPerSample)
  var int32Buf: array[4, uint8]

  for i in 0..<numBytes:
    littleEndian32(int32Buf[0].addr, data[i].addr)
    copyMem(gWriteBuf[bufPos].addr, int32Buf[0].addr, bytesPerSample)
    inc(bufPos, bytesPerSample)

    if bufPos >= bufLen:
      f.writeBuf(gWriteBuf[0].addr, bufLen)
      bufPos = 0

  if bufPos > 0:
    f.writeBuf(gWriteBuf[0].addr, bufPos - bytesPerSample)

  # Must write a padding a byte if the number of data bytes is odd
  if numBytes mod 2 == 1:
    gWriteBuf[0] = 0
    f.writeBuf(gWriteBuf[0].addr, 1)


proc writeData32BitFloat*(f: File, data: var openArray[float32],
                          numBytes: Natural) =
  const bytesPerSample = 4
  var bufPos = 0
  let bufLen = gWriteBuf.len - (gWriteBuf.len mod bytesPerSample)

  for i in 0..<numBytes:
    littleEndian32(gWriteBuf[bufPos].addr, data[i].addr)
    inc(bufPos, bytesPerSample)

    if bufPos >= bufLen:
      f.writeBuf(gWriteBuf[0].addr, bufLen)
      bufPos = 0

  if bufPos > 0:
    f.writeBuf(gWriteBuf[0].addr, bufPos - bytesPerSample)

