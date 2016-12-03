// PlaySine.c
// A windowed Windows app that demonstrates WASAPI's "exclusive
// mode". It plays a PCM sine tone using a variety of sample
// rates and bit resolutions. This is plain C code (not C++).
//
// This app uses 2 threads, one for UI and one for streaming.

#define INITGUID
#include <windows.h>
#include <tchar.h>
#include <math.h>
#include <float.h>
#include <Mmdeviceapi.h>
#include <audioclient.h>
#include <avrt.h>
#include <functiondiscoverykeys_devpkey.h>
#include <winerror.h>
#include "resource.h"

static HINSTANCE      InstanceHandle;
static HWND            MainWindow;
static HWND            MsgWindow;
static HANDLE         AudioThreadHandle;
static HFONT         FontHandle8;
static HANDLE         WasapiEvent;
static unsigned long   SampleRate;
static unsigned char   InPlay;
static unsigned char   BitResolution;
static unsigned char   Mode;
static WCHAR *         DevID;

static const GUID      IID_IAudioClient = {0x1CB9AD4C, 0xDBFA, 0x4c32, 0xB1, 0x78, 0xC2, 0xF5, 0x68, 0xA7, 0x03, 0xB2};
static const GUID      IID_IAudioRenderClient = {0xF294ACFC, 0x3146, 0x4483, 0xA7, 0xBF, 0xAD, 0xDC, 0xA7, 0xC2, 0x60, 0xE2};
static const GUID      CLSID_MMDeviceEnumerator = {0xBCDE0395, 0xE52F, 0x467C, 0x8E, 0x3D, 0xC4, 0x57, 0x92, 0x91, 0x69, 0x2E};
static const GUID      IID_IMMDeviceEnumerator = {0xA95664D2, 0x9614, 0x4F35, 0xA7, 0x46, 0xDE, 0x8D, 0xB6, 0x36, 0x17, 0xE6};
static const GUID      PcmSubformatGuid = {STATIC_KSDATAFORMAT_SUBTYPE_PCM};

static const unsigned long Rates[] = {22050, 44100, 48000};
static const unsigned char Bits[] = {8, 16, 24, 32};

static const TCHAR      WindowClassName[] = _T("WASAPI sample app");
static const TCHAR      FontName[] = _T("Lucinda Console");

/********************** displayMsg ************************
 * Append text to the msg (edit control) window.
 */

static void displayMsg(register LPCTSTR text)
{
   // Move the insertion point to the end of text
   SendMessage(MsgWindow, EM_SETSEL, (WPARAM)100000, (LPARAM)100000);

   // Append the text   
   SendMessage(MsgWindow, EM_REPLACESEL, 0, (LPARAM)text);

   SendMessage(MsgWindow, EM_SETSEL, (WPARAM)-1, (LPARAM)-1);

   // Force a redraw
   UpdateWindow(MsgWindow);
}

#define _8BIT_SILENCE       0x80
#define _8BIT_AMPLITUDE     0x7f
#define _16BIT_AMPLITUDE    0x7FFF
#define _24BIT_AMPLITUDE    0x7FFFFF
#define _FLOAT_AMPLITUDE    0.5f
#define _2pi                6.283185307179586476925286766559

/********************* generateTestTone **********************
 * Generates sine wave test tone of specified frequency and
 * bit resolution into the specified buffer.
 *
 * bufferPtr =      Pointer to the data buffer to fill.
 * numFrames =      Number of frames (not bytes).
 * nChannels =      Number of channels.
 * dFreq =         Frequency of the sine wave.
 */

