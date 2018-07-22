import os, strutils, strformat, terminal

const
  TEST_PATH = "./"
  CMD_OPTS = "-o:wav -s:22050 -b:16 -a:-6 -w:50 -i:linear -d:off"
  EXPECTED_SUFFIX = "-EXPECTED"
  RESULT_SUFFIX = "-RESULT"

when defined(windows):
  const EXE_PATH = "..\\src\\main.exe"
else:
  const EXE_PATH = "../src/main"


proc deleteResults() =
  styledEcho(styleBright,
    fmt"Deleting previous test results in '{TEST_PATH}'...", resetStyle)
  for f in walkFiles(fmt"{TEST_PATH}/*{RESULT_SUFFIX}.wav"):
    removeFile(f)

proc displayError(msg: string) =
  styledEcho(fgRed, msg, resetStyle)

proc renderTest(testPath: string, wavPath: string): bool =
  let renderCmd = fmt"{EXE_PATH} {CMD_OPTS} -f:{wavPath} {testPath}"
  if execShellCmd(renderCmd) == QuitSuccess:
    result = true
  else:
    displayError(fmt"Rendering '{testPath}' to '{wavPath}' failed")
    result = false


proc diff(resultPath, expectedPath: string): bool =
  var f1, f2: FILE
  if not f1.open(resultPath):
    displayError(fmt"Cannot open file '{resultPath}'")
    return false
  if not f2.open(expectedPath):
    displayError(fmt"Cannot open file '{expectedPath}'")
    return false

  let resultSize = f1.getFileSize
  let expectedSize = f2.getFileSize
  if resultSize != expectedSize:
    displayError(fmt"File size mismatch, expected size: {expectedSize}, " &
                 fmt"result size: {resultSize}")
    return false

  const BUFSIZE = 8192
  var buf1, buf2: array[BUFSIZE, uint8]
  var bytesRemaining = resultSize

  while bytesRemaining > 0:
    let len = min(bytesRemaining, BUFSIZE)
    if f1.readBytes(buf1, 0, len) != len:
      displayError(fmt"Error reading file '{resultPath}'")
      return false
    if f2.readBytes(buf2, 0, len) != len:
      displayError(fmt"Error reading file '{expectedPath}'")
      return false

    if not equalMem(buf1[0].addr, buf2[0].addr, len):
      displayError(fmt"Expected and result WAV files differ")
      return false
    bytesRemaining -= len

  result = true


proc displayResult(testName: string, success: bool) =
  styledEcho(styleBright, "  Test ", fmt"'{testName}'", resetStyle)
  cursorUp()
  setCursorXPos(38)
  if success:
    styledEcho(fgGreen, styleBright, "[OK]")
  else:
    styledEcho(fgRed, styleBright, "[FAIL]")


proc executeTests() =
  styledEcho(styleBright, fmt"Executing tests in '{TEST_PATH}'...", resetStyle)

  for testPath in walkFiles(fmt"{TEST_PATH}/*.mod"):
    var testName = testPath
    testName.removeSuffix(".mod")
    testName = testName.split("/")[^1]

    let resultWavPath = fmt"{TEST_PATH}/{testName}{RESULT_SUFFIX}.wav"

    var success = renderTest(testPath, resultWavPath)
    if success:
      let expectedWavPath = fmt"{TEST_PATH}/{testName}{EXPECTED_SUFFIX}.wav"
      success = diff(resultWavPath, expectedWavPath)

    displayResult(testName, success)


deleteResults()
executeTests()

