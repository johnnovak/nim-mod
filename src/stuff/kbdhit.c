/**
 Linux (POSIX) implementation of _kbhit().
 Morgan McGuire, morgan@cs.brown.edu
 */
#include <stdio.h>
#include <sys/select.h>
#include <termios.h>

int _kbhit() {
    static const int STDIN = 0;
    static int initialized = 0;

    if (! initialized) {
        // Use termios to turn off line buffering
        struct termios term;
        tcgetattr(STDIN, &term);
        term.c_lflag &= ~ICANON;
        tcsetattr(STDIN, TCSANOW, &term);
        setbuf(stdin, NULL);
        initialized = 1;
    }

//    int bytesWaiting;
//    ioctl(STDIN, FIONREAD, &bytesWaiting);
//    return bytesWaiting;

    struct timeval timeout;
    fd_set rdset;

    FD_ZERO(&rdset);
    FD_SET(STDIN, &rdset);
    timeout.tv_sec  = 0;
    timeout.tv_usec = 0;

    return select(STDIN + 1, &rdset, NULL, NULL, &timeout);
}

//////////////////////////////////////////////
//    Simple demo of _kbhit()

#include <unistd.h>

int main(int argc, char** argv) {
    printf("Press any key");
    while (1) {
        usleep(1000);
        int k = _kbhit();
        if (k > 0) {
          printf("%i", getch());
        }
 //       printf(".");
//        fflush(stdout);
    }
    printf("\nDone.\n");

    return 0;
}