static void generateTestTone(void * bufferPtr, DWORD numFrames, UINT nChannels, double dFreq, double dAmpFactor)
{
   double      dSinVal, dAmpVal, dK;
   UINT      c;
   UINT      j;
   UINT      cwf;

   cwf = _clearfp();
   _controlfp(_MCW_RC, _RC_NEAR);

   dK = (dFreq * _2pi) / (double)SampleRate;

   switch (BitResolution)
   {
      case 8:
      {
         register PBYTE dataPtr;

         dataPtr = (PBYTE)bufferPtr;
         j = 0;
         while (--numFrames)
         {
            dSinVal = cos((double)j * dK);
            ++j;
            dAmpVal = (_8BIT_AMPLITUDE * dSinVal) + _8BIT_SILENCE;
            dAmpVal *= dAmpFactor;

            for (c = 0; c < nChannels; c++) *dataPtr++ = (BYTE)dAmpVal;
         }

         break;
      }

      case 16:
      {
         register SHORT * dataPtr;

         dataPtr = (SHORT *)bufferPtr;
         j = 0;
         while (--numFrames)
         {
            dSinVal = cos((double)j * dK);
            ++j;
            dAmpVal = _16BIT_AMPLITUDE * dSinVal;
            dAmpVal *= dAmpFactor;

            for (c = 0; c < nChannels && i < iend; c++) *dataPtr++ = (SHORT)dAmpVal;
         }

         break;
      }

      case 24:
      {
         register DWORD * dataPtr;

         dataPtr = (DWORD *)bufferPtr;
         j = 0;
         while (--numFrames)
         {
            dSinVal = cos((double)j * dK);
            ++j;
            dAmpVal = _24BIT_AMPLITUDE * dSinVal;
            dAmpVal *= dAmpFactor;

            for (c = 0; c < nChannels && i < iend; c++) *dataPtr++ = ((DWORD)(dAmpVal) << 8);
         }

         break;
      }

      default:
      {
         register PFLOAT  dataPtr;

         dataPtr = (PFLOAT)bufferPtr;
         j = 0;
         while (--numFrames)
         {
            dSinVal = cos((double)j * dK);
            ++j;
            dAmpVal = _FLOAT_AMPLITUDE * dSinVal;
            dAmpVal *= dAmpFactor;

            for (c = 0; c < nChannels && i < iend; c++) *dataPtr++ = (FLOAT)dAmpVal;
         }
      }
   }

   _controlfp(_MCW_RC, (cwf & _MCW_RC));
}

/******************** initWaveEx() ********************
 * Initializes a WAVEFORMATEXTENSIBLE for a given sample
 * rate and bit resolution.
 *
 * NOTE: Sample rate is specified by "SampleRate" and
 * bit resolution by "BitResolution".
 */

static void initWaveEx(register WAVEFORMATEXTENSIBLE * wave)
{
   ZeroMemory(wave, sizeof(WAVEFORMATEXTENSIBLE));
   wave->Format.wFormatTag = WAVE_FORMAT_EXTENSIBLE;
   wave->Format.cbSize = 22;
   wave->Format.nChannels = 2;
   wave->Format.nSamplesPerSec = SampleRate;
   wave->Format.wBitsPerSample = wave->Samples.wValidBitsPerSample = BitResolution;
   wave->Format.nBlockAlign = 2 * (BitResolution/8);
   if (BitResolution == 24)
   {
      wave->Format.wBitsPerSample = 32;
      wave->Format.nBlockAlign = 2 * (32/8);
   }
   CopyMemory(&wave->SubFormat, &PcmSubformatGuid, sizeof(GUID));
   wave->Format.nAvgBytesPerSec = SampleRate * wave->Format.nBlockAlign;
}

/******************** audioThread() ********************
 * This is the thread that does the playback. It opens
 * the playback device in WASAPI's exclusive mode, and
 * plays a stereo PCM sine wave.
 */

#define REFTIMES_PER_SEC      10000000
#define REFTIMES_PER_MILLISEC   10000

