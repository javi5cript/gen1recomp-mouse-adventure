# Mouse Adventure development

- This Git repository is the source of truth for
  `javi5cript/gen1recomp-mouse-adventure`. Never edit the installed mod as the
  primary source, and never commit the surrounding Gen1Recomp installation.
- Read `docs\DEVELOPMENT.md` for the Windows workflow. Local paths belong in
  ignored `.dev.local.json`, not tracked scripts or documentation.
- Validate with `.\scripts\dev.ps1 -Task Test`. Use `npm ci` only for missing
  dependencies or dependency changes; retain the locked dependency versions.
- After reviewing and committing requested changes, use
  `.\scripts\dev.ps1 -Task Install` to deploy the tested, root-level ZIP. Build
  does not compile or change the engine. Do not bypass the running-game guard;
  get approval before a restart that could discard unsaved progress.
- Commit and push when requested. Do not automatically commit unrelated edits
  or publish releases, tags or catalog entries.
- Preserve native, source-owned input. No direct player position/facing,
  collision, inventory, save or battle-decision mutations. Guard queued actions
  against state/target changes and yield to physical controls.
- Add regression scenarios to `tests\controls.lua` when behavior changes;
  preserve existing scenarios. Headless fixtures do not replace live coverage.
- Keep the name Mouse Adventure and the compatibility ID `click_to_move`.
  Describe movement as "hold to move, point to steer", not click-to-destination
  or pathfinding. Clicking nearby objects is a separate interaction.
- Keep ROMs, imported assets, saves, installed mods, engine source, local
  configuration, caches, dependencies and build artifacts out of Git.
