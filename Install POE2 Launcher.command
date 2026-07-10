#!/bin/zsh
# Double-click me! macOS opens .command files in Terminal automatically.
# (If macOS complains about an unidentified developer: right-click me,
#  choose "Open", then click "Open" in the dialog. Only needed once.)
cd "$(dirname "$0")"
exec zsh ./install.sh
