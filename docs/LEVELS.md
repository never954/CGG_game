# Levels

Each level is a plain text file in `assets/levels/level_N.txt`. One character = one 1 × 1 metre tile.
Row 0 is the **top** of the level. The `LevelBuilder` script (`scripts/world/level_builder.gd`) turns it into
3D geometry, collision, water, enemies and items when the level starts.

## Legend

| Char | Meaning | Char | Meaning |
|---|---|---|---|
| `#` | ground / rock (solid) | `P` | hunter start |
| `=` | wooden one-way platform | `N` | Old Koax (talk with E) |
| `~` | deep water (costs a heart) | `S` | shrine = checkpoint + save |
| `.` | air | `X` | level exit (needs the memory eye) |
| `h` | hopper frog | `o` | spirit orb |
| `B` | brute frog | `p` | peach (+2 health) |
| `c` | cultist | `k` | key |
| `b` | the Toad King (boss) | `e` | memory eye |
| `D` | locked gate (uses a key) | `C` | crate (physics) |
| `^` | thorns | `r` | reeds (decoration) |

Lines starting with `;` are comments. Lines starting with `@` are settings:

```
@name Reedwake        shown on the title card
@theme reeds          reeds | grove | hollow | temple | throne  (sky, light, fog, textures, music)
```

## Rules that keep a level playable

The hunter is about 1.8 tiles tall and 0.7 tiles wide.

- **Jump height**: about 3.5 tiles. A ledge 3 tiles up is reachable; 4 needs a crate or a wall-jump.
- **Jump distance**: gaps of up to 4 tiles at the same height; 3 tiles if you also climb 2–3.
- **Corridors** need at least 2 free tiles of height.
- **Wall-jump shafts** work best 2 tiles wide (wall on both sides).
- **Gates**: put the `D` in a corridor exactly 3 tiles tall with solid rock above it, or the player will just jump over.
- **Water**: draw `~` down to one row above the bottom and keep a `#` floor under it.
- Entities stand on the tile **below** their character, so put them in the air row just above the ground.
- Shrines are numbered left to right automatically (that number is what the save file stores).

## Previewing in the editor

Open `scenes/world/level_preview.tscn`, select the **Level** node, and change **Level Index** in the Inspector.
The level rebuilds instantly in the 3D viewport, because the builder is a `@tool` script.

## Story per level

Level names, subtitles, hints (shown when the hunter passes an x position) and every conversation live in
`assets/dialogue/story.json`. The keys are `level_N_intro`, `level_N_hermit`, `level_N_memory`, `hints.N`.
