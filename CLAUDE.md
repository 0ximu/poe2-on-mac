# CLAUDE.md

Context for AI coding assistants (Claude Code and friends) helping a user with this repo. A human pointed you here because their Path of Exile 2 setup on macOS is broken, slow, or being set up for the first time. This file gives you the map so you don't rediscover it from scratch.

## What this repo is

Scripts and docs for running Path of Exile 2 (a Windows game) on Apple Silicon Macs through a Sikarugir/Wineskin wine wrapper with D3DMetal (DirectX 12 to Metal translation). The repo contains no game files and no wine binaries. The user owns a wrapper app that bundles everything; this repo installs a launcher and repair tooling around it.

## Where things are on the user's machine

- `~/.config/poe2-mac/config` holds `WRAPPER_APP` and `GAME_EXE` paths. Read this first; every other path derives from it.
- Inside the wrapper app:
  - wine prefix: `<WRAPPER_APP>/Contents/SharedSupport/prefix`
  - game log: `<prefix>/drive_c/Program Files (x86)/Grinding Gear Games/Path of Exile 2 - poe2_production/logs/Client.txt`
  - drive map: `<prefix>/dosdevices`
  - wine users: `<prefix>/drive_c/users/<name>` (some may be symlink aliases of one real dir)
- Game config: `~/Documents/My Games/Path of Exile 2/poe2_production_Config.ini`, reached by the game through a `Documents` symlink inside each wine user dir pointing at the real `~/Documents`.
- Installed tools: `~/.local/bin/play-poe2` (launcher) and `~/.local/bin/poe2-heal` (repair).
- Launch feedback: `/tmp/poe2_last_launch.log`.

## Diagnostic workflow (do this before theorizing)

1. `tail -40 "<Client.txt>"` - the game logs its own death well. Check the timestamp to confirm you're looking at the failing session, not an old one.
2. `~/.local/bin/poe2-heal` - fixes the three known silent breakages and reports what it found.
3. `pgrep -fl "PathOfExile.exe"` and `pgrep -fl wineserver` - distinguish "not running" from "hung".
4. If the game produces zero new log lines on launch, the failure is below the game (wine layer), not in the game. See failure signatures.

## Known failure signatures

| Evidence | Cause | Fix |
|---|---|---|
| No new Client.txt lines at all, wrapper prints `Secondary run` and exits | `dosdevices` lost its execute bit, wine can't reach C: | `chmod 0777 <prefix>/dosdevices` (poe2-heal does it) |
| `wineserver` fails with `Library not loaded: @rpath/libinotify.0.dylib` | SharedSupport symlink to Frameworks lib vanished | `ln -sf ../Frameworks/libinotify.0.dylib <WRAPPER_APP>/Contents/SharedSupport/libinotify.0.dylib` |
| Dialog/log: `[VULKAN] Failed to allocate texture [Depth]`, `VK_ERROR_FEATURE_NOT_PRESENT` | Documents symlink broke, game read a blank config and fell back to Vulkan | restore symlink to `~/Documents` (poe2-heal). Never "fix" by switching to Vulkan; DX12 is the only working renderer |
| `Deadlock detected with timeout 15000ms; running graph nodes: UIUpdate` | render thread stalled 15s, game killed itself | in game: disable Engine Multithreading, cap FPS at refresh rate, lower shadows. Expect rare, not never |
| `nodrv_CreateWindow ... no driver could be loaded` | launched from a detached shell/SSH/cron | launch via `open` or the Desktop app; wine needs the GUI session |
| Log shows `Wiping cache ShaderCache...`, slow first boot after patch | normal shader cache rebuild | wait it out once, don't force quit |
| Audio on wrong device | `audio_device_id` pins output by exact name, unicode apostrophes included | change in game (Options > Audio), or edit config byte exact while game is closed |

## Hard rules

- **Preserve, never delete.** When replacing a broken dir/file, `mv` it aside with a timestamp suffix. The scripts follow this convention; keep it.
- **DirectX 12 only.** Vulkan structurally cannot work here (no depth buffer allocation through MoltenVK). Any advice to switch renderer away from DX12 is wrong.
- **Config edits do not always stick.** The game rewrites `poe2_production_Config.ini` on clean exit and silently reverts values it dislikes. `engine_multithreading_mode` in particular only persists when changed in the game menu. Prefer in-game changes; only hand-edit with the game fully closed, and verify after next exit.
- **Test launches must run in the user's GUI session** (`open` / Desktop app). Detached launches fail at window creation and will mislead you into debugging a healthy setup. This has burned people before.
- **Kill processes narrowly.** Target PIDs from `pgrep -f` scoped to the wrapper path. No broad killall.
- **External drives are a recurring root cause.** Remounts scramble prefix permissions and symlinks. If several things broke at once, suspect the drive, then run poe2-heal rather than chasing each symptom.

## Working on the repo itself

- Scripts are zsh (`#!/bin/zsh`), macOS built-in, no bash 4 features, no external deps beyond standard macOS tools.
- Syntax check: `zsh -n <script>`. Functional check: `zsh scripts/heal-prefix.sh /path/to/Wrapper.app` is read-only-ish (only repairs, idempotent) and safe to run against a healthy wrapper; expect all `[ok]`.
- `install.sh` self-bootstraps when downloaded alone (curl one-liner), reattaches stdin from `/dev/tty` when piped, and must keep working with zero prompts when exactly one wrapper is found.
- zsh gotcha that already bit us once: `((x++))` on a zero counter evaluates false and poisons `&&`/`||` chains. Use `(( ++x ))`.
- Docs style: plain language for non-developers, no em dashes, symptom first then cause then fix.
