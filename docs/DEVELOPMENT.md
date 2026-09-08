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

`tests\run.js` and `tests\controls.lua` are the existing development harness,
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
