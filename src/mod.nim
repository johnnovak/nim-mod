import os, terminal
import getkey/getkey

include common
include loader
include display
include themes


gGfx = gfxCharsAscii

when defined(posix):
  if "utf" in getEnv("LANG").toLowerAscii:
    gGfx = gfxCharsUnicode

gTheme = themes[0]


proc enterFullscreen() =
  when defined(posix):
    case getEnv("TERM"):
    of "xterm-color":
      stdout.write "\e7\e[?47h"
    of "xterm-256color":
      stdout.write "\e[?1049h"
    else:
      eraseScreen()
  else:
    eraseScreen()

proc exitFullscreen() =
  when defined(posix):
    case getEnv("TERM"):
    of "xterm-color":
      stdout.write "\e[2J\e[?47l\e8"
    of "xterm-256color":
      stdout.write "\e[?1049l"
    else:
      eraseScreen()
  else:
    eraseScreen()

proc quitProc() {.noconv.} =
  resetAttributes()
  getKeyDeinit()
  exitFullscreen()
  showCursor()


proc main() =
  system.addQuitProc(quitProc)
  getKeyInit()
  enterFullscreen()
  hideCursor()

  var buf = readFile("../data/canalgreen.mod")
  let module = loadModule(buf)

  var
    currPattern = 0
    currRow = 0
    lastPattern = -1
    lastRow = -1

  while true:
    let key = getKey()

    case key:
    of keyUpArrow, ord('k'):
      currRow = max(currRow - 1, 0)
    of keyDownArrow, ord('j'):
      currRow = min(currRow + 1, ROWS_PER_PATTERN-1)
    of keyLeftArrow, ord('h'):
      currPattern = max(currPattern - 1, 0)
    of keyRightArrow, ord('l'):
      currPattern = min(currPattern + 1, module.patterns.high)
    of ord('q'):
      quit(0)
    else: discard

    setCursorPos(0, 0)
    if currPattern != lastPattern or currRow != lastRow:
      drawPatternView(module.patterns[currPattern],
                      currRow = currRow, maxRows = 32,
                      startTrack = 0, maxTracks = 4)
      lastPattern = currPattern
      lastRow = currRow

    sleep(1)

main()