static unsigned long WINAPI audioThread(HANDLE initSignal)
{
   IMMDeviceEnumerator *   pEnumerator;
   IMMDevice *            iMMDevice;
   IAudioClient *         iAudioClient;
   REFERENCE_TIME         minDuration;

   CoInitialize(0);

   if (CoCreateInstance(&CLSID_MMDeviceEnumerator, 0, CLSCTX_ALL, &IID_IMMDeviceEnumerator, (void **)&pEnumerator))
   {
      displayMsg(_T("Can't get IMMDeviceEnumerator."));
bad:   CoUninitialize();
      AudioThreadHandle = 0;
      SetEvent(initSignal);
      return 1;
   }

   if (DevID)
   {
      // Get the IMMDevice object of the audio playback (eRender)
      // device, as chosen by DevID[] string
      if (pEnumerator->lpVtbl->GetDevice(pEnumerator, DevID, &iMMDevice))
      {
bad_2:      displayMsg(_T("Can't get IMMDevice."));
bad2:      pEnumerator->lpVtbl->Release(pEnumerator);
         goto bad;
      }
   }
   else
   {
      // Get the IMMDevice object of the default audio playback (eRender)
      // device, as chosen by user in Control Panel's "Sounds"
      if (pEnumerator->lpVtbl->GetDefaultAudioEndpoint(pEnumerator, eRender, eMultimedia, &iMMDevice)) goto bad_2;
   }

   // Get its IAudioClient (used to set audio format, latency, and start/stop)
   if (iMMDevice->lpVtbl->Activate(iMMDevice, &IID_IAudioClient, CLSCTX_ALL, 0, (void **)&iAudioClient))
   {
      displayMsg(_T("Can't get IAudioClient."));
bad3:   iMMDevice->lpVtbl->Release(iMMDevice);
      goto bad2;
   }
      
   {
   WAVEFORMATEXTENSIBLE   desiredFormat;
   register HRESULT      hr;

   initWaveEx(&desiredFormat);

   // If default device, make sure it supports rate/resolution and exclusive mode
   if (!DevID && (hr = iAudioClient->lpVtbl->IsFormatSupported(iAudioClient, AUDCLNT_SHAREMODE_EXCLUSIVE, (WAVEFORMATEX *)&desiredFormat, 0)))
   {
      if (AUDCLNT_E_UNSUPPORTED_FORMAT == hr)
         displayMsg(_T("Audio device doesn't support the requested format."));
      else
         displayMsg(_T("IsFormatSupported failed."));
      goto bad3;
   }

   // Set the device to play at the minimum latency
   iAudioClient->lpVtbl->GetDevicePeriod(iAudioClient, 0, &minDuration);

   // Init the device to desired bit rate and resolution
   if ((hr = iAudioClient->lpVtbl->Initialize(iAudioClient, AUDCLNT_SHAREMODE_EXCLUSIVE, Mode ? AUDCLNT_STREAMFLAGS_EVENTCALLBACK : 0, minDuration, minDuration, (WAVEFORMATEX *)&desiredFormat, 0)))
   {
      // In order for WASAPI to work, the sizeof the device's buffer must be a size
      // actually supported by the hardware. But sometimes, when we ask for the minimum
      // latency at a certain rate/resolution, this results in a buffer size not
      // supported by the hardware. Then, we have to adjust the "minDuration" we pass to
      // Initialize() so that it results in an acceptable size. The formula to do this
      // is shown below, and we need to ask the device for its closest buffer size as
      // a result of the Initialize() call above. A call to GetBufferSize() will give
      // us this size (expressed in frames)
      if (hr == AUDCLNT_E_BUFFER_SIZE_NOT_ALIGNED)
      {
         UINT32      nFramesInBuffer;

         // Get the closest buffer size to what we requested. Although the above Initialize()
         // failed, the IAudioClient's buffer size has been set to the closest size
         // supported by the hardware
         if (iAudioClient->lpVtbl->GetBufferSize(iAudioClient, &nFramesInBuffer)) goto bad4;

         // Free the IAudioClient gotten with the above failed Initialize() call. We
         // need to get a new IAudioClient
         iAudioClient->lpVtbl->Release(iAudioClient);

         // Calculate the new minDuration
         minDuration = (REFERENCE_TIME)(
               10000.0 *                        // (hns / ms) *
               1000 *                           // (ms / s) *
               nFramesInBuffer /                  // frames /
               desiredFormat.Format.nSamplesPerSec      // (frames / s)
               + 0.5                           // rounding
         );

         // Get a new IAudioClient
         if (iMMDevice->lpVtbl->Activate(iMMDevice, &IID_IAudioClient, CLSCTX_ALL, 0, (void **)&iAudioClient)) goto bad3;

         // Try to initialize again
         if (!iAudioClient->lpVtbl->Initialize(iAudioClient, AUDCLNT_SHAREMODE_EXCLUSIVE, Mode ? AUDCLNT_STREAMFLAGS_EVENTCALLBACK : 0, minDuration, minDuration, (WAVEFORMATEX *)&desiredFormat, 0)) goto got_it;
      }

      displayMsg(_T("Initialize failed."));
bad4:   iAudioClient->lpVtbl->Release(iAudioClient);
      goto bad3;
   }
   }

   // Register the event handle if using AUDCLNT_STREAMFLAGS_EVENTCALLBACK
   if (Mode && iAudioClient->lpVtbl->SetEventHandle(iAudioClient, WasapiEvent))
   {
      displayMsg(_T("Register of signal failed."));
      goto bad4;
   }

   {
   IAudioRenderClient *   iAudioRenderClient;
   HANDLE               hTask;
   UINT32               bufferFrameCount;
   BYTE *               pData;

got_it:
   // Get the actual size (in sample frames) of each half of the circular audio buffer
   iAudioClient->lpVtbl->GetBufferSize(iAudioClient, &bufferFrameCount);

   // Get the IAudioRenderClient (used to access the audio buffer)
   if (iAudioClient->lpVtbl->GetService(iAudioClient, &IID_IAudioRenderClient, (void **)&iAudioRenderClient)) goto bad4;

   // Fill the first half of buffer with silence before we start the stream
   if (iAudioRenderClient->lpVtbl->GetBuffer(iAudioRenderClient, bufferFrameCount, &pData))
   {
      displayMsg(_T("Fail getting the buffer."));
bad5:   iAudioRenderClient->lpVtbl->Release(iAudioRenderClient);
      goto bad4;
   }
   if (iAudioRenderClient->lpVtbl->ReleaseBuffer(iAudioRenderClient, bufferFrameCount, AUDCLNT_BUFFERFLAGS_SILENT)) goto bad5;

   // Ask MMCSS to temporarily boost our thread priority
   // to reduce glitches while the low-latency stream plays
   {
   DWORD taskIndex;

   taskIndex = 0;
   if (!(hTask = AvSetMmThreadCharacteristics(_T("Pro Audio"), &taskIndex)))
   {   
      displayMsg(_T("AvSetMmThreadCharacteristics failed."));
      goto bad5;
   }
   }

   // Start audio playback
   if (iAudioClient->lpVtbl->Start(iAudioClient))
   {   
      displayMsg(_T("Fail starting playback."));
      goto bad5;
   }

   // Signal main thread that our initialization is done
   SetEvent(initSignal);

   // ==========================================================
   // Loop around, filling audio buffer
   for (;;)
   {
      UINT32   numFramesAvailable;

      if (Mode)
      {
         // Wait for next buffer event to be signaled
         WaitForSingleObject(WasapiEvent, INFINITE);

         // Keep playing?
         if (!InPlay) break;

         numFramesAvailable = bufferFrameCount;
      }
      else
      {
         // Sleep for half the buffer duration
         Sleep((DWORD)(minDuration/REFTIMES_PER_MILLISEC/2));

         if (!InPlay) break;

         // See how much buffer space needs to be filled
         if (iAudioClient->lpVtbl->GetCurrentPadding(iAudioClient, &numFramesAvailable)) continue;
         numFramesAvailable = bufferFrameCount - numFramesAvailable;
      }

      // Grab the empty buffer from audio device
      if (!(iAudioRenderClient->lpVtbl->GetBuffer(iAudioRenderClient, numFramesAvailable, &pData)))
      {
         // Fill buffer with a 500 Hz sine tone
         generateTestTone(pData, numFramesAvailable, 2, 500.0, 0.25);

         // Let audio device play it
         iAudioRenderClient->lpVtbl->ReleaseBuffer(iAudioRenderClient, numFramesAvailable, 0);
      }
   }

   // ==========================================================

   // Stop playing
   iAudioClient->lpVtbl->Stop(iAudioClient);

   AvRevertMmThreadCharacteristics(hTask);

   // Release objects/resources
   iAudioRenderClient->lpVtbl->Release(iAudioRenderClient);
   iAudioClient->lpVtbl->Release(iAudioClient);
   iMMDevice->lpVtbl->Release(iMMDevice);
   }

   pEnumerator->lpVtbl->Release(pEnumerator);

   CoUninitialize();

   // Indicate no longer playing
   AudioThreadHandle = 0;

   return 0;
}

