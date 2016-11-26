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


when defined(windows):
  proc kbhit(): cint {.importc: "_kbhit", header: "<conio.h>".}
  proc getch(): cint {.importc: "_getch", header: "<conio.h>".}

  proc getKeyInit*()   = discard
  proc getKeyDeinit*() = discard

  proc getKey*(): int =
    var key = keyNone

    if kbhit() > 0:
      let c = getch()
      case c:
      of   0:
        discard getch()  # ignore unknown 2-key keycodes

      of   8: key = keyBackspace
      of   9: key = keyTab
      of  13: key = keyEnter
      of  32: key = keySpace

      of 224:
        case getch():
        of 72: key = keyUpArrow
        of 75: key = keyLeftArrow
        of 77: key = keyRightArrow
        of 80: key = keyDownArrow
        else: discard  # ignore unknown 2-key keycodes

      else:
        key = c

    result = key


else:  # OSX & Linux
  import posix, termios

  # TODO can be removed on OSX?
#  proc setBuf(f: File, p: pointer) {.importc: "setbuf", header: "<stdio.h>".}

  proc nonblock(enabled: bool) =
    var ttyState: Termios

    # get the terminal state
    discard tcGetAttr(STDIN_FILENO, ttyState.addr)

    if enabled:
      # turn off canonical mode & echo
      ttyState.c_lflag = ttyState.c_lflag and not Cflag(ICANON or ECHO)

      # minimum of number input read
      ttyState.c_cc[VMIN] = 0.cuchar

    else:
      # turn on canonical mode
      ttyState.c_lflag = ttyState.c_lflag or ICANON

    # set the terminal attributes.
    discard tcSetAttr(STDIN_FILENO, TCSANOW, ttyState.addr)

  # TODO can be removed on OSX?
#    setBuf(stdin, nil)


  proc getKeyInit*() =
    nonblock(true)

  proc getKeyDeinit*() =
    nonblock(false)

  # surely a 20 char buffer is more than enough; the longest
  # keycode sequence I've seen was 6 chars
  const KEY_SEQUENCE_MAXLEN = 20

  # global keycode buffer
  var keyBuf: array[KEY_SEQUENCE_MAXLEN, int]

  proc parseKey(charsRead: int): int =
    # With help from
    # https://github.com/mcandre/charm/blob/master/lib/charm.c
    var key = keyNone

    case keyBuf[0]:
    of   9: key = keyTab
    of  10: key = keyEnter
    of  32: key = keySpace
    of 127: key = keyBackspace

    of  27:
      if charsRead == 1:  # escape key was hit
        key = keyEscape
      else:  # interpret escape sequence
        case keyBuf[1]:
        of 79, 91:
          case keyBuf[2]:
          of 65: key = keyUpArrow
          of 66: key = keyDownArrow
          of 67: key = keyRightArrow
          of 68: key = keyLeftArrow
          else: discard  # ignore unknown sequences
        else: discard  # ignore unknown sequences

    of   0: discard  # ignore ctrl shortcuts that have no equivalent
    of  29: discard  # on windows
    of  30: discard
    of  31: discard

    # mention http://www.leonerd.org.uk/code/libtermkey/
    # TODO function keys
    # http://aperiodic.net/phil/archives/Geekery/term-function-keys.html
    # TODO vt100
    # http://www.comptechdoc.org/os/linux/howlinuxworks/linux_hlvt100.html

    else:
      key = keyBuf[0]  # no special handling, just return whatever
                       # was received
    result = key


  proc getKey*(): int =
    var i = 0
    while i < KEY_SEQUENCE_MAXLEN:
      var ret = read(0, keyBuf[i].addr, 1)
      if ret > 0:
        i += 1
      else:
        break

    if i == 0:  # nothing read
      result = keyNone
    else:
      result = parseKey(i)

