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
# 2. Self-heal known breakages. All three have actually happened in the wild,
#    usually after an external drive remount. Each is harmless to re-check.
# ---------------------------------------------------------------------------

# a) The drive-map folder lost its execute bit. Wine then can't enter its own
#    C: drive and the game dies instantly with no log at all
#    ("wine: could not load kernel32.dll").
DOSDEV="$PREFIX/dosdevices"
if [[ -d "$DOSDEV" && ! -x "$DOSDEV" ]]; then
  chmod 0777 "$DOSDEV" 2>/dev/null && note "Repaired drive-map permissions."
fi

# b) wineserver loads libinotify through its rpath (SharedSupport/). If that
#    link is gone, wineserver can't start and the launcher exits silently.
if [[ -f "$WRAPPER_APP/Contents/Frameworks/libinotify.0.dylib" && \
      ! -e "$WRAPPER_APP/Contents/SharedSupport/libinotify.0.dylib" ]]; then
  ln -sf "../Frameworks/libinotify.0.dylib" \
        "$WRAPPER_APP/Contents/SharedSupport/libinotify.0.dylib" 2>/dev/null
fi

# c) The Documents symlink inside the prefix got replaced by an empty folder.
#    The game then reads a blank config, falls back to the Vulkan renderer,
#    and crashes with "[VULKAN] Failed to allocate texture [Depth]".
#    Wineskin's default is to link every wine user's Documents to the real
#    macOS Documents folder, so restore exactly that.
for userdir in "$PREFIX/drive_c/users"/*(N/); do
  [[ "${userdir:t}" == "Public" ]] && continue
  link="$userdir/Documents"
  if [[ "$(readlink "$link" 2>/dev/null)" != "$HOME/Documents" ]]; then
    if [[ -e "$link" && ! -L "$link" ]]; then
      mv "$link" "${link}.broken-$(date +%Y%m%d-%H%M%S)" 2>/dev/null  # preserve, never delete
    else
      rm -f "$link" 2>/dev/null                                       # dangling/wrong symlink
    fi
    ln -s "$HOME/Documents" "$link" 2>/dev/null && note "Repaired game config link."
  fi
done

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
