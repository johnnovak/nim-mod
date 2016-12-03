/*
 *  Compile with: gcc -lasound -lm -o pcm pcm
 *  This small demo sends a simple sinusoidal wave to your speakers.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <getopt.h>
#include <pthread.h>
#include <alsa/asoundlib.h>

#include <sys/time.h>
#include <math.h>

static char *device = "plughw:0,0";                     /* playback device */
static snd_pcm_format_t format = SND_PCM_FORMAT_S16;    /* sample format */
static unsigned int rate = 44100;                       /* stream rate */
static unsigned int channels = 2;                       /* count of channels */
static unsigned int buffer_time = 500000;               /* ring buffer length in us */
static unsigned int period_time = 100000;               /* period time in us */
static double freq = 110;                               /* sinusoidal wave frequency in Hz */
static snd_pcm_sframes_t buffer_size;
static snd_pcm_sframes_t period_size;
static snd_output_t *output = NULL;

static double phase = 0;

static void generate_sine(const snd_pcm_channel_area_t *areas,
                          snd_pcm_uframes_t offset,
                          int count)
{
  int num_channels = 2;

  static double max_phase = 2. * M_PI;
  double step = max_phase*freq/(double)rate;
  unsigned char *samples[num_channels];
  int steps[num_channels];
  unsigned int chn;
  int format_bits = 16;
  unsigned int maxval = (1 << (format_bits - 1)) - 1;
  int bps = format_bits / 8;  /* bytes per sample */

  for (chn = 0; chn < num_channels; chn++) {
    samples[chn] = /*(signed short *)*/(((unsigned char *)areas[chn].addr) + (areas[chn].first / 8));
    steps[chn] = areas[chn].step / 8;
    samples[chn] += offset * steps[chn];
  }

  /* fill the channel areas */
  while (count-- > 0) {
    union {
      float f;
      int i;
    } fval;
    int res, i;
    res = sin(phase) * maxval;
    for (chn = 0; chn < num_channels; chn++) {
      /* Generate data in native endian format */
      for (i = 0; i < bps; i++)
        *(samples[chn] + i) = (res >>  i * 8) & 0xff;
      samples[chn] += steps[chn];
    }
    phase += step;
    if (phase >= max_phase)
      phase -= max_phase;
  }
}

static int set_hwparams(snd_pcm_t *handle,
                        snd_pcm_hw_params_t *params,
                        snd_pcm_access_t access)
{
  unsigned int rrate;
  snd_pcm_uframes_t size;
  int err, dir;

  /* choose all parameters */
  err = snd_pcm_hw_params_any(handle, params);
  if (err < 0) {
    printf("Broken configuration for playback: no configurations available: %s\n", snd_strerror(err));
    return err;
  }

  /* set the interleaved read/write format */
  err = snd_pcm_hw_params_set_access(handle, params, access);
  if (err < 0) {
    printf("Access type not available for playback: %s\n", snd_strerror(err));
    return err;
  }

  /* set the sample format */
  snd_pcm_format_t format = SND_PCM_FORMAT_S16;
  err = snd_pcm_hw_params_set_format(handle, params, format);
  if (err < 0) {
    printf("Sample format not available for playback: %s\n", snd_strerror(err));
    return err;
  }

  /* set the count of channels */
  unsigned int channels = 2;
  err = snd_pcm_hw_params_set_channels(handle, params, channels);
  if (err < 0) {
    printf("Channels count (%i) not available for playbacks: %s\n", channels, snd_strerror(err));
    return err;
  }

  /* set the stream rate */
  rrate = rate;
  err = snd_pcm_hw_params_set_rate_near(handle, params, &rrate, 0);
  if (err < 0) {
    printf("Rate %iHz not available for playback: %s\n", rate, snd_strerror(err));
    return err;
  }

//  if (rrate != rate) {
//    printf("Rate doesn't match (requested %iHz, get %iHz)\n", rate, err);
//    return -EINVAL;
//  }

  /* set the buffer time */
  err = snd_pcm_hw_params_set_buffer_time_near(handle, params, &buffer_time, &dir);
  if (err < 0) {
    printf("Unable to set buffer time %i for playback: %s\n", buffer_time, snd_strerror(err));
    return err;
  }

  err = snd_pcm_hw_params_get_buffer_size(params, &size);
  if (err < 0) {
    printf("Unable to get buffer size for playback: %s\n", snd_strerror(err));
    return err;
  }

  buffer_size = size;

  /* set the period time */
  err = snd_pcm_hw_params_set_period_time_near(handle, params, &period_time, &dir);
  if (err < 0) {
    printf("Unable to set period time %i for playback: %s\n", period_time, snd_strerror(err));
    return err;
  }

  err = snd_pcm_hw_params_get_period_size(params, &size, &dir);
  if (err < 0) {
    printf("Unable to get period size for playback: %s\n", snd_strerror(err));
    return err;
  }
  period_size = size;

  /* write the parameters to device */
  err = snd_pcm_hw_params(handle, params);
  if (err < 0) {
    printf("Unable to set hw params for playback: %s\n", snd_strerror(err));
    return err;
  }

  return 0;
}


