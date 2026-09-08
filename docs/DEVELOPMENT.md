# Developing Mouse Adventure

## Source of truth

Repository: <https://github.com/javi5cript/gen1recomp-mouse-adventure>.
Make changes here, review them with Git, then deploy the packaged result.
The installed `mods\click_to_move` folder is a runtime copy, not a workspace.

Mouse Adventure is interpreted Lua for Gen1Recomp. There is no engine compile,
executable patch, ROM modification or asset import in this workflow.

## One-time Windows setup

Use Windows PowerShell 5.1 or PowerShell 7, Git, Node.js with npm, and a working
Gen1Recomp Windows installation with your own imported game data. The current
baseline is engine 0.2.56 and mod API 2.

From the repository root:

```powershell
npm ci
Copy-Item .dev.example.json .dev.local.json
```

Edit `GameDirectory` in `.dev.local.json` to the folder containing
`gen1recomp.exe`. Relative paths resolve from the repository root, not the
shell's current directory. This file is ignored by Git. Alternatively supply
`-GameDirectory 'C:\Games\gen1recomp-win64'`, or set `GEN1RECOMP_DIR` when no
local configuration file exists. An explicit parameter takes precedence.

The script reads the installed executable's embedded LOVE ZIP and extracts
only engine Lua source into `.dev-cache\engine\<executable-sha256>`. It never
modifies the executable. A changed executable gets a separate source cache.
An unsupported bundle fails explicitly rather than testing unrelated source.
Engine source is local, ignored, and never included in the mod package.

## Edit, commit, deploy

1. Edit the repository's Lua, documentation and regression scenarios.
2. Run `.\scripts\dev.ps1 -Task Test`, then review `git diff`.
3. Commit the intended files on your working branch. Do not add local paths,
   engine files, imported data, saves, `.dev-cache`, `node_modules` or `dist`.
4. Save and close Gen1Recomp, then run `.\scripts\dev.ps1 -Task Install`.
5. Launch the game and exercise the changed behavior. Push the source commit
   when ready; publishing a release or catalog update is a separate decision.

The helper intentionally does not commit or push on your behalf, and allows
uncommitted local builds for iteration. Installation always rebuilds from the
current checkout, so do not change files between the final commit and deploy
if you want the installed copy to match that commit exactly.

| Command | Result |
| --- | --- |
| `.\scripts\dev.ps1 -Task Test` | Parse Lua 5.1, check manifest identity/version, run controls regressions |
| `.\scripts\dev.ps1 -Task Build` | Test, then write `dist\click_to_move-<version>.zip` |
| `.\scripts\dev.ps1 -Task Install` | Test, build, back up and install to `%APPDATA%\pokemon-love2d\mods\click_to_move` |
| `.\scripts\dev.ps1 -Task Run -Game yellow` | Install, start Yellow, and wait until the game closes |
| `.\scripts\dev.ps1 -Task Smoke -AllGames` | Test/build, then run isolated Red, Blue and Yellow opening scenarios |
| `.\scripts\dev.ps1 -Task Smoke -Game red` | Run only the Red opening scenario |

Run also accepts `red` or `blue`. Use Run from a visible terminal when you
want to keep the game open. Neither Install nor Run closes a running game:
save and close it yourself first. Mod enable flags are not altered; enable
Mouse Adventure for the selected game in the mod manager if necessary.

Backups are under `.dev-cache\backups\<timestamp>` and contain the previous
installed mod folder. Only the seven allowlisted runtime files are overwritten;
unrecognized existing files are preserved. If deployment fails, do not launch
until you restore that backup with the game closed. Restore only this mod's
folder, never the whole user-data directory. Both cached sources and backups
are local development data; retain needed backups before removing caches.

The ZIP has seven files directly at its root:
`manifest.json`, `main.lua`, `mouse_ui.lua`, `mouse_targets.lua`, `README.md`,
`LICENSE`, and `THIRD_PARTY_NOTICES.md`. Tests, tooling, dependencies,
screenshots, other mods and game data are excluded.

## Regression and play coverage

`tests\run.js`, `tests\controls.lua` and `tests\screens.lua` form the development harness,
now tracked in this repository. Dependencies are locked in `package-lock.json`.
The runner loads native Input, Player, Collision, Camera, menu, intro and title
modules from the installed engine. It extracts the native overworld dispatch
and battle-message methods from that same source.

Graphics, audio, maps, save fixtures and surrounding game services are headless
doubles. These scenarios cover steering, native turn-and-interact dispatch,
counter reach, stale targets, dialogue, startup, menu selection and input
ownership. They do not prove every real map script, pickup reward, sound,
rendering path or external mod combination. Test those in-game before release.

For isolated play coverage, enable only Mouse Adventure for the chosen game.
Include Red, Blue and Yellow; intro/title/Continue; NPCs, signs, item balls,
counters and scenery; dialogue and Oak's Yellow catching demonstration;
menu/battle/naming controls; held movement across doors and map connections.
Preserve saves and do not replace the user's mod settings automatically.

### v1.4.0 QoL coverage

