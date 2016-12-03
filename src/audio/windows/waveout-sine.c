#include <windows.h>
#include <mmsystem.h>
#include <stdio.h>
#include <conio.h>

/*
 * some good values for block size and count
 */
#define BLOCK_SIZE 8192
#define BLOCK_COUNT 20

/*
 * function prototypes
 */
static void CALLBACK waveOutProc(HWAVEOUT, UINT, DWORD, DWORD, DWORD);
static WAVEHDR* allocateBlocks(int size, int count);
static void freeBlocks(WAVEHDR* blockArray);
static void writeAudio(HWAVEOUT hWaveOut, LPSTR data, int size);

/*
 * module level variables
 */
static CRITICAL_SECTION waveCriticalSection;
static WAVEHDR* waveBlocks;
static volatile int waveFreeBlockCount;
static int waveCurrentBlock;


static void CALLBACK waveOutProc(
    HWAVEOUT hWaveOut,
    UINT uMsg,
    DWORD dwInstance,
    DWORD dwParam1,
    DWORD dwParam2
    )
{
  /*
   *  * pointer to free block counter
   *   */
  int* freeBlockCounter = (int*)dwInstance;
  /*
   *  * ignore calls that occur due to openining and closing the
   *   * device.
   *    */
  if (uMsg != WOM_DONE) {
    return;
  }

  EnterCriticalSection(&waveCriticalSection);
  (*freeBlockCounter)++;
  LeaveCriticalSection(&waveCriticalSection);
}

WAVEHDR* allocateBlocks(int size, int count)
{
  unsigned char* buffer;
  int i;
  WAVEHDR* blocks;
  DWORD totalBufferSize = (size + sizeof(WAVEHDR)) * count;

  if ((buffer = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY,
                          totalBufferSize)) == NULL) {
    fprintf(stderr, "Memory allocation error\n");
    ExitProcess(1);
  }

  blocks = (WAVEHDR*) buffer;
  buffer += sizeof(WAVEHDR) * count;
  for (i = 0; i < count; i++) {
    blocks[i].dwBufferLength = size;
    blocks[i].lpData = buffer;
    buffer += size;
  }
  return blocks;
}

void freeBlocks(WAVEHDR* blockArray)
{
  HeapFree(GetProcessHeap(), 0, blockArray);
}

void writeAudio(HWAVEOUT hWaveOut, LPSTR data, int size)
{
  WAVEHDR* current;
  int remain;
  current = &waveBlocks[waveCurrentBlock];

  while (size > 0) {
    /*
     * first make sure the header we're going to use is unprepared
     */
    if(current->dwFlags & WHDR_PREPARED)
      waveOutUnprepareHeader(hWaveOut, current, sizeof(WAVEHDR));

    if(size < (int)(BLOCK_SIZE - current->dwUser)) {
      memcpy(current->lpData + current->dwUser, data, size);
      current->dwUser += size;
      break;
    }

    remain = BLOCK_SIZE - current->dwUser;
    memcpy(current->lpData + current->dwUser, data, remain);
    size -= remain;
    data += remain;
    current->dwBufferLength = BLOCK_SIZE;

    waveOutPrepareHeader(hWaveOut, current, sizeof(WAVEHDR));
    waveOutWrite(hWaveOut, current, sizeof(WAVEHDR));

    EnterCriticalSection(&waveCriticalSection);
    waveFreeBlockCount--;
    LeaveCriticalSection(&waveCriticalSection);

    /*
     * wait for a block to become free
     */
    while(!waveFreeBlockCount)
      Sleep(10);

    /*
     * point to the next block
     */
    waveCurrentBlock++;
    waveCurrentBlock %= BLOCK_COUNT;
    current = &waveBlocks[waveCurrentBlock];
    current->dwUser = 0;
  }
}

int main(int argc, char* argv[])
{
  HWAVEOUT hWaveOut;
  WAVEFORMATEX wfx;

  waveBlocks = allocateBlocks(BLOCK_SIZE, BLOCK_COUNT);
  waveFreeBlockCount = BLOCK_COUNT;
  waveCurrentBlock = 0;
  InitializeCriticalSection(&waveCriticalSection);

  wfx.nSamplesPerSec = 44100;
  wfx.wBitsPerSample = 16;
  wfx.nChannels = 2;
  wfx.cbSize = 0;
  wfx.wFormatTag = WAVE_FORMAT_PCM;
  wfx.nBlockAlign = (wfx.wBitsPerSample * wfx.nChannels) >> 3;
  wfx.nAvgBytesPerSec = wfx.nBlockAlign * wfx.nSamplesPerSec;

  if (waveOutOpen(&hWaveOut, WAVE_MAPPER, &wfx, (DWORD_PTR)waveOutProc,
                  (DWORD_PTR)&waveFreeBlockCount,
                  CALLBACK_FUNCTION) != MMSYSERR_NOERROR) {

    fprintf(stderr, "%s: unable to open wave mapper device\n", argv[0]);
    ExitProcess(1);
  }

  while (1) {
    Sleep(10);
    writeAudio(hWaveOut);
    if (kbhit() > 0) break;
  }

  while(waveFreeBlockCount < BLOCK_COUNT) {
    Sleep(10);
  }

  int i;
  for (i = 0; i < waveFreeBlockCount; i++) {
    if (waveBlocks[i].dwFlags & WHDR_PREPARED) {
      waveOutUnprepareHeader(hWaveOut, &waveBlocks[i], sizeof(WAVEHDR));
    }
  }

  DeleteCriticalSection(&waveCriticalSection);

  freeBlocks(waveBlocks);
  waveOutClose(hWaveOut);

  return 0;
}
