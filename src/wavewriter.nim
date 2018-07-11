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


proc write(f: File, dest: pointer, len: Natural) =
  let numBytesWritten = f.writeBuffer(dest, len)
  if numBytesWritten != len:
    raise newException(WaveWriterError, "Error writing WAVE file")

proc writeChunkId(f: File, id: string) =
  var buf = id
  write(f, buf[0].addr, 4)

proc writeInt16LE(f: File, n: int) =
  var i = n.int16
  var buf: array[2, uint8]
  littleEndian16(buf[0].addr, i.addr)
  write(f, buf, 2)

proc writeInt32LE(f: File, n: int) =
  var i = n.int32
  var buf: array[4, uint8]
  littleEndian32(buf[0].addr, i.addr)
  write(f, buf, 4)


proc writeHeaders*(f: File, sampleRate: Natural, sampleFormat: SampleFormat,
                   numChannels: Natural, numDataBytes: Natural) =
  ## Call this with the correct parameters to write the WAVE file headers to
  ## a new file. After that, write ``numDataBytes`` length of bytes (must be
  ## even) of sample data in little-endian format.

  # Master RIFF chunk
  var chunkSize = CHUNK_ID_SIZE +
                  CHUNK_HEADER_SIZE + FORMAT_CHUNK_SIZE +
                  CHUNK_HEADER_SIZE + numDataBytes

  f.writeChunkId("RIFF")
  f.writeInt32LE(chunkSize)
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
  f.writeInt16LE(FORMAT_CHUNK_SIZE)
  f.writeInt16LE(formatTag)
  f.writeInt16LE(numChannels)
  f.writeInt32LE(sampleRate)
  f.writeInt32LE(avgBytesPerSec)
  f.writeInt16LE(blockAlign)
  f.writeInt16LE(bitsPerSample)

var gWriteBuf: seq[uint8]

proc writeDataStart*(format: SampleFormat, bufSizeInSamples: Natural = 4096) =
  case format
  of sf16Bit:      newSeq(gWriteBuf, bufSizeInSamples * 2)
  of sf24Bit:      newSeq(gWriteBuf, bufSizeInSamples * 3)
  of sf32BitFloat: newSeq(gWriteBuf, bufSizeInSamples * 4)

proc writeData16Bit*(f: File, data: openArray[int16], numSamples: Natural) =
  var dataPos = 0
  var bufPos = 0


  littleEndian16(gWriteBuf[bufPos].addr, data[dataPos].addr)
  inc(dataPos)
  inc(bufPos, 2)
  if bufPos >= gWriteBuf.len
    f.write(


proc writeData24Bit*(f: File, data: openArray[int32], numSamples: Natural) =

proc writeData32BitFloat*(f: File, data: openArray[float32],
                          numSamples: Natural) = 
