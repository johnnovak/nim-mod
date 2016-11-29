import os
import illwill

proc keyName(key: int): string =
  case key:
  of keyCtrlA: result = "CtrlA"
  of keyCtrlB: result = "CtrlB"
  of keyCtrlD: result = "CtrlD"
  of keyCtrlE: result = "CtrlE"
  of keyCtrlF: result = "CtrlF"
  of keyCtrlG: result = "CtrlG"
  of keyCtrlH: result = "CtrlH"
  of keyCtrlJ: result = "CtrlJ"
  of keyCtrlK: result = "CtrlK"
  of keyCtrlL: result = "CtrlL"
  of keyCtrlN: result = "CtrlN"
  of keyCtrlO: result = "CtrlO"
  of keyCtrlP: result = "CtrlP"
  of keyCtrlQ: result = "CtrlQ"
  of keyCtrlR: result = "CtrlR"
  of keyCtrlS: result = "CtrlS"
  of keyCtrlT: result = "CtrlT"
  of keyCtrlU: result = "CtrlU"
  of keyCtrlV: result = "CtrlV"
  of keyCtrlW: result = "CtrlW"
  of keyCtrlX: result = "CtrlX"
  of keyCtrlY: result = "CtrlY"
  of keyCtrlZ: result = "CtrlZ"

  of keyCtrlBackslash:    result = "CtrlBackslash"
  of keyCtrlCloseBracket: result = "CtrlCloseBracket"

  of keyBackspace:  result = "Backspace"
  of keyTab:        result = "Tab"
  of keyEnter:      result = "Enter"
  of keyEscape:     result = "Escape"
  of keySpace:      result = "Space"

  of keyUpArrow:    result = "UpArrow"
  of keyDownArrow:  result = "DownArrow"
  of keyRightArrow: result = "RightArrow"
  of keyLeftArrow:  result = "LeftArrow"

  of keyHome:       result = "Home"
  of keyInsert:     result = "Insert"
  of keyDelete:     result = "Delete"
  of keyEnd:        result = "End"
  of keyPageUp:     result = "PageUp"
  of keyPageDown:   result = "PageDown"

  of keyF1:  result = "F1"
  of keyF2:  result = "F2"
  of keyF3:  result = "F3"
  of keyF4:  result = "F4"
  of keyF5:  result = "F5"
  of keyF6:  result = "F6"
  of keyF7:  result = "F7"
  of keyF8:  result = "F8"
  of keyF9:  result = "F9"
  of keyF10: result = "F10"
  of keyF11: result = "F11"
  of keyF12: result = "F12"
  else:
    result = $cast[char](key)


consoleInit()

while true:
  var key = getKey()
  if key != keyNone:
    echo keyName(key)
  else:
    sleep(1)

consoleDeinit()

