import os, terminal

###### styleDim

resetAttributes(stdout)
setStyle(stdout, {styleDim})
setForegroundColor(stdout, fgRed)
stdout.write "darkRed1 "    # prints text with red fg, OK

resetAttributes(stdout)
setForegroundColor(stdout, fgRed)
setStyle(stdout, {styleDim})
stdout.write "darkRed2 "    # prints text with BLACK fg, FAIL!!!

resetAttributes(stdout)
setStyle(stdout, {styleBright})
setBackgroundColor(stdout, bgGreen)
stdout.write "brightGreen1 "    # prints text with bright green bg, OK

resetAttributes(stdout)
setBackgroundColor(stdout, bgGreen)
setStyle(stdout, {styleBright})
stdout.write "brightGreen2 "    # prints text with BLACK bg, FAIL!!!

resetAttributes(stdout)
