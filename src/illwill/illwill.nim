import os, terminal


const keyNone* = -1

const keyCtrlA* = 1
const keyCtrlB* = 2
const keyCtrlD* = 4
const keyCtrlE* = 5
const keyCtrlF* = 6
const keyCtrlG* = 7
const keyCtrlH* = 8
const keyCtrlJ* = 10
const keyCtrlK* = 11
const keyCtrlL* = 12
const keyCtrlN* = 14
const keyCtrlO* = 15
const keyCtrlP* = 16
const keyCtrlQ* = 17
const keyCtrlR* = 18
const keyCtrlS* = 19
const keyCtrlT* = 20
const keyCtrlU* = 21
const keyCtrlV* = 22
const keyCtrlW* = 23
const keyCtrlX* = 24
const keyCtrlY* = 25
const keyCtrlZ* = 26

const keyCtrlBackslash*    = 28
const keyCtrlCloseBracket* = 29

const keyTab*        = 9
const keyEnter*      = 13
const keyEscape*     = 27
const keySpace*      = 32
const keyBackspace*  = 127

const keyUpArrow*    = 1001
const keyDownArrow*  = 1002
const keyRightArrow* = 1003
const keyLeftArrow*  = 1004

const keyHome*       = 1005
const keyInsert*     = 1006
const keyDelete*     = 1007
const keyEnd*        = 1008
const keyPageUp*     = 1009
const keyPageDown*   = 1010

const keyF1*         = 1011
const keyF2*         = 1012
const keyF3*         = 1013
const keyF4*         = 1014
const keyF5*         = 1015
const keyF6*         = 1016
const keyF7*         = 1017
const keyF8*         = 1018
const keyF9*         = 1019
const keyF10*        = 1020
const keyF11*        = 1021
const keyF12*        = 1022


when defined(windows):
  import encodings, unicode, winlean

  proc kbhit(): cint {.importc: "_kbhit", header: "<conio.h>".}
  proc getch(): cint {.importc: "_getch", header: "<conio.h>".}

  proc consoleInit*()   = discard
  proc consoleDeinit*() = discard

  proc getKey*(): int =
    var key = keyNone

    if kbhit() > 0:
      let c = getch()
      case c:
      of   0:
        case getch():
        of 59: key = keyF1
        of 60: key = keyF2
        of 61: key = keyF3
        of 62: key = keyF4
        of 63: key = keyF5
        of 64: key = keyF6
        of 65: key = keyF7
        of 66: key = keyF8
        of 67: key = keyF9
        of 68: key = keyF10
        else: discard getch()  # ignore unknown 2-key keycodes

      of   8: key = keyBackspace
      of   9: key = keyTab
      of  13: key = keyEnter
      of  32: key = keySpace

      of 224:
        case getch():
        of  72: key = keyUpArrow
        of  75: key = keyLeftArrow
        of  77: key = keyRightArrow
        of  80: key = keyDownArrow

        of  71: key = keyHome
        of  82: key = keyInsert
        of  83: key = keyDelete
        of  79: key = keyEnd
        of  73: key = keyPageUp
        of  81: key = keyPageDown

        of 133: key = keyF11
        of 134: key = keyF12
        else: discard  # ignore unknown 2-key keycodes

      else:
        key = c

    result = key


  proc writeConsole(hConsoleOutput: HANDLE, lpBuffer: pointer,
                    nNumberOfCharsToWrite: DWORD,
                    lpNumberOfCharsWritten: ptr DWORD,
                    lpReserved: pointer): WINBOOL {.
    stdcall, dynlib: "kernel32", importc: "WriteConsoleW".}


  var hStdout = getStdHandle(STD_OUTPUT_HANDLE)
  var utf16LEConverter = open(destEncoding = "utf-16", srcEncoding = "UTF-8")

  proc put*(s: string) =
    stdout.write s
    #var us = utf16LEConverter.convert(s)
    #var numWritten: DWORD
    #discard writeConsole(hStdout, pointer(us[0].addr), DWORD(s.runeLen),
    #                     numWritten.addr, nil)


