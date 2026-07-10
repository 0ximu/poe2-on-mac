#!/bin/zsh
# heal-prefix.sh - standalone "doctor" for a Sikarugir/Wineskin POE2 wrapper.
#
# Run this when the game refuses to start or crashes with the Vulkan depth
# error. It checks and repairs the known failure points, telling you what it
# found at each step. Safe to run any number of times.
#
# Usage:
#   ./heal-prefix.sh                 (uses ~/.config/poe2-mac/config)
#   ./heal-prefix.sh /path/to/POE2.app   (explicit wrapper path)

if [[ -n "$1" ]]; then
  WRAPPER_APP="$1"
elif [[ -f "$HOME/.config/poe2-mac/config" ]]; then
  source "$HOME/.config/poe2-mac/config"
else
  echo "Usage: $0 /path/to/YourWrapper.app  (or run install.sh first)" >&2
  exit 1
fi

PREFIX="$WRAPPER_APP/Contents/SharedSupport/prefix"
ok=0; fixed=0; failed=0

say()  { print -r -- "$@" }
# note: ((++x)), not ((x++)). Post-increment evaluates to the OLD value, so the
# first ((x++)) on a zero counter returns "false" and poisons && / || chains.
pass() { say "  [ok]    $1"; (( ++ok )) }
fix()  { say "  [FIXED] $1"; (( ++fixed )) }
bad()  { say "  [FAIL]  $1"; (( ++failed )) }

say "Checking wrapper: $WRAPPER_APP"
say ""

# --- 0. basics -------------------------------------------------------------
if [[ ! -d "$PREFIX/drive_c" ]]; then
  bad "No wine prefix found at $PREFIX. Wrong path, or drive not mounted?"
  exit 1
fi
pass "wine prefix found"

# --- 1. dosdevices execute bit ----------------------------------------------
# Without it, wine can't reach its own C: drive and the game dies with no log.
DOSDEV="$PREFIX/dosdevices"
if [[ ! -d "$DOSDEV" ]]; then
  bad "dosdevices folder is missing entirely. The prefix may need to be recreated."
elif [[ ! -x "$DOSDEV" ]]; then
  chmod 0777 "$DOSDEV" && fix "dosdevices had lost its execute bit (wine was locked out of C:)" \
                       || bad "could not chmod $DOSDEV"
else
  pass "dosdevices permissions"
fi

# --- 2. libinotify link for wineserver --------------------------------------
# wineserver looks for libinotify.0.dylib next to SharedSupport/. If the link
# is gone, wineserver can't start and every launch fails silently.
FW_LIB="$WRAPPER_APP/Contents/Frameworks/libinotify.0.dylib"
SS_LIB="$WRAPPER_APP/Contents/SharedSupport/libinotify.0.dylib"
if [[ -f "$FW_LIB" ]]; then
  if [[ -e "$SS_LIB" ]]; then
    pass "libinotify link for wineserver"
  else
    ln -sf "../Frameworks/libinotify.0.dylib" "$SS_LIB" \
      && fix "restored libinotify link (wineserver could not start without it)" \
      || bad "could not create $SS_LIB"
  fi
else
  pass "wrapper does not use a Frameworks libinotify (nothing to do)"
fi

# --- 3. Documents symlink per wine user --------------------------------------
# If this link becomes a plain folder, the game reads a blank config, falls
# back to Vulkan, and crashes with "Failed to allocate texture [Depth]".
for userdir in "$PREFIX/drive_c/users"/*(N/); do
  u="${userdir:t}"
  [[ "$u" == "Public" ]] && continue
  link="$userdir/Documents"
  if [[ "$(readlink "$link" 2>/dev/null)" == "$HOME/Documents" ]]; then
    pass "Documents link for wine user '$u'"
  else
    [[ -e "$link" && ! -L "$link" ]] && mv "$link" "${link}.broken-$(date +%Y%m%d-%H%M%S)"
    rm -f "$link" 2>/dev/null
    ln -s "$HOME/Documents" "$link" \
      && fix "Documents link for wine user '$u' (was broken; game would crash on Vulkan)" \
      || bad "could not link Documents for wine user '$u'"
  fi
done

# --- 4. renderer sanity in the game config -----------------------------------
# DirectX12 is the only renderer that works through D3DMetal on Apple Silicon.
CFG="$HOME/Documents/My Games/Path of Exile 2/poe2_production_Config.ini"
if [[ -f "$CFG" ]]; then
  r=$(grep -aoE 'renderer_type=[A-Za-z0-9]+' "$CFG" | head -1)
  if [[ "$r" == "renderer_type=DirectX12" ]]; then
    pass "config renderer is DirectX12"
  else
    say "  [WARN]  config says '$r'. On Apple Silicon it must be DirectX12."
    say "          Fix it in game (Options > Graphics > Renderer) or edit:"
    say "          $CFG"
  fi
else
  say "  [note]  no game config yet at '$CFG' (normal before first run)"
fi

# --- 5. stale wine sockets ----------------------------------------------------
for d in /tmp/.wine-*(N/); do
  say "  [note]  stale wine socket dir: $d (harmless; cleared automatically on launch)"
done

say ""
say "Done: $ok ok, $fixed fixed, $failed failed."
[[ $failed -gt 0 ]] && exit 1
exit 0
