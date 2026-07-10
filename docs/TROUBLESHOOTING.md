# Troubleshooting

Every entry here is a failure we actually hit, diagnosed from logs, and fixed. Find your symptom, read the cause, apply the fix.

**Golden rule: run `~/.local/bin/poe2-heal` first.** It auto-fixes the top three causes below and tells you what it found. The launcher also runs the same repairs before every start, so most of these can only bite you if you launch the wrapper directly.

The game log lives at:

```
<YourWrapper.app>/Contents/SharedSupport/prefix/drive_c/Program Files (x86)/Grinding Gear Games/Path of Exile 2 - poe2_production/logs/Client.txt
```

When in doubt, look at its last 30 lines. The game logs its own death surprisingly well.

---

## Game won't start at all. No window, no log entry, nothing.

**Symptom:** you launch, the wrapper seems to do something for a second, then nothing. `Client.txt` gets no new lines at all.

**Cause A: wine is locked out of its own C: drive.**
The `dosdevices` folder inside the prefix lost its execute permission (this can happen after an external drive remount). Wine can't resolve `C:`, can't load `kernel32.dll`, and dies before it can log anything.

**Fix:** `poe2-heal` restores the permission. Manually: `chmod 0777 "<Wrapper.app>/Contents/SharedSupport/prefix/dosdevices"`

**Cause B: wineserver can't start because a library link is gone.**
`wineserver` (the process everything else depends on) loads `libinotify.0.dylib` via a relative path. If that link vanishes, every launch fails with the wrapper printing `Secondary run` and quitting. You can confirm with:
`"<Wrapper.app>/Contents/SharedSupport/wine/bin/wineserver" --version` - if it errors with `Library not loaded: @rpath/libinotify.0.dylib`, this is it.

**Fix:** `poe2-heal` recreates the link. Manually:
`ln -sf "../Frameworks/libinotify.0.dylib" "<Wrapper.app>/Contents/SharedSupport/libinotify.0.dylib"`

**Cause C: a leftover session from a crash is blocking relaunch.**
A hung `wineserver` from the previous session makes new launches bail out.

**Fix:** the launcher clears this automatically. Manually: find the PIDs with `pgrep -fl wineserver` and `kill -9` them, or just reboot.

---

## Crash on startup: "[VULKAN] Failed to allocate texture [Depth]"

**Symptom:** an error dialog with exactly that text, seconds after launch. Log shows `[VULKAN] Init SwapChain` and `VK_ERROR_FEATURE_NOT_PRESENT`.

**Cause:** the game lost its config file and fell back to the Vulkan renderer, which cannot allocate a depth buffer through MoltenVK on Macs. You didn't choose Vulkan; a blank config chose it for you. The config goes missing when the `Documents` symlink inside the wine prefix (which points at your real `~/Documents`) gets replaced by an empty folder. Wine prefix updates do this occasionally.

**Fix:** `poe2-heal` restores the symlink, after which the game reads your real config (`renderer_type=DirectX12`) and starts normally. Your settings were never lost, just unreachable.

**Never** "fix" this by actually switching to Vulkan. DirectX 12 is the only renderer that works on Apple Silicon.

---

## Game freezes mid-play, then closes itself after ~15 seconds

**Symptom:** picture freezes, audio may loop, and after about 15 seconds the game quits. Log ends with:
`Deadlock detected with timeout 15000ms; running graph nodes: UIUpdate`

