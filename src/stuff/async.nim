import posix, termios


proc getChar(): cint {.importc: "getchar", header: "<stdio.h>".}
proc setBuf(f: File, p: pointer) {.importc: "setbuf", header: "<stdio.h>".}

proc kbhit(): cint =
  var tv: Timeval
  tv.tv_sec = 0
  tv.tv_usec = 0

  var fds: TFdSet
  FD_ZERO(fds)
  FD_SET(STDIN_FILENO, fds)  # STDIN_FILENO is 0
  discard select(STDIN_FILENO+1, fds.addr, nil, nil, tv.addr)
  return FD_ISSET(STDIN_FILENO, fds)

proc nonblock(enabled: bool) =
  var ttystate: Termios

  # get the terminal state
  discard tcGetAttr(STDIN_FILENO, ttystate.addr)
  echo ttystate

  if enabled:
    # turn off canonical mode & echo
    ttystate.c_lflag = ttystate.c_lflag and not Cflag(ICANON or ECHO)

    # minimum of number input read
    ttystate.c_cc[VMIN] = 0.cuchar

  else:
    # turn on canonical mode
    ttystate.c_lflag = ttystate.c_lflag or ICANON

  # set the terminal attributes.
  discard tcSetAttr(STDIN_FILENO, TCSANOW, ttystate.addr)
  setBuf(stdin, nil)


when isMainModule:
  var
    c: cint
    i = 0

  nonblock(true)
  while (i == 0):
    discard usleep(1000)
  #  echo "*"
    i = kbhit()
    if i != 0:
        c = getchar()
        echo c
        if c == cast[int]('q'):
            i = 1
        else:
            i = 0

  echo "Quitting..."
  nonblock(false)

