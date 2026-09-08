# Mouse Adventure

**Hold to move. Point to steer. Click to interact.**

Play Pokemon Red, Blue and Yellow with mouse-first controls for
[Gen1Recomp](https://github.com/bryanthaboi/gen1recomp). Explore with held
steering, click nearby characters and objects, and navigate dialogue, menus
and battles with the mouse. Battles, progression, collision and saving keep
their normal game rules.

Maintained by [javi5cript](https://github.com/javi5cript).

![Mouse Adventure's live overworld steering arrow while holding left-click, with the action dock below](docs/screenshots/held-steering.png)

*v1.3.0 direction guide and action dock; v1.4.0 has a revised dock layout.
Captured in a modded game; additional world content is not included with Mouse Adventure.*

## Installation

Download Mouse Adventure **v1.4.0 (public beta)**:
`click_to_move-1.4.0.zip` from the
[releases page](https://github.com/javi5cript/gen1recomp-mouse-adventure/releases).

Requires **Gen1Recomp 0.2.56 or later in the pre-2.0 series** and your own
legally obtained Red, Blue or Yellow game data. This is a single-player mod,
not a standalone game.

> Public beta: clean-game coverage across Red, Blue and Yellow is not yet
> complete. Experimental controls are opt-in; replacement UI compatibility
> depends on the installed layout.

1. Save your progress and close the game.
2. In the launcher, open **MODS -> Import mod .zip** and select
   `click_to_move-1.4.0.zip`.
3. Enable **Mouse Adventure** for Red, Blue or Yellow, then start the game.

Download the release asset, not GitHub's automatic **Source code (zip)**.

**Manual install (alternative):**

1. Close the game and back up any existing `mods\click_to_move` folder.
2. Create `click_to_move` inside the engine's user-data `mods` directory.
   On Windows this is `%APPDATA%\pokemon-love2d\mods\click_to_move`.
3. Copy `manifest.json`, `main.lua`, `mouse_ui.lua`, `mouse_targets.lua`,
   `README.md`, `LICENSE`, and `THIRD_PARTY_NOTICES.md` into that folder.
4. Start Red, Blue, or Yellow and enable **Mouse Adventure** in the mod manager.

To uninstall, close the game and remove only `mods\click_to_move`, or disable
Mouse Adventure in the mod manager. Leave saves, carts, and other mods alone.

## Mouse controls

| Input | Action |
| --- | --- |
| Hold left mouse button | Move in the direction of the cursor |
| Move the cursor while holding | Steer in eight directions |
| Release | Stop after the current tile step |
| Point at the player while holding | Pause inside the dead zone |
| Click a nearby character or object | Face it and interact once |
| Click a menu row or battle choice | Select and confirm |
| Click during a waiting dialogue prompt | Advance text |
| Hover a supported choice | Highlight its clickable area |
| Mouse wheel | Scroll a supported list or change supported Pokedex tabs without confirming |
| Right-click | Go back in menus, or cancel held steering |
| G in the overworld | Hide or show the steering guide |

**Hold to move, point to steer** -- not click-to-destination. Keep holding to
keep moving; the mod does not find a route or approach distant targets for you.
Diagonal movement alternates horizontal and vertical tile steps.

Stand still directly beside an NPC, item ball, sign or solid object before
clicking it. Clerks and nurses can also be reached across a single counter.
For other field actions, face the target and use **INTERACT / A** or the party menu.

Click directly on your following Pokemon to talk.
Pointing past it starts normal held steering instead, including in tilt and
voxel orbit. The game's collision rules still apply.

Click the intro/title to continue when ready. To load a save, click the
main-menu row and then the Continue information box. Dialogue, battle messages,
level-up stats and post-catch Pokedex pages accept clicks when ready;
animations, sounds and scripted waits still apply.

The guide toggle lasts for the current session. Use **STEERING GUIDE** in the
mod settings to choose its startup state. You can also
choose H or J and click **GUIDE** in the dock footer. The key only works in the
overworld and yields to custom Game Boy key bindings.

Keyboard/controller input takes priority. Touch steering also works outside
the engine's virtual controls. Opening a menu or entering battle ends a hold;
press again afterward. Door transitions and scripts pause movement. Release
or lose window focus to cancel it.

### Optional precision and input controls

**TILT/VOXEL CLICK VS HOLD** separates directional interaction from steering.
Near an adjacent target, make a short click to interact, or keep holding
(about 0.18 seconds) or drag to start moving instead. Flat-view controls are
unchanged.

**WHEEL NAVIGATION** is on by default and moves the selection through supported
menu, bag and Pokedex lists while the cursor is inside the game view. Enable
it in mod settings if you previously switched it off. Scrolling never
confirms or activates an item. Overworld wheel zoom is unchanged. Battle
choices, naming, PC and party screens still use clicks or dock arrows.
On supported Modern Pokedex and Gen1Dex entries, the wheel scrolls notes or
moves when available; otherwise it changes entry tabs.

**EARLY DIALOGUE CLICK** retains one click for up to 0.35 seconds while a
visible dialogue/battle prompt or post-catch Pokedex cry finishes waiting.
It does not skip typing, attack animations or confirmation choices. A buffered
click expires rather than carrying into another page or screen; the dock
shows its status.

**FOUR-DIRECTION STEERING** chooses only the dominant cardinal direction.
**DEAD ZONE / DIRECTION** displays the pause radius and current direction while
holding; **HIGH-CONTRAST GUIDE** and **GUIDE THICKNESS** improve line visibility.

## Action dock

A separate strip below the game contains every Game Boy button. It reserves
window space rather than covering dialogue, menus, or the battle HUD.
The dock offers COMPACT, COMFORTABLE and LARGE sizes, stable button
positions, and MORE pages for small windows. Its footer shows control hints,
waiting messages and clickable guide status.
Text uses dedicated, DPI-aware fonts: 16-pixel compact labels, 18-pixel
comfortable labels, 20-pixel large labels and a 16-pixel footer. It is not
shrunk from the game's font.

| Control | Purpose |
| --- | --- |
| INTERACT / A or CONFIRM / A | Talk, confirm, advance text, select the current item |
| BACK / B | Cancel, close a menu, return to the previous screen |
| MENU | Open the native Start menu: Party, Bag, Pokedex, Save, Options |
| SELECT | Native secondary action, including swapping moves where supported |
| UP / DOWN / LEFT / RIGHT | Hold to navigate or walk/face using native D-pad input |
| MODS | Open or close the engine's mod manager (the normal F10 action) |
| HELP | Show a short control reference in the dock |
| GUIDE ON/OFF | Toggle the steering guide without issuing game input |
| MORE | Show the next dock page when the window cannot fit every control |

On the native naming grid the controls read TYPE, DELETE, DONE and CASE.
Click letters directly, or use the arrows and TYPE. Preset names remain native
menu choices.

If a screen does not respond to direct clicks, use the dock's arrows and
**CONFIRM / A**. To save, choose **MENU -> SAVE** and answer the game's
confirmation.

### Overworld Pokemon

With Wilds of Kanto's overworld catching enabled:

- **HOLD: THROW** charges a throw; release inside the dock to throw.
- **NEXT BALL** cycles the selected ball.

Stop walking before charging. Right-click, focus loss, leaving the dock, or
opening another screen cancels the charge. Enable a throw-button combo in
Wilds' settings if the dock asks for one. The dock keeps these
buttons in place but disabled when catching is unavailable.

## Supported screens

| Screen | Direct-click coverage |
| --- | --- |
| Overworld | Adjacent NPCs, item balls, signs and solid scenery; NPCs across one counter |
| Startup | Intro/title screens, main-menu rows and Continue info box |
| Native menus and confirmations | Visible rows, YES/NO, scrolled lists |
| Dialogue | Ready text pages, including battle messages |
| Native battles | Command and move choices, Safari and Mimic, level-up stats, classic and wide layouts |
| Party | Native rows and recognized Modern Party cards/submenus; native and Gen1Party SWITCH / STATS / CANCEL popups |
| Pokemon stats | Click native summary pages to advance/return; recognized Modern Party summaries also support move cards and details |
| PC | Recognized Modern PC slots, actions and box picker |
| Pokedex | Native and recognized Modern Pokedex lists; post-catch data pages; DATA / CRY / AREA menus and recognized Gen1Dex lists/entries |
| Area map | Native map dismissal; recognized Gen1Dex hints/location controls and right-click to return |
| Trainer/badges | Click to close the native trainer card; badges remain display-only |
| Naming | Native letter grid and recognized modern naming controls |
| Bag | Native list rows and recognized Modern Bag rows |
| Other replacement screens | Use their own mouse controls or the dock |

Direct clicks on Gen1BattleUI grids work only without Kanto Gear loaded.
With Kanto Gear, use its companion controls or the dock.
Operating-system file dialogs and arbitrary mod text/search fields are not
guaranteed to be keyboard-free.

## Options

Open this mod's settings in the mod manager.
Wheel navigation defaults to ON; the optional steering and
early-click behaviors default to OFF.

| Option | Default | Purpose |
| --- | --- | --- |
| HOLD TO MOVE | ON | Enables held steering |
| STEERING GUIDE | ON | Draws a line and arrow toward the cursor |
| DEAD ZONE | 6 | Pause radius around the player, in world pixels (2-16) |
| MOUSE MENUS AND DIALOGUE | ON | Enables UI clicks, contextual B and the dock |
| MOUSE ACTION BAR | ON | Reserves space for visible controller and Wilds controls |
| GUIDE HOTKEY | ON | Enables the configured guide key in the overworld |
| GUIDE KEY | G | Choose G, H or J; native Game Boy bindings retain priority |
| DOCK SIZE | COMPACT | Compact, comfortable or large buttons and text |
| WHEEL NAVIGATION | ON | Scroll through supported lists without confirming |
| EARLY DIALOGUE CLICK | OFF | Remember one early click briefly while a visible prompt waits |
| TILT/VOXEL CLICK VS HOLD | OFF | Release to interact; hold or drag to steer |
| PROJECTED PLAYER ANCHOR | OFF | Steer relative to the rendered player in tilt/voxel views (experimental) |
| FOUR-DIRECTION STEERING | OFF | Dominant cardinal direction instead of alternating diagonals |
| DEAD ZONE / DIRECTION | OFF | Show pause radius and current direction during a hold |
| HIGH-CONTRAST GUIDE | OFF | Add a black outline beneath the steering arrow |
| GUIDE THICKNESS | 1 | Steering line width, 1-4 window units |

## Camera support and limitations

Held steering and click-to-interact work in three overworld cameras:

- the flat 2D view (default),
- the engine's **TILT** view, and
- the **voxel** mod's orbit/diorama levels 1-5.

In tilt and voxel orbit, steer relative to the centre of the view by default.
The optional PROJECTED PLAYER ANCHOR follows the rendered player instead,
which can help near map edges.

Known limitations:

- **Free-look voxel cameras are unsupported.** Use the voxel mod's own
  controls in first-person (level 6) and third-person free-cam (level 7).
- **Tilt and voxel-orbit interaction is directional.** Clicking an adjacent NPC,
  sign, or object resolves the click to one of the four cardinal neighbours and
  faces that way. Following Pokemon are an exception:
  only a sprite-sized area triggers interaction. If its projected position is
  unavailable, use **INTERACT / A** rather than clicking the surrounding world.
- **Projected anchoring is optional and experimental.** If the player's screen
  position is unavailable, steering falls back to the centre and the dock
  identifies it as approximate. Camera and visual-effect mods may affect accuracy.
- **Replacement UIs are not guaranteed clickable.** Third-party battle and menu
  UIs that redraw their own screens may not expose click targets.
- **Gen1Arena backdrops can cover voxel battles.** If an illustrated 2D scene
  overlaps the voxel view, turn off **Gen1Arena -> BACKDROPS**. If it persists,
  disable Gen1Arena, save and restart. Mouse Adventure does not resolve
  conflicts between battle renderers.

## Help and feedback

Report problems on the [issue tracker](https://github.com/javi5cript/gen1recomp-mouse-adventure/issues).
Include your game, Gen1Recomp and Mouse Adventure versions, active mods,
camera mode, and steps to reproduce. A screenshot helps with click-target
or layout problems.

For release changes, see the [changelog](CHANGELOG.md).
For building or contributing, see the [development guide](docs/DEVELOPMENT.md).

## Credits and license

Gen1Recomp is developed by bryanthaboi and contributors. Compatibility work
references the modern UI projects maintained by piftee, Gen1WildUI and
Gen1BattleUI by wild1walker, Wilds of Kanto by YoDrehDenSwagAuf, and Kanto Gear
by AverageConsumer. These are separate projects with their own licenses;
they are not bundled or required for the basic mouse controls.

Mod code is licensed under [MIT](LICENSE). See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for acknowledgments and notices.
No ROMs, game assets or third-party mods are included.
Pokemon and related names belong to their respective owners. This is an
unofficial fan project, not affiliated with Nintendo, Creatures, or Game Freak.
The MIT license grants no rights to their games, artwork or trademarks.
