import os, strutils

import nimterop/cimport

{.passL: "-lsoundio".}

cIncludeDir("/usr/include/soundio")
cImport("/usr/include/soundio/soundio.h")