static int set_swparams(snd_pcm_t *handle, snd_pcm_sw_params_t *swparams)
{
  int err;
  /* get the current swparams */
  err = snd_pcm_sw_params_current(handle, swparams);
  if (err < 0) {
    printf("Unable to determine current swparams for playback: %s\n", snd_strerror(err));
    return err;
  }
  /* start the transfer when the buffer is almost full: */
  /* (buffer_size / avail_min) * avail_min */
  err = snd_pcm_sw_params_set_start_threshold(handle, swparams, (buffer_size / period_size) * period_size);
  if (err < 0) {
    printf("Unable to set start threshold mode for playback: %s\n", snd_strerror(err));
    return err;
  }
  /* allow the transfer when at least period_size samples can be processed */
  /* or disable this mechanism when period event is enabled (aka interrupt like style processing) */
  err = snd_pcm_sw_params_set_avail_min(handle, swparams, period_size);
  if (err < 0) {
    printf("Unable to set avail min for playback: %s\n", snd_strerror(err));
    return err;
  }
  /* write the parameters to the playback device */
  err = snd_pcm_sw_params(handle, swparams);
  if (err < 0) {
    printf("Unable to set sw params for playback: %s\n", snd_strerror(err));
    return err;
  }
  return 0;
}

static int xrun_recovery(snd_pcm_t *handle, int err)
{
  printf("stream recovery\n");

  if (err == -EPIPE) {    /* under-run */
    err = snd_pcm_prepare(handle);
    if (err < 0) {
      printf("Can't recovery from underrun, prepare failed: %s\n", snd_strerror(err));
    }
    return 0;

  } else if (err == -ESTRPIPE) {
    while ((err = snd_pcm_resume(handle)) == -EAGAIN) {
      sleep(1);       /* wait until the suspend flag is released */
    }
    if (err < 0) {
      err = snd_pcm_prepare(handle);
      if (err < 0) {
        printf("Can't recovery from suspend, prepare failed: %s\n", snd_strerror(err));
      }
    }
    return 0;
  }
  return err;
}


struct async_private_data {
  signed short *samples;
  snd_pcm_channel_area_t *areas;
};

static void async_callback(snd_async_handler_t *ahandler)
{
  struct async_private_data *data = snd_async_handler_get_callback_private(ahandler);
  signed short *samples = data->samples;
  snd_pcm_channel_area_t *areas = data->areas;
  snd_pcm_sframes_t avail;
  int err;

  snd_pcm_t *handle = snd_async_handler_get_pcm(ahandler);
  avail = snd_pcm_avail_update(handle);

  while (avail >= period_size) {

    generate_sine(areas, 0, period_size);

    err = snd_pcm_writei(handle, samples, period_size);
    if (err < 0) {
      printf("Write error: %s\n", snd_strerror(err));
      exit(EXIT_FAILURE);
    }
    if (err != period_size) {
      printf("Write error: written %i expected %li\n", err, period_size);
      exit(EXIT_FAILURE);
    }
    avail = snd_pcm_avail_update(handle);
  }
}

