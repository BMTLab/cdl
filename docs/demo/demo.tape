# docs/demo/demo.tape
#
# The demo of the README, recorded by vhs (https://github.com/charmbracelet/vhs):
#   make demo
# writes docs/demo/demo.gif. docs/demo/setup.bash builds the scratch HOME
# it walks through, so every machine records the same listings.

Output "docs/demo/demo.gif"

Set Shell "bash"
Set FontFamily "Hack"
Set FontSize 16
Set Width 1200
Set Height 640
Set Padding 24
Set Theme "Catppuccin Mocha"
Set WindowBar Colorful
Set BorderRadius 10
Set TypingSpeed 55ms
Set Framerate 24

Hide
Type "source docs/demo/setup.bash && clear"
Enter
Sleep 1s
Show

# A project: the header with its git branch, then as many columns as fit.
Type "cdl projects/aurora"
Sleep 400ms
Enter
Sleep 3s

# A file: cdl enters its directory and marks it.
Type "cdl docs/guide.md"
Sleep 400ms
Enter
Sleep 3s

# Back where it was.
Type "cdl -"
Sleep 400ms
Enter
Sleep 2s

# Tab completes directories and files.
Ctrl+L
Type "cdl as"
Sleep 500ms
Tab
Sleep 700ms
Enter
Sleep 2500ms

# A long listing stays on screen, and shows the file it was asked for.
Ctrl+L
Type "cdl ~/photos/IMG_2180.jpg"
Sleep 400ms
Enter
Sleep 3500ms

# An error says what is wrong, and returns a code of its own.
Ctrl+L
Type "cdl ../vault/inner; echo $?"
Sleep 400ms
Enter
Sleep 3s
