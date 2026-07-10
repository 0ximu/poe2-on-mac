#!/bin/zsh
# play-poe2 - launcher for Path of Exile 2 in a Sikarugir/Wineskin wrapper on macOS.
#
# Reads its paths from ~/.config/poe2-mac/config (created by install.sh).
# Before every launch it repairs the three things known to silently break the
# wrapper (see docs/TROUBLESHOOTING.md), then starts the game with feedback
# via macOS notifications.

CONFIG="$HOME/.config/poe2-mac/config"
if [[ ! -f "$CONFIG" ]]; then
  osascript -e 'display alert "Play POE2" message "No config found. Run install.sh from the poe2-on-mac repo first."' >/dev/null 2>&1
  echo "No config at $CONFIG. Run install.sh first." >&2
  exit 1
fi
source "$CONFIG"   # sets WRAPPER_APP and GAME_EXE

note() { osascript -e "display notification \"$1\" with title \"Play POE2\"" >/dev/null 2>&1 }

WRAP="$WRAPPER_APP/Contents/MacOS/Sikarugir"
[[ -x "$WRAP" ]] || WRAP="$WRAPPER_APP/Contents/MacOS/wineskinlauncher"
PREFIX="$WRAPPER_APP/Contents/SharedSupport/prefix"
WINE_SCOPE="$WRAPPER_APP/Contents/SharedSupport/wine"

# ---------------------------------------------------------------------------
# 1. Is the wrapper reachable? (external drives unmount, paths move)
# ---------------------------------------------------------------------------
if [[ ! -x "$WRAP" || ! -f "$GAME_EXE" ]]; then
  note "Can't find the game. Is the drive with ${WRAPPER_APP:t} plugged in?"
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. Self-heal known breakages by running poe2-heal in quiet mode.
#    All repair logic lives in heal-prefix.sh (single source of truth);
#    quiet mode prints only [FIXED]/[FAIL] lines, which we relay as
#    notifications. A missing heal script never blocks launching.
# ---------------------------------------------------------------------------
for HEAL in "$HOME/.local/bin/poe2-heal" "${0:a:h}/heal-prefix.sh"; do
  [[ -f "$HEAL" ]] && break
done
if [[ -f "$HEAL" ]]; then
  heal_out=$(zsh "$HEAL" --quiet "$WRAPPER_APP" 2>/dev/null)
  if print -r -- "$heal_out" | grep -q "\[FAIL\]"; then
    note "Some repairs failed. Run poe2-heal in Terminal for details."
  elif [[ -n "$heal_out" ]]; then
    note "Repaired game files before launch."
  fi
fi

# ---------------------------------------------------------------------------
# 3. Already running? Don't spawn a second copy.
# ---------------------------------------------------------------------------
if pgrep -f "PathOfExile.exe" >/dev/null 2>&1; then
  note "POE2 is already running (check other Spaces / behind windows)."
  exit 0
fi

# ---------------------------------------------------------------------------
# 4. A leftover wine session from a crash blocks relaunch. Clear it.
#    pkill is scoped to THIS wrapper's wine path so nothing else is touched.
# ---------------------------------------------------------------------------
if pgrep -f "$WINE_SCOPE" >/dev/null 2>&1; then
  note "Clearing a leftover session, then launching..."
  pkill -f "$WINE_SCOPE" 2>/dev/null
  sleep 3
fi

# ---------------------------------------------------------------------------
# 5. Launch. First frames can take ~30s (renderer init + shader cache).
# ---------------------------------------------------------------------------
note "Launching POE2... (first frames can take ~30 seconds)"
nohup "$WRAP" WSS-installer "$GAME_EXE" >/tmp/poe2_last_launch.log 2>&1 &
exit 0