static int async_loop(snd_pcm_t *handle,
                      signed short *samples,
                      snd_pcm_channel_area_t *areas)
{
  struct async_private_data data;
  snd_async_handler_t *ahandler;
  int err, count;
  data.samples = samples;
  data.areas = areas;

  err = snd_async_add_pcm_handler(&ahandler, handle, async_callback, &data);
  if (err < 0) {
    printf("Unable to register async handler\n");
    exit(EXIT_FAILURE);
  }

  for (count = 0; count < 2; count++) {

    generate_sine(areas, 0, period_size);

    err = snd_pcm_writei(handle, samples, period_size);
    if (err < 0) {
      printf("Initial write error: %s\n", snd_strerror(err));
      exit(EXIT_FAILURE);
    }
    if (err != period_size) {
      printf("Initial write error: written %i expected %li\n", err, period_size);
      exit(EXIT_FAILURE);
    }
  }

  if (snd_pcm_state(handle) == SND_PCM_STATE_PREPARED) {
    err = snd_pcm_start(handle);
    if (err < 0) {
      printf("Start error: %s\n", snd_strerror(err));
      exit(EXIT_FAILURE);
    }
  }

  while (1) {
    sleep(1);
  }
}

static void async_direct_callback(snd_async_handler_t *ahandler)
{
  snd_pcm_t *handle = snd_async_handler_get_pcm(ahandler);
  struct async_private_data *data = snd_async_handler_get_callback_private(ahandler);

  int first = 0, err;

  while (1) {
    snd_pcm_state_t state = snd_pcm_state(handle);
    if (state == SND_PCM_STATE_XRUN) {
      err = xrun_recovery(handle, -EPIPE);
      if (err < 0) {
        printf("XRUN recovery failed: %s\n", snd_strerror(err));
        exit(EXIT_FAILURE);
      }
      first = 1;

    } else if (state == SND_PCM_STATE_SUSPENDED) {
      err = xrun_recovery(handle, -ESTRPIPE);
      if (err < 0) {
        printf("SUSPEND recovery failed: %s\n", snd_strerror(err));
        exit(EXIT_FAILURE);
      }
    }

    snd_pcm_sframes_t avail = snd_pcm_avail_update(handle);
    if (avail < 0) {
      err = xrun_recovery(handle, avail);
      if (err < 0) {
        printf("avail update failed: %s\n", snd_strerror(err));
        exit(EXIT_FAILURE);
      }
      first = 1;
      continue;
    }

    if (avail < period_size) {
      if (first) {
        first = 0;
        err = snd_pcm_start(handle);
        if (err < 0) {
          printf("Start error: %s\n", snd_strerror(err));
          exit(EXIT_FAILURE);
        }
      } else {
        break;
      }
      continue;
    }

    snd_pcm_uframes_t offset, frames, size;
    size = period_size;

    while (size > 0) {
      frames = size;

      const snd_pcm_channel_area_t *my_areas;
      err = snd_pcm_mmap_begin(handle, &my_areas, &offset, &frames);
      if (err < 0) {
        if ((err = xrun_recovery(handle, err)) < 0) {
          printf("MMAP begin avail error: %s\n", snd_strerror(err));
          exit(EXIT_FAILURE);
        }
        first = 1;
      }

      generate_sine(my_areas, offset, frames);

      snd_pcm_sframes_t commitres = snd_pcm_mmap_commit(handle, offset, frames);
      if (commitres < 0 || (snd_pcm_uframes_t)commitres != frames) {
        if ((err = xrun_recovery(handle, commitres >= 0 ? -EPIPE : commitres)) < 0) {
          printf("MMAP commit error: %s\n", snd_strerror(err));
          exit(EXIT_FAILURE);
        }
        first = 1;
      }
      size -= frames;
    }
  }
}