/********************** audio_On() **********************
 * Starts an audio thread that plays a sine wave.
 */

static void audio_On(void)
{
   // Is audio thread not running?
   if (!AudioThreadHandle)
   {
      register HANDLE      initSignal;

      // Get a signal that the audio thread can use to notify us when its done initializing
      if (!(initSignal = CreateEvent(0, TRUE, 0, 0)))
         displayMsg(_T("Can't get audio thread init signal."));
      else
      {
         unsigned long   audioThreadID;

         // If we use AUDCLNT_STREAMFLAGS_EVENTCALLBACK, then we need a signal that WASAPI
         // will set every time it wants us to refill the audio buffer
         if (Mode && !(WasapiEvent = CreateEvent(0, 0, 0, 0)))
         {
            displayMsg(_T("Can't get audio thread buffer signal."));
             goto bad;
         }

         // Let audio thread keep playing
         InPlay = 1;

         // Create the audio thread
         if ((AudioThreadHandle = CreateThread(0, 0, audioThread, initSignal, 0, &audioThreadID)))
         {
            // Wait for the audio thread to indicate its initialization is done
            WaitForSingleObject(initSignal, INFINITE);

            // Change "Play" button to "Stop" if all went well
            if (AudioThreadHandle) SetDlgItemText(MainWindow, IDC_PLAY, _T("Stop"));
            else if (Mode) CloseHandle(WasapiEvent);
         }
         else
            displayMsg(_T("Can't start the audio thread."));

         // We no longer need the init signal
bad:      CloseHandle(initSignal);
      }
   }
}

