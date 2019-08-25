# nim-mod

Some people ride ridiculously expensive Harley-Davidsons, collect vintage
guitars or marry 20-year younger platinum blondes when midlife crisis strikes.

I write modplayers.

<img src="img/nim-mod-1.png" align="left" width="48%" alt="nim-mod - pattern view" />
<img src="img/nim-mod-2.png" width="48%" alt="nim-mod - samples view" />


## Features

* Pretty accurate **Amiga ProTracker 2.3D** compatible playback
* Supports **4-channel SoundTracker** (15 samples), **4-channel ProTracker** (31
  samples) and other **2-99 channel MOD formats** (FastTracker II, OctaMED,
  StarTrekker etc.)
* Cross-platform (Windows, Linux & OS X)
* Kickass console UI with many cool colourschemes
* WAV writer (16/24-bit integer, 32-bit float)
* Change play position during playback with speed/tempo & pattern jump chasing
* Song length calculation with loop detection
* Adjustable stereo width
* Vim-inspired keyboard shortcuts (**SUPR IMPRTANT!!!!!11**)
* Uses FMOD for audio playback (*just* for the audio---the playroutine is custom implemented)

## Usage

*(Substitute **nimmod** with **nimmod.exe** on Windows and **./nimmod** on
Linux & OS X)*

Play `foo.mod`:

```
nimmod foo.mod
```

Play `foo.mod` and explicitly set the buffer size (experiment with larger
values if experiencing audio drop-outs):

```
nimmod --bufferSize=4096 foo.mod
```

Display the calculated non-looped length of `foo.mod` and exit:

```
nimmod --showLength foo.mod
```

Render `foo.mod` to a 24-bit/48kHz WAV file called `foo.wav`:

```
nimmod --output=wav --bitDepth=24 --sampleRate=48000 --outFilename=foo.wav foo.mod
```

Play `foo.mod` without displaying the UI and show detailed debug info:

```
nimmod --noUserInterace --verbose foo.mod
```

Run `nimmod -h` to see the full list of command line options.


## Note for Windows users

The default Windows console raster font doesn't include Unicode box drawing
characters, so if you see some random garbage on the screen, most likely
that's the culprit. The solution is to set the console font to **Lucida
Console** or some other font that includes the Unicode box drawing characters.
Note that not all fonts will work well, some will result in discontinuous
lines—you'll need to experiment.


## Where to find modules?

Check out the [data directory](data/) in this repo for a (in my opinion) very
good selection of classic modules.

Visit the following huge online collections if you need more!

* https://modarchive.org/
* http://amp.dascene.net/
* https://www.exotica.org.uk/
* https://www.exotica.org.uk/wiki/Modland


## Building

**nimmod** requires Nim 0.18.0+ and depends on the
[fmod](https://github.com/johnnovak/nim-fmod),
[illwill](https://github.com/johnnovak/illwill) and
[easyWave](https://github.com/johnnovak/easyWave) Nim packages. Install them
with [Nimble](https://github.com/nim-lang/nimble):

```
nimble install fmod illwill easywav
```

Then do a release build:

```
cd src
nim c -r -d:release nimmod
```

After this, you can run the render tests:

```
cd test
nim c -r rendertest
```

## License

Copyright © 2016-2019 John Novak <<john@johnnovak.net>>

This work is free. You can redistribute it and/or modify it under the terms of
the [Do What The Fuck You Want To Public License, Version 2](http://www.wtfpl.net/), as published
by Sam Hocevar. See the [COPYING](./COPYING) file for more details.



