#include <conio.h>
#include <stdio.h>
#include <windows.h>

int main() {
  int key = 0;

  while (1) {
    Sleep(100);

    if (_kbhit()) {
      key =_getch();

      printf("%d\n", key);
      if (key == 'q')
        break;
    }
  }
}