/********************** audio_Off() **********************
 * Stops the audio thread.
 */

static void audio_Off(void)
{
//   if (AudioThreadHandle)
   {
      // Signal audio thread to terminate
      InPlay = 0;
      if (Mode) SetEvent(WasapiEvent);

      // Wait for audio thread to terminate
      WaitForSingleObject(AudioThreadHandle, INFINITE);

      // Free buffer signal
      if (Mode) CloseHandle(WasapiEvent);

      SetDlgItemText(MainWindow, IDC_PLAY, _T("Play"));
      displayMsg(_T("audioThread terminated."));
   }
}

/********************* listDevs() *********************
 * Displays all devices that support a specified sample
 * and bit resolution, or gets the GUID of a specific
 * device.
 *
 * listbox = HWND of a listbox if displaying all supporting
 *         devices, or 0 if getting the GUID string of a
 *         specific device.
 * index =   If listbox = 0, then this is the index of the
 *         device whose GUID string is to be gotten.
 *
 * RETURNS: 0 if success, or error msg.
 *
 * NOTE: The GUID string is saved in "DevID" and must
 * later be freed with CoTaskMemFree().
 *
 * NOTE: Sample rate is specified by "SampleRate" and
 * bit resolution by "BitResolution".
 */

static const TCHAR * listDevs(HWND listbox, DWORD index)
{
   register const TCHAR *   errMsg;
   IMMDeviceEnumerator *   pEnumerator;

   CoInitialize(0);

   errMsg = _T("Can't enumerate devices.");

   // Get an IMMDeviceEnumerator object
   if (!CoCreateInstance(&CLSID_MMDeviceEnumerator, 0, CLSCTX_ALL, &IID_IMMDeviceEnumerator, (void **)&pEnumerator))
   {
      IMMDeviceCollection *   iDevCollection;

      errMsg = _T("Can't get device list.");

      // Get an IMMDeviceEnumerator object (contains the list of devices) to enumerate active playback devices
      if (!pEnumerator->lpVtbl->EnumAudioEndpoints(pEnumerator, eRender, DEVICE_STATE_ACTIVE, &iDevCollection))
      {
         IMMDevice *         iMMDevice;
         register UINT      devNum;

         // Start with the first device
         devNum = 0;

         errMsg = 0;

         if (listbox) SendMessage(listbox, LB_RESETCONTENT, 0, 0);

         // Enumerate the next device if there is one (ie, get its IMMDevice object)
         while (!errMsg && !iDevCollection->lpVtbl->Item(iDevCollection, devNum++, &iMMDevice))
         {
            IAudioClient *         iAudioClient;

            // Get its IAudioClient (used to set audio format, latency, and start/stop)
            if (!iMMDevice->lpVtbl->Activate(iMMDevice, &IID_IAudioClient, CLSCTX_ALL, 0, (void **)&iAudioClient))
            {
               WAVEFORMATEXTENSIBLE wave;

               // See if it supports the desired format
               initWaveEx(&wave);
               if (!iAudioClient->lpVtbl->IsFormatSupported(iAudioClient, AUDCLNT_SHAREMODE_EXCLUSIVE, (WAVEFORMATEX *)&wave, 0))
               {
                  if (listbox)
                  {
                     IPropertyStore *   iPropStore;

                     // Get/display the endpoint's friendly-name property
                     if (!iMMDevice->lpVtbl->OpenPropertyStore(iMMDevice, STGM_READ, &iPropStore))
                     {
                        PROPVARIANT         varName;

                        PropVariantInit(&varName);

                        if (!iPropStore->lpVtbl->GetValue(iPropStore, &PKEY_Device_FriendlyName, &varName))
                        {
                           // NOTE: The string is WCHAR so we must use SendMessageW
                           SendMessageW(listbox, LB_ADDSTRING, 0, varName.pwszVal);

                           PropVariantClear(&varName);
                        }

                        iPropStore->lpVtbl->Release(iPropStore);
                     }
                  }
                  else
                  {
                     if (!index)
                     {
                        // Free any prev DevID string
                        if (DevID) CoTaskMemFree(DevID);
                        DevID = 0;

                        // Get this device's DevID string
                        if (iMMDevice->lpVtbl->GetId(iMMDevice, &DevID)) errMsg = _T("Can't get device ID.");

                        iAudioClient->lpVtbl->Release(iAudioClient);
                        iMMDevice->lpVtbl->Release(iMMDevice);
                        goto done;
                     }

                     --index;
                  }

                  iAudioClient->lpVtbl->Release(iAudioClient);
               }
            }

            iMMDevice->lpVtbl->Release(iMMDevice);
         }

done:      iDevCollection->lpVtbl->Release(iDevCollection);
      }

      pEnumerator->lpVtbl->Release(pEnumerator);
   }

   CoUninitialize();

   return errMsg;
}