else:  # OSX & Linux
  import posix, tables, termios

  proc nonblock(enabled: bool) =
    when defined(macosx):   # until the termios lib is fixed
      let ECHO   = Cflag(0x00000008)
      let ICANON = Cflag(0x00000100)

    var ttyState: Termios

    # get the terminal state
    discard tcGetAttr(STDIN_FILENO, ttyState.addr)

    if enabled:
      # turn off canonical mode & echo
      ttyState.c_lflag = ttyState.c_lflag and not Cflag(ICANON or ECHO)

      # minimum of number input read
      ttyState.c_cc[VMIN] = 0.cuchar

    else:
      # turn on canonical mode & echo
      ttyState.c_lflag = ttyState.c_lflag or ICANON or ECHO

    # set the terminal attributes.
    discard tcSetAttr(STDIN_FILENO, TCSANOW, ttyState.addr)


  proc kbhit(): cint =
    var tv: Timeval
    tv.tv_sec = 0
    tv.tv_usec = 0

    var fds: TFdSet
    FD_ZERO(fds)
    FD_SET(STDIN_FILENO, fds)
    discard select(STDIN_FILENO+1, fds.addr, nil, nil, tv.addr)
    return FD_ISSET(STDIN_FILENO, fds)


  proc consoleInit*() =
    nonblock(true)

  proc consoleDeinit*() =
    nonblock(false)

  # surely a 20 char buffer is more than enough; the longest
  # keycode sequence I've seen was 6 chars
  const KEY_SEQUENCE_MAXLEN = 20

  # global keycode buffer
  var keyBuf: array[KEY_SEQUENCE_MAXLEN, int]

  let
    keySequences = {
      keyUpArrow:    @["\27OA", "\27[A"],
      keyDownArrow:  @["\27OB", "\27[B"],
      keyRightArrow: @["\27OC", "\27[C"],
      keyLeftArrow:  @["\27OD", "\27[D"],

      keyHome:       @["\27[1~", "\27[7~", "\27OH", "\27[H"],
      keyInsert:     @["\27[2~"],
      keyDelete:     @["\27[3~"],
      keyEnd:        @["\27[4~", "\27[8~", "\27OF", "\27[F"],
      keyPageUp:     @["\27[5~"],
      keyPageDown:   @["\27[6~"],

      keyF1:         @["\27[11~", "\27OP"],
      keyF2:         @["\27[12~", "\27OQ"],
      keyF3:         @["\27[13~", "\27OR"],
      keyF4:         @["\27[14~", "\27OS"],
      keyF5:         @["\27[15~"],
      keyF6:         @["\27[17~"],
      keyF7:         @["\27[18~"],
      keyF8:         @["\27[19~"],
      keyF9:         @["\27[20~"],
      keyF10:        @["\27[21~"],
      keyF11:        @["\27[23~"],
      keyF12:        @["\27[24~"]
    }.toTable

  proc parseKey(charsRead: int): int =
    # Inspired by
    # https://github.com/mcandre/charm/blob/master/lib/charm.c
    var key = keyNone

    if charsRead == 1:
      case keyBuf[0]:
      of   9: key = keyTab
      of  10: key = keyEnter
      of  27: key = keyEscape
      of  32: key = keySpace
      of 127: key = keyBackspace
      of 0, 29, 30, 31: discard   # these have no Windows equivalents so
                                  # we'll ignore them
      else:
        key = keyBuf[0]

    else:
      var inputSeq = ""
      for i in 0..<charsRead:
        inputSeq &= char(keyBuf[i])

      for k, sequences in keySequences.pairs:
        for s in sequences:
          if s == inputSeq:
            key = k

    result = key


  proc getKey*(): int =
    var i = 0
    while kbhit() > 0 and i < KEY_SEQUENCE_MAXLEN:
      var ret = read(0, keyBuf[i].addr, 1)
      if ret > 0:
        i += 1
      else:
        break

    if i == 0:  # nothing read
      result = keyNone
    else:
      result = parseKey(i)


  template put*(s: string) = stdout.write s


proc enterFullscreen*() =
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

proc exitFullscreen*() =
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

when defined(posix):
  # TODO doesn't work... why?
  onSignal(SIGTSTP):
    signal(SIGTSTP, SIG_DFL)
    exitFullscreen()
    resetAttributes()
    consoleDeinit()
    showCursor()
    discard `raise`(SIGTSTP)

  onSignal(SIGCONT):
    enterFullscreen()
    consoleInit()
    hideCursor()