static void *async_direct_loop(void *arg)
{
  snd_pcm_t *handle = (snd_pcm_t *) arg;
  struct async_private_data data;
  snd_async_handler_t *ahandler;
  const snd_pcm_channel_area_t *my_areas;
  snd_pcm_uframes_t offset, frames, size;
  snd_pcm_sframes_t commitres;
  int err, count;
  data.samples = NULL;    /* we do not require the global sample area for direct write */
  data.areas = NULL;      /* we do not require the global areas for direct write */

  err = snd_async_add_pcm_handler(&ahandler, handle, async_direct_callback, &data);

  if (err < 0) {
    printf("Unable to register async handler\n");
    exit(EXIT_FAILURE);
  }

  for (count = 0; count < 2; count++) {
    size = period_size;
    while (size > 0) {
      frames = size;
      err = snd_pcm_mmap_begin(handle, &my_areas, &offset, &frames);
      if (err < 0) {
        if ((err = xrun_recovery(handle, err)) < 0) {
          printf("MMAP begin avail error: %s\n", snd_strerror(err));
          exit(EXIT_FAILURE);
        }
      }

      generate_sine(my_areas, offset, frames);

      commitres = snd_pcm_mmap_commit(handle, offset, frames);
      if (commitres < 0 || (snd_pcm_uframes_t)commitres != frames) {
        if ((err = xrun_recovery(handle, commitres >= 0 ? -EPIPE : commitres)) < 0) {
          printf("MMAP commit error: %s\n", snd_strerror(err));
          exit(EXIT_FAILURE);
        }
      }
      size -= frames;
    }
  }

  err = snd_pcm_start(handle);
  if (err < 0) {
    printf("Start error: %s\n", snd_strerror(err));
    exit(EXIT_FAILURE);
  }

  while (1) {
    sleep(1);
  }
}


int main(int argc, char *argv[])
{
  int k;
  printf("Recognized sample formats are:");
  for (k = 0; k < SND_PCM_FORMAT_LAST; ++k) {
    const char *s = snd_pcm_format_name(k);
    if (s) {
      printf(" %s", s);
    }
  }
  printf("\n");

  snd_pcm_t *handle;
  int err, morehelp;
  snd_pcm_hw_params_t *hwparams;
  snd_pcm_sw_params_t *swparams;
  int method = 0;
  signed short *samples;
  unsigned int chn;
  snd_pcm_channel_area_t *areas;
  snd_pcm_hw_params_malloc(&hwparams);
  snd_pcm_sw_params_malloc(&swparams);
  morehelp = 0;

  err = snd_output_stdio_attach(&output, stdout, 0);
  if (err < 0) {
    printf("Output failed: %s\n", snd_strerror(err));
    return 0;
  }

  printf("Playback device is %s\n", device);
  printf("Stream parameters are %iHz, %s, %i channels\n", rate, snd_pcm_format_name(format), channels);
  printf("Sine wave rate is %.4fHz\n", freq);

  if ((err = snd_pcm_open(&handle, device, SND_PCM_STREAM_PLAYBACK, 0)) < 0) {
    printf("Playback open error: %s\n", snd_strerror(err));
    return 0;
  }

//  if (err = set_hwparams(handle, hwparams, SND_PCM_ACCESS_RW_INTERLEAVED) < 0) {
  if (err = set_hwparams(handle, hwparams, SND_PCM_ACCESS_MMAP_NONINTERLEAVED) < 0) {
    printf("Setting of hwparams failed: %s\n", snd_strerror(err));
    exit(EXIT_FAILURE);
  }

  if ((err = set_swparams(handle, swparams)) < 0) {
    printf("Setting of swparams failed: %s\n", snd_strerror(err));
    exit(EXIT_FAILURE);
  }

  snd_pcm_dump(handle, output);

  samples = malloc((period_size * channels * snd_pcm_format_physical_width(format)) / 8);
  if (samples == NULL) {
    printf("No enough memory\n");
    exit(EXIT_FAILURE);
  }

  areas = calloc(channels, sizeof(snd_pcm_channel_area_t));
  if (areas == NULL) {
    printf("No enough memory\n");
    exit(EXIT_FAILURE);
  }

  for (chn = 0; chn < channels; chn++) {
    areas[chn].addr = samples;
    areas[chn].first = chn * snd_pcm_format_physical_width(format);
    areas[chn].step = channels * snd_pcm_format_physical_width(format);
  }

  pthread_t playback_thread;
  pthread_create(&playback_thread, NULL, &async_direct_loop, (void *) handle);


  while (1) {
    usleep(1000);
    printf("*");
    fflush(0);
  }

  free(areas);
  free(samples);
  snd_pcm_close(handle);

  return 0;
}