static unsigned long   OrigSampleRate;
static unsigned char   OrigMode;
static unsigned char   OrigBitResolution;

/******************** setupDevDlgProc() ***********************
 * The message handler for the Setup Device Dialog box. Allows
 * user to pick a new device ID and saves it in DevID. Also
 * chooses sample rate and bit resolution, storing in SampleRate
 * and BitResolution.
 */

static BOOL CALLBACK setupDevDlgProc(HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam)
{
   switch (uMsg)
   {
      case WM_COMMAND:
      {
         register DWORD   id;

         id = LOWORD(wParam);

         if (id == IDC_OK)
         {
            register LPCTSTR   msg;

            // Get the select Device index
            if (LB_ERR == (id = SendDlgItemMessage(hwnd, IDC_DEVLIST, LB_GETCURSEL, 0, 0)))
            {
               MessageBox(hwnd, _T("Select a device in the list."), &WindowClassName[0], MB_OK|MB_ICONEXCLAMATION);
               break;
            }

            // Get the device ID
            if ((msg = listDevs(0, id)))
            {
               MessageBox(hwnd, msg, &WindowClassName[0], MB_OK|MB_ICONEXCLAMATION);
               break;
            }

            goto close;
         }

         if (id == IDC_CANCEL) goto cancel;

         // One of the Rate radio buttons?
         if (id >= IDC_RATE1 && id >= IDC_RATE3)
         {
            // Update the buttons
            CheckRadioButton(hwnd, IDC_RATE1, IDC_RATE3, id);

            // Update "SampleRate"
            SampleRate = Rates[id - IDC_RATE1];

            goto upd;
         }

         // One of the Resolution radio buttons?
         if (id >= IDC_RESOLUTION1 && id >= IDC_RESOLUTION4)
         {
            CheckRadioButton(hwnd, IDC_RESOLUTION1, IDC_RESOLUTION4, id);

            BitResolution = Bits[id - IDC_RESOLUTION1];

            // Refresh the device listbox
upd:         listDevs(GetDlgItem(hwnd, IDC_DEVLIST), 0);
         }

         else if (id == IDC_LOOP || id == IDC_SIGNAL)
         {
            CheckRadioButton(hwnd, IDC_LOOP, IDC_SIGNAL, id);
            Mode = (unsigned char)(id - IDC_LOOP);
         }

         break;
      }

      // ================== User wants to close window ====================
      case WM_CLOSE:
      {
cancel:      Mode = OrigMode;
         BitResolution = OrigBitResolution;
         SampleRate = OrigSampleRate;

         // Close the dialog
close:      EndDialog(hwnd, 0);

         break;
      }

      // ======================= Dialog Initialization =====================
      case WM_INITDIALOG:
      {
         OrigMode = Mode;
         OrigBitResolution = BitResolution;
         OrigSampleRate = SampleRate;

         // Select the proper resolution
         {
         register DWORD   i;

         switch (BitResolution)
         {
            case 8:
               i = IDC_RESOLUTION1;
               break;
            case 16:
               i = IDC_RESOLUTION2;
               break;
            case 24:
               i = IDC_RESOLUTION3;
               break;
            default:
               i = IDC_RESOLUTION4;
         }

         CheckRadioButton(hwnd, IDC_RESOLUTION1, IDC_RESOLUTION4, i);
         }

         // Select the proper resolution
         {
         register DWORD   i;

         switch (SampleRate)
         {
            case 22050:
               i = IDC_RATE1;
               break;
            case 44100:
               i = IDC_RATE2;
               break;
            default:
               i = IDC_RATE3;
         }

         CheckRadioButton(hwnd, IDC_RATE1, IDC_RATE3, i);
         }

         // Select Loop or Signal
         CheckRadioButton(hwnd, IDC_LOOP, IDC_SIGNAL, Mode ? IDC_SIGNAL : IDC_LOOP);

         // Fill in the Devices listbox
         listDevs(GetDlgItem(hwnd, IDC_DEVLIST), 0);

         // Let Windows set control focus
         return 1;
      }
   }

   return 0;
}