Wheel navigation defaults to ON; early-click, click-versus-hold,
projected-anchor and four-way options default to OFF. Keep both the default
path and each enabled/disabled path in
the controls regressions. The harness uses native Pokedex entry update/cry
methods and PartyMenu input with BattleState's voluntary-switch callback in
addition to the existing menu, text and battle dispatch. Cover SWITCH, STATS
and CANCEL in native, Modern Party and recognized Gen1Party geometry,
active/fainted refusals, forced replacement and stale-click cancellation.
Replacement layout fixtures model the inspected mod geometry; they do not
load or prove the third-party renderer.

`tests\screens.lua` exercises native summary/trainer/map controllers and the
Pokedex's private action menu. When the recognized replacement mods are
installed, the runner extracts their input methods read-only for additional
Modern Party, Modern Pokedex and Gen1Dex cases. Missing optional mods skip
those cases; changed extraction contracts fail explicitly. Horizontal wheel
descriptors must be honored by the input transport, including fractional
notches, native page resets and cancellation before scrolling a different tab.

Dock labels must use dedicated fonts at native size, not a scaled copy of the
font left active by the game or another mod. Cover font inheritance, cache
reuse, DPI changes and pixel alignment alongside each dock size.

Projection tests supply explicit camera coordinates, canvas/DPI geometry and
rejected/missing-frame cases. They must model `Renderer:endFrame` clearing its
world override and `worldActive` flag before `render.hud`. UI target projection
must use the endFrame snapshot, including anchors and classic overlays inside
wide battles, rather than recomputing the now-different UI scale. Cover save
choices at centered/bottom/top-right layouts and unequal DPI scales.

Follower picking is separate from the optional steering anchor: projected
sprite bounds are collected even when centered steering is selected. Cover
native Pikachu and follower aliases, scaled sprites, near versus past clicks,
and missing/rejected/stale camera observations. These fixtures verify the adapter's math
and ownership, not the real GPU pipeline.

Before release, exercise flat/tilt/voxel map edges and camera transitions,
short click versus long hold near NPCs and counters, wheel navigation with
other mouse mods, early clicks during sounds and page changes, and all dock
sizes at narrow/high-DPI resolutions. Ensure a keyboard/controller press,
focus loss, changed list, changed page or changed target cancels queued intent.
Do not enable the opt-ins in the baseline opening profile implicitly.

The guide hotkey's session override must work without `mod.options:set`,
which the baseline engine does not expose. Keep failure-path cases for
engines that do expose setters/persistence; do not silently swallow failures.
Native control key bindings must keep precedence over the guide key.

## Automated opening playthrough

Use Node.js 18 or newer and the normal, non-portable Windows game installation:

```powershell
.\scripts\dev.ps1 -Task Smoke -AllGames
# For a focused iteration:
.\scripts\dev.ps1 -Task Smoke -Game yellow
```

The smoke runner uses the engine's existing `POKEPORT_DRIVER` frame-driver
interface, not its startup-skipping autopilot. It starts the real executable,
renders the real game, and sends left/right mouse press, move and release
callbacks through the same LOVE handlers that Mouse Adventure receives.
It never sets player position/facing, names, inventory, event flags, party,
battle decisions or damage directly.

Each game gets a fresh, unique `mouse-adventure-smoke-<game>-<uuid>` profile
under `%APPDATA%`. Only that game's already-imported `data`, `assets` and cache
marker are copied from the live profile, plus the repository mod and dedicated
test settings. No existing saves or other mods are copied. Portable mode is
refused because it bypasses LOVE's isolated save identity. Normal installed
mods, options and saves are not modified.

The route starts at the intro/title, chooses NEW GAME, types ASH and GARY
on the mouse naming grid, withdraws the bedroom PC's Potion, goes downstairs
and outside, triggers Oak at the northern grass, obtains Charmander in Red,
Squirtle in Blue or Pikachu in Yellow, then completes the first rival battle.
The run stops there, without continuing the adventure. Battle outcomes are
observed, not forced; this is an input/progression test, not a guaranteed-win
or battle-balance test.

Reports live in `.dev-cache\smoke\<run>\<game>`. `environment.json` records the
isolated profile and source/executable hashes. `result.json` records milestones,
state and any failure; `engine.log` contains engine output. Milestone/failure
screenshots are copied to `screenshots`. The all-game command attempts all
three scenarios and returns a failure exit code if any fails.

Runs have bounded stage waits and a ten-minute per-process watchdog. A timeout
stops only the test process that the runner launched. The game windows open
normally; avoid interacting with them while the driver is active. Isolated
profiles and reports are retained locally for debugging, never committed or
shipped in the mod ZIP.

This covers the specified fresh-game opening at centered UI layout and normal
speed, with native animations enabled and audio muted. It does not cover OS
mouse hardware delivery, other UI layouts, every script or later-game behavior.
It complements, rather than replaces, the headless controls regressions.

## Product language and compatibility

Name: **Mouse Adventure**.
Tagline: **Hold to move. Point to steer. Click to interact.**

Point-to-steer means holding the left button and choosing a direction relative
to the character. It is not a destination tile, pathfinding, auto-approach, or
real-time combat. Diagonals alternate native cardinal steps. Nearby object
clicks turn in place through native input, then send A once.

Keep the `click_to_move` ID and existing option keys stable. Do not rename the
repository, installed folder, or saved options merely to update the wording.
Version bumps, release assets and mod-index submissions are explicit release
steps, not side effects of building or installing.
