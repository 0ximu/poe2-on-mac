#!/bin/zsh
# install.sh - one-time setup for poe2-on-mac.
#
# What it does:
#   1. Finds your POE2 wrapper app (or lets you drag it into the Terminal).
#   2. Finds PathOfExile.exe inside it.
#   3. Saves both paths to ~/.config/poe2-mac/config.
#   4. Installs the play-poe2 launcher to ~/.local/bin.
#   5. Creates a double-clickable "Play POE2" app on your Desktop,
#      using your wrapper's own icon.
#   6. Runs the repair checks once so you start from a healthy state.
#
# It never touches the game itself and never needs sudo.

setopt NULL_GLOB
REPO_DIR="${0:a:h}"
REPO_URL="https://github.com/0ximu/poe2-on-mac"

say()   { print -r -- "$@" }
title() { say ""; say "==> $1" }

# When run via `curl | zsh`, stdin is the pipe, not the keyboard. Reattach it
# so the interactive prompts below still work.
if [[ ! -t 0 ]] && (exec < /dev/tty) 2>/dev/null; then
  exec < /dev/tty
fi

# Self-bootstrap: if this file was downloaded on its own (curl one-liner),
# fetch the rest of the repo to a temp folder and continue from there.
if [[ ! -f "$REPO_DIR/scripts/play-poe2.sh" ]]; then
  say "Downloading poe2-on-mac..."
  TMP=$(mktemp -d)
  curl -fsSL "$REPO_URL/archive/refs/heads/main.tar.gz" | tar xz -C "$TMP" || {
    say "Download failed. Check your internet connection and try again."; exit 1
  }
  exec zsh "$TMP"/poe2-on-mac-*/install.sh
fi

say "poe2-on-mac installer"
say "This sets up a one-click launcher for Path of Exile 2 in a Sikarugir/Wineskin wrapper."

# ---------------------------------------------------------------------------
# 1. Find the wrapper app
# ---------------------------------------------------------------------------
title "Looking for your POE2 wrapper app..."

is_wrapper() {
  # A wrapper is any .app with a wine prefix inside it.
  [[ -d "$1/Contents/SharedSupport/prefix/drive_c" ]]
}

typeset -a candidates
for dir in "$HOME/Applications" /Applications /Volumes/*; do
  [[ -d "$dir" ]] || continue
  for app in "$dir"/*.app "$dir"/*/*.app; do
    is_wrapper "$app" && candidates+=("$app")
  done
done

WRAPPER_APP=""
if (( ${#candidates} == 1 )); then
  WRAPPER_APP="${candidates[1]}"
  say "Found: $WRAPPER_APP"
elif (( ${#candidates} > 1 )); then
  say "Found more than one wrapper app:"
  local i=1
  for c in "${candidates[@]}"; do say "  $i) $c"; ((i++)); done
  say -n "Which one is Path of Exile 2? Type the number and press Enter: "
  read choice
  WRAPPER_APP="${candidates[$choice]}"
fi

while [[ -z "$WRAPPER_APP" || ! -d "$WRAPPER_APP" ]]; do
  say ""
  say "Couldn't find it automatically. That's fine:"
  say "  Drag your wrapper app (e.g. POE2.app) from Finder into this window,"
  say -n "  then press Enter: "
  read WRAPPER_APP
  WRAPPER_APP="${WRAPPER_APP%% }"      # trim the trailing space Finder adds
  WRAPPER_APP="${WRAPPER_APP//\\/}"    # strip escape backslashes
  if ! is_wrapper "$WRAPPER_APP"; then
    say "  Hmm, '$WRAPPER_APP' doesn't look like a wine wrapper (no prefix inside)."
    WRAPPER_APP=""
  fi
done
say "Using wrapper: $WRAPPER_APP"

# ---------------------------------------------------------------------------
# 2. Find PathOfExile.exe inside the wrapper
# ---------------------------------------------------------------------------
title "Looking for PathOfExile.exe inside the wrapper..."
GAME_EXE=$(find "$WRAPPER_APP/Contents/SharedSupport/prefix/drive_c" \
             -maxdepth 6 -name "PathOfExile.exe" -path "*Path of Exile 2*" 2>/dev/null | head -1)
if [[ -z "$GAME_EXE" ]]; then
  GAME_EXE=$(find "$WRAPPER_APP/Contents/SharedSupport/prefix/drive_c" \
               -maxdepth 6 -name "PathOfExile.exe" 2>/dev/null | head -1)
fi
if [[ -z "$GAME_EXE" ]]; then
  say "Could not find PathOfExile.exe inside the wrapper."
  say "Install the game inside the wrapper first (see README step 2), then rerun this."
  exit 1
fi
say "Found: $GAME_EXE"

# ---------------------------------------------------------------------------
# 3. Save the config
# ---------------------------------------------------------------------------
title "Saving config..."
mkdir -p "$HOME/.config/poe2-mac"
cat > "$HOME/.config/poe2-mac/config" <<EOF
# Written by poe2-on-mac install.sh on $(date '+%Y-%m-%d %H:%M')
WRAPPER_APP="$WRAPPER_APP"
GAME_EXE="$GAME_EXE"
EOF
say "Saved to ~/.config/poe2-mac/config"

# ---------------------------------------------------------------------------
# 4. Install the launcher
# ---------------------------------------------------------------------------
title "Installing the launcher..."
mkdir -p "$HOME/.local/bin"
cp "$REPO_DIR/scripts/play-poe2.sh" "$HOME/.local/bin/play-poe2"
cp "$REPO_DIR/scripts/heal-prefix.sh" "$HOME/.local/bin/poe2-heal"
chmod +x "$HOME/.local/bin/play-poe2" "$HOME/.local/bin/poe2-heal"
say "Installed: ~/.local/bin/play-poe2 and ~/.local/bin/poe2-heal"

# ---------------------------------------------------------------------------
# 5. Create the Desktop app
# ---------------------------------------------------------------------------
title "Creating 'Play POE2' on your Desktop..."
DESKTOP_APP="$HOME/Desktop/Play POE2.app"
if [[ -e "$DESKTOP_APP" ]]; then
  mv "$DESKTOP_APP" "$HOME/.play-poe2-old-$(date +%s).app" 2>/dev/null
fi
osacompile -o "$DESKTOP_APP" -e "do shell script \"$HOME/.local/bin/play-poe2\"" >/dev/null

# Give it the wrapper's own icon so it looks like the game, not a script.
for icns in "$WRAPPER_APP/Contents/Resources"/*.icns; do
  cp "$icns" "$DESKTOP_APP/Contents/Resources/applet.icns" && break
done
xattr -cr "$DESKTOP_APP" 2>/dev/null
codesign --force --deep -s - "$DESKTOP_APP" >/dev/null 2>&1
say "Created: $DESKTOP_APP"

# ---------------------------------------------------------------------------
# 6. Run the repair checks once
# ---------------------------------------------------------------------------
title "Running health checks on the wrapper..."
zsh "$HOME/.local/bin/poe2-heal" "$WRAPPER_APP"

say ""
say "All set. Double-click 'Play POE2' on your Desktop to play."
say "If anything ever breaks, run:  ~/.local/bin/poe2-heal"