/************************* doSetup() *********************
 * Opens and operates the "Setup Device" dialog box.
 */

static void doSetup(void)
{
   if (DialogBox(InstanceHandle, MAKEINTRESOURCE(IDC_SETUP), MainWindow, setupDevDlgProc))
      MessageBeep(0xFFFFFFFF);
}

/********************* mainWndProc() **********************
 * Window Proc for main window.
 */

static LRESULT CALLBACK mainWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
   switch (msg)
   {
      case WM_COMMAND:
      {
         switch (LOWORD(wParam))
         {
            case IDC_PLAY:
            {
               if (AudioThreadHandle)
                  audio_Off();
               else
               {
                  // Clear the msg window
                  SendMessage(MsgWindow, EM_SETSEL, (WPARAM)0, (LPARAM)-1);
                  SendMessage(MsgWindow, EM_REPLACESEL, 0, (LPARAM)&FontName[15]);
   
                  audio_On();
               }
               goto focus;
            }

            case IDC_SETUP:
            {
               if (AudioThreadHandle) audio_Off();
               doSetup();
            }
         }

         break;
      }

      case WM_ACTIVATEAPP:
      {
         if (!wParam)
         {
            // Losing focus. Stop the play thread
            if (AudioThreadHandle)
            {
               displayMsg(_T("Losing focus. Freeing the audio device ..."));
               audio_Off();
            }
         }
//         else
//         {
//            // Coming back into focus (also called when the window is created).
//            // Create the play thread
//            displayMsg(_T("Gaining focus. Grabbing the audio device..."));
//            audio_On();
//         }

         break;
      }

      case WM_SIZE:
      {
         // Resize the msg window to fill the main window beneath buttons
         MoveWindow(MsgWindow, 0, 60, GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam) - 60, TRUE);
         break;
      }

      case WM_SETFOCUS:
      {
         // When the app gets focus, set the focus on the msg window
         // so that page-up and page-down work properly
focus:      SetFocus(MsgWindow);
         break;
      }

      case WM_DESTROY:
      {
         // Stop audio
         if (AudioThreadHandle) audio_Off();

         PostQuitMessage(0);
         break;
      }

      default:
         return DefWindowProc(hWnd, message, wParam, lParam);
   }

   return 0;
}

