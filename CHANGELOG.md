# Changelog

All notable changes to Mouse Adventure (`click_to_move`) are recorded here.
This project follows the pre-2.0 Gen1Recomp mod conventions.

## 1.4.0 - public beta - 2026-09-08

### Added

- Click controls for native Pokemon summaries, Pokedex DATA / CRY / AREA menus,
  area maps and trainer cards. Recognized Modern Party summaries, Modern
  Pokedex entries and Gen1Dex list/entry/area layouts use their own native
  input handlers; badge icons remain display-only.
- Wheel support for Pokedex entry notes/move lists and horizontal tabs, with
  fractional notches and cancellation when the displayed page changes.
- Configurable G/H/J guide key and clickable GUIDE status in the dock.
- Three readable dock sizes, stable Wilds control slots, small-window
  pagination, contextual click/wait hints and cycling HELP.
- Opt-in short-click versus held-steering separation in tilt/voxel views.
- Native-input wheel navigation for recognized menu, bag and Pokedex lists,
  enabled by default.
- Opt-in, bounded early-click buffering for exact visible dialogue/battle
  prompts and post-catch Pokedex cry waits.
- Opt-in native projected player anchoring, four-direction steering,
  dead-zone/direction feedback, high-contrast guide and adjustable line width.
- Regression coverage for opt-in behavior, native page/list input, input
  ownership, stale gestures, render projection, settings errors and dock sizes.

### Fixed

- UI frame observation initializes before the first render. Voxel follower
  targets and optional projected steering anchors account for supersampled
  antialiasing before applying display DPI.
- The action dock uses its own DPI-aware fonts at native size instead of
  shrinking the game's current font. Button text is now 16/18/20 pixels for
  compact/comfortable/large, with 16-pixel footer text and pixel-aligned drawing.
- Following Pokemon respond only to clicks in their sprite-sized area, not
  every click in their direction. Flat, tilt and voxel-orbit views account for
  follower visual size; missing or stale projected bounds never trigger talk.
- Menu and confirmation hitboxes/highlights use the UI transform actually
  rendered before the engine clears its world flags. This keeps zoomed-out
  dynamic menus and anchored save choices aligned, including high-DPI windows.
  Classic overlays also respect the wide battle's horizontal centering.
- Party context menus now accept clicks on SWITCH, STATS and CANCEL in the
  native and recognized Gen1Party layouts. Modern Party uses the same guarded
  action handling. Switching still obeys the game's active/fainted Pokemon
  restrictions; changed selections or physical input cancel queued clicks.
- Guide toggles explicitly report session-only state and settings write errors.
  Rebound native controls retain priority over the configured guide key.
- Separate wheel notches include neutral polls so native input sees distinct
  presses. Queued scrolling cancels when its list or input owner changes.
- Updated the opening smoke driver's dock coordinates for the stable layout.

### Known limitations

- Clean-game release coverage across Red, Blue and Yellow is not yet complete.
- Gen1Arena's 2D backdrops can overlap voxel battle scenes. Turn off its
  BACKDROPS option or disable Gen1Arena and restart after saving. This release
  does not patch third-party battle renderers.
- Projected anchoring and new input timing still need live Red/Blue/Yellow
  coverage, particularly at map edges, during camera transitions and with
  replacement UIs. Headless projection fixtures are not rendering proof.

## 1.3.0 - public beta

### Added

- Held steering and click-to-interact now work in the engine's **TILT** view and
  in the **voxel** mod's orbit/diorama levels 1-5, in addition to the flat
  overworld. All three cameras pitch down from the south without yaw, so the mod
  steers relative to the centre of the view.
- Regression tests covering tilt and voxel-orbit steering, directional NPC
  interaction, and the free-look rejection path.
- **G** hotkey to hide or show the steering line and arrow in the overworld,
  plus a GUIDE HOTKEY (G) option to disable it. The hotkey never fires while
  naming or in a menu.

### Changed

- Camera classification uses the first-party `Tilt` and `Pipelines` engine
  modules directly, with no dependency on the voxel mod.
- Under tilt and voxel-orbit, clicking an adjacent NPC, sign, or object resolves
  to the nearest cardinal neighbour and faces that way. Pixel-accurate sprite
  targeting is still used in the flat overworld.

### Fixed

- A click now advances the battle **level-up stat card** ("grew to level N!").
  The card is a separate state pushed over the battle, so clicks previously
  found no target; any click now sends A to dismiss it, as vanilla does.
- A click now advances and closes the **Pokedex data page** shown after catching
  a new species ("New POKeDEX data will be added..."). Each click pages through
  the entry and finally closes it. Input is still ignored while the caught mon's
  cry plays, exactly as with the keyboard.

### Known limitations

- Free-look voxel cameras (level 6 first-person, level 7 third-person free-cam)
  are unsupported: the mod stops steering and logs a warning instead of moving
  in the wrong direction.
- Centre-anchored steering assumes the player is roughly centred and can degrade
  at map edges where the camera stops following.
- Third-party replacement battle and menu UIs are not guaranteed clickable.

## 1.2.0 - public beta

- First public beta: mouse-first controls for Pokemon Red, Blue, and Yellow -
  hold-to-move point-to-steer overworld movement, clickable dialogue and menus,
  and an on-screen controller dock. Flat overworld only.
