# Changelog

All notable changes to Mouse Adventure (`click_to_move`) are recorded here.
This project follows the pre-2.0 Gen1Recomp mod conventions.

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
