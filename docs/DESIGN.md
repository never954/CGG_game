# Design notes

## The look: HD-2D in Godot 3D

The world is real 3D, but every character, tree and item is a flat pixel-art sprite (`Sprite3D` /
`AnimatedSprite3D`) standing in it, like cardboard cut-outs in a diorama. That gives
"Octopath / BREKEKEKEX"-style depth with pixel art:

| Effect | How |
|---|---|
| Sprites that sit on one pixel grid | every sprite uses `pixel_size = 0.03` m and nearest filtering (`Props.style`) |
| Sprites lit and shadowed by the scene | `shaded = true`, `cast_shadow = on`, `alpha_cut = discard` |
| Sun and shadows | `DirectionalLight3D` with shadows, colour/angle per theme |
| Lantern glow in the mist | `OmniLight3D` per lantern + `light_volumetric_fog_energy` + volumetric fog |
| Water reflections | custom spatial shader (`scripts/world/water.gdshader`): opaque, very smooth, rippled normals → screen-space reflections (SSR) mirror the world |
| Depth / gradients | fog with aerial perspective, distant hill and mountain ridges, vertex-colour shading that darkens cliffs with depth |
| Soft contact shadows | SSAO |
| Glow | HDR colours above 1.0 + glow (bloom) |
| Miniature feel | depth of field: the lane is sharp, the far bank and near reeds blur |
| Colour grade | filmic tonemapping + contrast/saturation adjustment |

All of that is set up per theme in `scripts/world/themes.gd` and built by `LevelBuilder._build_atmosphere()`.

## Architecture

```
title.tscn ──New Game / Continue──▶ game.tscn
                                     ├── Level      (LevelBuilder: map → meshes, collision, water, entities, decor)
                                     ├── CameraRig  (dynamic camera + fireflies)
                                     ├── Hud        (CanvasLayer)
                                     ├── Dialogue   (CanvasLayer)
                                     ├── Menus      (CanvasLayer: pause / game over / level complete / ending)
                                     └── Player     (added by game.gd at the start or last shrine)
Autoloads (always alive): Controls (input map) · GameState (progress + save file + hit-stop) · Audio
```

Nodes talk through **groups** instead of hard references, so scenes stay independent:
`player`, `enemy`, `camera` (add_trauma, snap), `hud` (show_hint, show_title, show_boss),
`dialogue` (play), `game` (talk, memory_found, level_complete, boss_defeated).

## Player feel

- Acceleration/deceleration instead of instant speed; air control is lower.
- **Coyote time** (0.1 s): you can still jump just after leaving a ledge.
- **Jump buffer** (0.13 s): pressing jump just before landing still jumps.
- **Variable jump**: releasing Space early cuts the rise (`jump_cut`).
- **Heavier fall** (`fall_multiplier`) for a snappy arc.
- **Wall slide / wall jump** with a short input lock so the push-off is not cancelled.
- **One-way platforms**: platform collision layer 3 is only in the player's mask while falling;
  Down + Jump disables it for 0.3 s to drop through.

## Combat, enemies and camera

These sections grew large. They are now fully explained in **[HOW_IT_WORKS.md](HOW_IT_WORKS.md)**:
§9 combat (launcher, juggles, dive, parry, perfect dodge, spirit, Moon Breaker, powers),
§10 enemy AI (tells, feints, evasion, attack slots, boss phase 2),
§11 camera (spring follow, arena framing, event cameras, shake, DOF), §12 game feel (hit-stop, impact frames).

## Saving

`GameState.save_game()` writes `user://save.cfg` (a ConfigFile) with the level, the last shrine index, orbs,
memories and falls. It saves when a shrine is lit, a memory is found, a level starts and when you die.
**Continue** on the title screen loads it and starts at that shrine.
On a Mac the file is in `~/Library/Application Support/Godot/app_userdata/BREKEKEKEX - The Hunter Who Forgot/`.

## Collision layers

| Layer | Name | Used by |
|---|---|---|
| 1 | world | terrain, gates |
| 2 | player | the hunter |
| 3 | platform | one-way wood |
| 4 | enemy | frogs, cultists, boss |
| 5 | pickup | orbs, keys, eyes |
| 6 | crate | rigid-body crates |
| 7 | hazard | thorns, water |
