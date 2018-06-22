import posix, termios

#include <stdio.h>
#include <unistd.h>
#include <termios.h>

# http://shtrom.ssji.net/skb/getc.html

proc getChar(): cint {.importc: "getchar", header: "<stdio.h>".}

proc init() =
  var
    oldtio: Termios
    newtio: Termios
    c: char = cast[char](0x00)

  # get the terminal settings for stdin */
  discard tcGetAttr(STDIN_FILENO, oldtio.addr)

  # we want to keep the old setting to restore them a the end
  newtio = oldtio

  # disable canonical mode (buffered i/o) and local echo
  echo newtio
  newtio.c_lflag = newtio.c_lflag and
                   ((not ICANON.cuint) and (not ECHO.cuint))

  echo newtio

  # set the new settings immediately
  discard tcSetAttr(STDIN_FILENO, TCSANOW, newtio.addr)

  while c != 'q':
    echo "*"
    c = cast[char](getchar())
#    echo c

  # restore the former settings
  discard tcSetAttr(STDIN_FILENO, TCSANOW, oldtio.addr)


init()