**Cause:** POE2 has a built-in watchdog. If the render thread stalls for 15 seconds, the game kills itself rather than hang your machine. Under D3DMetal this happens occasionally in demanding moments: dense maps, decorated hideouts with visitors, certain particle-heavy weapon effects (skill trail microtransactions are a known trigger, since some trail shaders don't compile through D3DMetal).

**Fixes, in order of impact:**
1. In game: Options > Graphics > **Engine Multithreading > Disabled**. Biggest single improvement. Must be done in game; editing the config file silently reverts.
2. Cap the frame rate to your display's refresh rate.
3. Lower shadows to Low and consider turning off fancy weapon/wing trail MTX if crashes correlate with a specific effect.
4. If the game is on a slow USB drive, move it to Thunderbolt/internal storage. I/O stalls contribute.

Expect "rare", not "never". This is the cost of the translation layer.

---

## No sound in my AirPods / headset

**Symptom:** game audio comes from the Mac speakers even though your headset is connected, or there's no audio at all.

**Cause:** the game pins its output to a specific device name in the config (`audio_device_id=...`). If that says `Mac Studio Speakers`, your AirPods never get a chance.

**Fix:** in game: Options > Audio > output device. Pick your headset. If editing the config file instead, the device name must match **byte for byte**, including Unicode apostrophes in names like `Yavor's AirPods` (that apostrophe is usually U+2019, not the plain `'` your keyboard types).

Also check: if your AirPods are set as the Mac's *input* (microphone) device, macOS may drop them into low-quality phone-call mode. Set input to the Mac's internal mic in System Settings > Sound.

---

## My graphics settings keep reverting

**Symptom:** you edit `poe2_production_Config.ini`, launch, and the file is back to the old value.

**Cause:** the game rewrites the config on every clean exit and silently discards values it considers invalid. Some settings (Engine Multithreading in particular) only accept changes made through the in-game menu.

**Fix:** change settings in game whenever possible. Only hand-edit the file for things the menu doesn't expose, and do it while the game is fully closed.

---

## Stutter / hitching when entering new areas

**Symptom:** frame rate is fine overall, but the game hitches hard when loading into zones or when lots of new enemies appear.

**Cause:** asset streaming from a slow disk. USB SSDs have much worse random-read performance than internal NVMe.

**Fixes:**
- Move the wrapper to internal storage or a Thunderbolt enclosure (biggest fix).
- Lower texture quality; fewer bytes streamed per scene.
- Turn on Dynamic Resolution so the GPU isn't also fighting for headroom during the spike.

---

## Patch fails: updater can't overwrite the game executable

**Symptom:** after GGG ships a patch, the in-game updater errors out and can't replace `PathOfExile.exe`.

**Cause:** wine sometimes holds a lock on the running executable, so the updater writes the new one as `PathOfExile.tmp` and can't swap it in.

**Fix** (credit: the [poewiki Mac guide](https://www.poewiki.net/wiki/Guide:Path_of_Exile_on_Mac_using_Windows_Client)): in the game folder inside the wrapper, rename `PathOfExile.exe` to `PathOfExile.old`, then rename `PathOfExile.tmp` to `PathOfExile.exe`, then launch again to finish the update. Repeat if it recurs on a later patch.

---

## First launch after a patch takes forever

**Symptom:** after a game update, the first launch sits at a black screen or the menu takes 30-60 s to appear. `Client.txt` shows `Wiping cache ShaderCache...`.

**Cause:** the game threw away its compiled shader cache (normal after patches) and is rebuilding it through D3DMetal, which is slower than on Windows.

**Fix:** none needed. Let it finish once; subsequent launches are fast again. Don't force-quit during it or you'll do it all again.

---

## Trade overlay (Exiled Exchange 2): price check shows nothing, overlay itself works

**Symptom:** Exiled Exchange 2 is installed and running, Shift+Space opens the overlay fine, but the price check hotkey does nothing useful. The screen may "bounce" briefly (menu bar flashes into view), then no window, or an empty one. EE2's debug log shows `[ClipboardPoller] No item text found`. Manually pressing Ctrl+C on a hovered item copies the item text fine.

**Cause (two stacked problems, both invisible):**

1. **Wine drops the Alt-modified copy combo.** EE2 doesn't read the item directly; it simulates the game's copy shortcut and reads the clipboard. It builds that shortcut as Ctrl + *show-mods-key* + C, which is **Ctrl+Alt+C** by default. On wine-based installs, synthetic Ctrl+C reaches the game but synthetic **Ctrl+Alt+C never does**. We verified this by sending both combos in isolation: plain Ctrl+C copied item text every time, Ctrl+Alt+C never did. Bonus trap: if your price check hotkey itself uses a held Alt (like Alt+A), your own finger adds the poison modifier.
2. **Focus race.** When the price window opens, the game can briefly lose focus (that's the menu bar flash), and the simulated keystroke fires at the wrong window.

**Fix:**
- Bind price check to a **single key with no modifiers** (e.g. F6) in the EE2 overlay settings.
- The real fix needs EE2 to send plain Ctrl+C instead of Ctrl+Alt+C on wine setups; see [Exiled-Exchange-2 issue #349](https://github.com/Kvan7/Exiled-Exchange-2/issues/349) for the root cause writeup and status. Until it's fixed upstream, the workaround is patching EE2's key simulation locally (reroute the copy tap through System Events with plain Ctrl+C, re-activate the game window first, and extend the clipboard poll timeout; you'll need to re-sign the app and re-grant Accessibility after patching, since editing a bundle invalidates macOS permission grants).
- While testing permissions: EE2 must be launched via `open` / Finder, not by running its binary from a terminal, or macOS attributes its permission checks to the terminal and EE2 exits at startup.

**Expectations after the fix:** price check works reliably; the copied item text is the plain version (no advanced mod tiers), which EE2 parses fine.

---

## Launching from a script/SSH shows nothing

**Symptom:** launching from cron, SSH, or a detached script produces no window; wine logs show `Application tried to create a window, but no driver could be loaded`.

**Cause:** wine needs access to the macOS window server. Only processes started inside your logged-in GUI session get that.

**Fix:** always launch via the Desktop app or `open`, not from detached shells. This one cost us an hour of debugging; learn from our pain.
