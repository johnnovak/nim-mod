#include <unistd.h>
#include <stdio.h>
#include <sys/select.h>
#include <termios.h>

#define NB_DISABLE 0
#define NB_ENABLE 1

// http://cc.byexamples.com/2007/04/08/non-blocking-user-input-in-loop-without-ncurses/
// plus setbuf(stdin, NULL); in init

int kbhit()
{
    struct timeval tv;
    fd_set fds;
    tv.tv_sec = 0;
    tv.tv_usec = 0;
    FD_ZERO(&fds);
    FD_SET(STDIN_FILENO, &fds); //STDIN_FILENO is 0
    int s = select(STDIN_FILENO+1, &fds, NULL, NULL, &tv);
    return FD_ISSET(STDIN_FILENO, &fds);
}

void nonblock(int state)
{
    struct termios ttystate;

    //get the terminal state
    tcgetattr(STDIN_FILENO, &ttystate);

    if (state==NB_ENABLE)
    {
        //turn off canonical mode & echo
        printf("ttystate.c_lflag: %d\n", ttystate.c_lflag);
        printf("ICANON: %d\n", ICANON);
        printf("ECHO: %d\n", ECHO);
        ttystate.c_lflag &= ~ICANON & ~ECHO;
        printf("ttystate.c_lflag: %d\n", ttystate.c_lflag);
        //minimum of number input read.
        ttystate.c_cc[VMIN] = 0;
    }
    else if (state==NB_DISABLE)
    {
        //turn on canonical mode
        ttystate.c_lflag |= ICANON;
    }
    //set the terminal attributes.
    tcsetattr(STDIN_FILENO, TCSANOW, &ttystate);
    setbuf(stdin, NULL);
}

int main()
{
    char c;
    int i=0;
    int state = 0;

    nonblock(NB_ENABLE);
    while (!i)
    {
        usleep(1000);
        i = kbhit();
        if (i != 0)
        {
            c = getchar();
            printf("%d\n", c);
            if (c=='q')
                i=1;
            else
                i=0;
        }
    }
    printf("\n you hit %c. \n",c);
    nonblock(NB_DISABLE);

    return 0;
}