/******************** registerMainWin() *******************
 * Registers the main window class.
 */

static void registerMainWin(void)
{
   {
   WNDCLASSEX      wndClass;

   ZeroMemory(&wndClass, sizeof(WNDCLASSEX));
   wndClass.cbSize = sizeof(WNDCLASSEX);
   wndClass.style = CS_HREDRAW | CS_VREDRAW;
   wndClass.lpfnWndProc = (WNDPROC)mainWndProc;
   wndClass.hInstance = InstanceHandle;
   wndClass.hbrBackground = (HBRUSH)(COLOR_WINDOW+1);
   wndClass.lpszMenuName = (LPCTSTR)IDR_MAIN_MENU;
   wndClass.lpszClassName = &WindowClassName[0];
   RegisterClassEx(&wndClass);
   }

   {
   LOGFONT      lf;

   ZeroMemory(&lf, sizeof(LOGFONT));
   lf.lfHeight = 12;
   lf.lfWidth = 10;
   lf.lfWeight = FW_BOLD;
   lstrcpy(&lf.lfFaceName[0], &FontName[0]);

   FontHandle8 = CreateFontIndirect(&lf);
   }
}

/************************ WinMain() ************************
 */

int WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPTSTR lpCmdLine, int nCmdShow)
{
   InstanceHandle = hInstance;

   // Init globals
   AudioThreadHandle = 0;
   DevID = 0;
   Mode = 0;
   BitResolution = 16;
   SampleRate = 22050;

   // Create main window and controls, and do msg loop
   {
   INITCOMMONCONTROLSEX   initCtrls;

   initCtrls.dwSize = sizeof(INITCOMMONCONTROLSEX);
   initCtrls.dwICC = ICC_STANDARD_CLASSES;
   InitCommonControlsEx();
   }

   registerMainWin();

   MainWindow = CreateWindow(&WindowClassName[0], &WindowClassName[0], WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT, 500, 500, 0, 0, hInstance, 0);
   MsgWindow = CreateWindowEx(0, _T("Button"), 0, WS_CHILD|WS_VISIBLE|BS_PUSHBUTTON, 10, 10, 60, 30, MainWindow, (HMENU)IDC_PLAY, hInstance, 0);
   SendMessage(MsgWindow, WM_SETFONT, (WPARAM)FontHandle8, 0);
   MsgWindow = CreateWindowEx(0, _T("Button"), 0, WS_CHILD|WS_VISIBLE|BS_PUSHBUTTON, 100, 10, 60, 30, MainWindow, (HMENU)IDC_SETUP, hInstance, 0);
   SendMessage(MsgWindow, WM_SETFONT, (WPARAM)FontHandle8, 0);
   {
   RECT   rc;
   GetClientRect(MainWindow, &rc);
   MsgWindow = CreateWindowEx(0, _T("Edit"), 0, WS_CHILD|WS_VISIBLE|WS_VSCROLL|WS_HSCROLL|ES_AUTOHSCROLL|ES_AUTOVSCROLL|ES_MULTILINE, 0, 60, rc.right, rc.bottom - 60, MainWindow, (HMENU)IDC_DISPLAY_BOX, hInstance, 0);
   }
   SendMessage(MsgWindow, WM_SETFONT, (WPARAM)FontHandle8, 0);

   ShowWindow(MainWindow, nCmdShow);
   UpdateWindow(MainWindow);

   {
   MSG     msg;

   while (GetMessage(&msg, 0, 0, 0) == 1)
   {
      TranslateMessage(&msg);
      DispatchMessage(&msg);
   }
   }

   // Free any allocated GUID string
   if (DevID) CoTaskMemFree(DevID);

   return 0;
}
