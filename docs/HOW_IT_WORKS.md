# How BREKEKEKEX was built: every system, explained

This document explains **how every part of the game works and how it is implemented in Godot**,
from how a single pixel of a sprite is drawn to how the camera swings during a fight. Each section
has three parts:

- **What it is**: the idea in plain words.
- **How it is done**: the engine features, the file, and the important code or maths.
- **If the teacher asks**: a short answer you can say out loud.

> File paths are relative to the `game_play/` folder. `res://` in Godot means the same folder.

---

## Contents

1. [The big picture: what happens when you press Play](#1-the-big-picture)
2. [Godot basics used everywhere](#2-godot-basics-used-everywhere)
3. [How the sprites are made (the C++ art generator)](#3-how-the-sprites-are-made)
4. [How the sprites get into Godot and animate](#4-how-sprites-get-into-godot-and-animate)
5. [How the sounds and music are made](#5-how-the-sounds-and-music-are-made)
6. [How a level is built from a text file](#6-how-a-level-is-built-from-a-text-file)
7. [How the HD-2D look is rendered](#7-how-the-hd-2d-look-is-rendered)
8. [The hunter: movement](#8-the-hunter-movement)
9. [The hunter: combat, parry, perfect dodge, powers](#9-the-hunter-combat)
10. [The enemies: how they think](#10-the-enemies)
11. [The camera: the BREKEKEKEX feel](#11-the-camera)
12. [Game feel: hit-stop, impact frames, shake, particles](#12-game-feel)
13. [World objects: pickups, gates, shrines, crates, water, NPC](#13-world-objects)
14. [UI: HUD, dialogue, menus, title screen](#14-ui)
15. [Saving and loading](#15-saving-and-loading)
16. [Physics layers and collisions](#16-physics-layers-and-collisions)
17. [Testing](#17-testing)
18. [Viva question bank](#18-viva-question-bank)
19. [File index](#19-file-index)

---

## 1. The big picture

**What happens, step by step, when you press Play (F5):**

```
1. Godot reads project.godot
       main scene = res://scenes/ui/title.tscn, window 1280x720, Vulkan renderer
2. Autoloads are created (they live for the whole game):
       Controls  → registers every input action (keys + gamepad)
       GameState → progress, health, save file, hit-stop
       Audio     → sound-effect players + music player
3. title.tscn loads → builds level 1 behind the menu, camera drifts along it
4. "New Game" / "Continue" / "Chapters" → change_scene_to_file("res://scenes/world/game.tscn")
5. game.gd _ready():
       LevelBuilder.build()  → reads assets/levels/level_N.txt → meshes, collision, water,
                               enemies, items, trees, lights, sky
       creates the Player at the start or at the last shrine
       CameraRig.set_target(player)
       plays the music, shows the title card, starts the intro dialogue
6. Every frame:  _process(delta)          → camera, HUD, animations of props
   60×/second:   _physics_process(delta)  → player, enemies, projectiles, crates move & collide
7. Events: shrine lit → save | memory eye → story + new power | exit → next level
           boss defeated → final memory → ending → sequel tease
```

**If the teacher asks "how is the game structured?"**
"It is scene-based. The title screen and the game are two scenes. The game scene contains the
level builder, a camera rig, the HUD, the dialogue box, menus and an impact-frame layer. The player
and every enemy are separate reusable scenes, and global state lives in three autoload singletons."

---

## 2. Godot basics used everywhere

| Concept | What it means | Where we use it |
|---|---|---|
| **Node** | One building block with one job (a light, a sprite, a collision shape, a script…) | everything |
| **Scene** (`.tscn`) | A saved tree of nodes that can be reused (instanced) | `player.tscn`, `hopper.tscn`, `shrine.tscn`… |
| **Script** (`.gd`) | GDScript attached to a node, adds behaviour | `scripts/` |
| **`class_name`** | Gives a script a global type name | `Player`, `Enemy`, `HitFx`, `Props`… |
| **Inheritance** | `extends` another class | `Hopper extends Enemy`, `ToadKing extends Brute` |
| **`@export`** | Variable shown in the Inspector, editable without code | speeds, HP, damage… |
| **`@onready`** | Variable assigned when the node enters the scene | `@onready var sprite = $Sprite` |
| **`@tool`** | Script also runs inside the editor | LevelBuilder, SheetSprite, world objects |
| **`_ready()`** | Called once when the node is in the scene | setup |
| **`_process(delta)`** | Called every rendered frame | camera, HUD |
| **`_physics_process(delta)`** | Called at a fixed 60 Hz | movement, collisions, AI |
| **`delta`** | Seconds since the last call; multiply speeds by it | everywhere |
| **Signal** | An event a node emits; others connect to it | `player.died`, `body_entered` |
| **Group** | A tag on nodes; find or call all of them | `"enemy"`, `"camera"`, `"hud"`, `"game"` |
| **Autoload** | A node created at startup that never goes away (singleton) | `GameState`, `Audio`, `Controls` |
| **Resource** | Data object (texture, mesh, material, shape, SpriteFrames) | everywhere |
| **Tween** | Animates a property over time in code | fades, gate opening, popups |

**Groups are how systems talk.** Instead of hard references, code says
`get_tree().call_group("camera", "add_trauma", 0.3)`, and whatever is in the group "camera" gets the call.
That keeps scenes independent: the player doesn't need to know where the camera is.

---

## 3. How the sprites are made

Every character, prop and texture is **drawn by our own C++ program**, `tools/assetgen.cpp`.
It uses the same computer-graphics algorithms as the course assignments. Nothing is downloaded or
hand-painted.

```
c++ -O2 -std=c++17 tools/assetgen.cpp -o tools/assetgen && ./tools/assetgen
```

### 3.1 The canvas
`struct Canvas` is an array of RGBA bytes (`w × h × 4`). `set(x, y, colour)` writes a pixel;
`blend(x, y, colour, alpha)` mixes a semi-transparent colour over it (used for motion smears).

### 3.2 Shapes are polygons
Every body part is a polygon (a list of points):
- `P_rect(x0,y0,x1,y1)` gives a rectangle
- `P_ell(cx,cy,rx,ry)` gives an ellipse approximated by 14 points
- `P_seg(a, b, width)` gives a thick line as a quad (the staff, limbs)
- `P({x,y, x,y, …})` gives any custom shape (coat, hat brim, frog body)

### 3.3 Transformations: 2D affine matrices
`struct A2` is a 2D affine matrix

```
| a  c  tx |      x' = a·x + c·y + tx
| b  d  ty |      y' = b·x + d·y + ty
```

with constructors `T(x,y)` (translate), `R(θ)` (rotate counter-clockwise), `S(sx,sy)` (scale),
and `*` for **composition**. Matrices apply right-to-left, so `T * R * S` means
"scale, then rotate, then move". This is the composite transformation from the transformation
assignment, used to build a **skeleton**:

```cpp
A2 base = A2::T(0, ps.bob) * A2::T(0, 22) * A2::R(ps.rot) * A2::T(0, -22) * A2::S(ps.sqx, ps.sqy);
A2 body = base * A2::T(0, 21) * A2::R(-ps.lean) * A2::T(0, -21);   // lean around the hips
A2 upperArm = body * A2::T(shoulder.x, shoulder.y) * A2::R(angle);   // arm hangs off the body
A2 forearm  = upperArm * A2::T(0, -6) * A2::R(elbow);                // forearm hangs off the arm
```

`T(0,21) * R * T(0,-21)` is **rotation about a pivot**: move the pivot to the origin, rotate, move back.
Because each part multiplies its parent's matrix, moving the body moves the arms, the staff and the head
with it. That is a **hierarchical model**.

### 3.4 Filling: the scan-line algorithm
`scan_fill(polygon, …)` fills any polygon, convex or concave:

1. Find the polygon's lowest and highest y.
2. For every scan line `y`, sample at the pixel centre `y + 0.5`.
3. Intersect that horizontal line with every edge, using the half-open rule `p.y <= yc < q.y` so
   vertices aren't counted twice: `x = p.x + (yc − p.y)·(q.x − p.x)/(q.y − p.y)`.
4. Sort the intersection x values and fill between pairs (1st–2nd, 3rd–4th…). This is the
   **even-odd rule**, which handles concave shapes and holes.

### 3.5 The pixel-art outline
`draw_cell()` draws the whole figure **five times**:
1. Four times in a dark outline colour, shifted 1 px left, right, up and down.
2. Once more in the real colours on top.

What remains of the dark copies is a clean **1-pixel silhouette outline**, the classic pixel-art look.

### 3.6 Posing: skeleton + inverse kinematics
A `Pose` struct holds the angles of a frame: lean, bob, leg/knee angles, staff centre and angle,
hand grip positions, hat tilt, scarf wave, and the motion smear.

The **hands must stay on the staff** wherever it is, so the arms use **two-bone IK** (`ik2`):
given the shoulder and the target hand position, the **law of cosines** gives the shoulder angle:

```
cos α = (l1² + d² − l2²) / (2·l1·d)        d = distance shoulder → hand
shoulder angle = direction to hand ± α     elbow angle = what's left to reach the hand
```

So the animator only says "the staff is here, the hands grip it there", and the arms follow automatically.

### 3.7 Anime motion smears
Fast swings draw a **crescent** (`smear_arc`) behind the staff: an outer arc and an inner arc whose
radius shrinks with `sin(πt)`, so it is thick in the middle and pointed at the ends, drawn semi-transparent.
That's the "anime smear frame" look. The parry smear is blue and the special is gold.

### 3.8 Animations = rows of a sprite sheet
Each animation is a list of `Pose`s (frames). `build_hunter()` lays them out as **one row per animation,
one column per frame** in a single PNG (cell 128 × 100 px) and writes a JSON file describing it:

```json
{ "cell": [128, 100], "foot": [64, 86],
  "animations": [ {"name": "idle", "row": 0, "frames": 4, "fps": 5.0, "loop": true}, ... ] }
```

The hunter has 18 animations: idle, run, jump, fall, attack1, attack2, heavy, air, dodge, block,
hurt, death, **launch, dive, airdash, vault, parry, special**. Enemies are built the same way with their own
pose structs (`BPose` brute, `KPose` cultist, hopper squash/stretch).

### 3.9 Textures: noise + dithering
Ground textures (grass, marsh, mud, cliff, planks, stone, cave) are 64×64 and **tile seamlessly**:
- **Periodic value noise** (`pnoise`): random values on a grid that wraps around (`% P`), blended
  with smoothstep. Three octaves are added (big, medium and small detail).
- **Bayer ordered dithering** (`tone4`): the noise value plus a 4×4 Bayer matrix threshold chooses one of
  **4 colour tones**. That gives the crunchy pixel-art texture instead of a smooth gradient.

### 3.10 Writing PNG files by hand
`write_png` writes a valid PNG without any library: the signature, an `IHDR` chunk (size, RGBA 8-bit),
an `IDAT` chunk holding **uncompressed "stored" deflate blocks** plus an Adler-32 checksum, and `IEND`.
Every chunk has a CRC-32.

**If the teacher asks "how did you make the sprites?"**
"With a C++ rasterizer I wrote: each body part is a polygon placed by composite affine matrices in a
skeleton hierarchy, filled with the scan-line algorithm, outlined by drawing it offset in four directions,
and the arms use two-bone IK so the hands stay on the staff. Each frame is a pose; the frames are packed into
a sprite sheet PNG with a JSON file that tells Godot the rows, frame counts and frame rates."

---

## 4. How sprites get into Godot and animate

### 4.1 Import
Godot imports every PNG automatically (the `.import` files). `project.godot` sets the texture importer
to lossless with mipmaps, and the sprites are drawn with **nearest-neighbour filtering** so pixels stay crisp.

### 4.2 `SheetSprite` (scripts/actors/sheet_sprite.gd)
An `AnimatedSprite3D` (a sprite that lives in 3D and plays animations). In `build()` it:
1. reads the JSON,
2. creates a `SpriteFrames` resource,
3. for each animation adds one **`AtlasTexture`** per frame whose `region` is that frame's rectangle:
   `Rect2(frame * cell.x, row * cell.y, cell.x, cell.y)`, which cuts the frame out of the big sheet,
4. sets the fps and looping from the JSON.

Playing an animation is then just `sprite.play("run")`. Gameplay also reads `sprite.frame` so damage only
happens on the **active frames** of an attack.

### 4.3 Size and feet
All sprites use `pixel_size = 0.03` (1 sprite pixel = 3 cm), so everything shares one pixel grid.
The hunter is 61 px tall, which is **1.83 m**. A sprite is drawn centred on its node, but we want the
**feet** at the node's origin (so the character stands on the ground), so the sprite is shifted up:

```
position.y = (foot.y − cell.y / 2) × pixel_size = (86 − 50) × 0.03 = 1.08 m
```

Turning around is `sprite.flip_h = facing < 0`. The sheets keep the feet horizontally centred so flipping
never makes the character jump sideways.

### 4.4 Sprites in a 3D world
`Props.style()` sets every sprite to be `shaded` (lit by the sun and lanterns), `double_sided`, with
`alpha_cut = DISCARD` (transparent pixels are cut out, so sprites **cast proper shadows** and sort correctly)
and `cast_shadow = ON`.

**If the teacher asks "how is animation done in the engine?"**
"With AnimatedSprite3D and a SpriteFrames resource. My SheetSprite script builds the SpriteFrames from the
sprite sheet: every frame is an AtlasTexture region of the sheet, with the frame rate and looping from the
JSON. The player's state machine calls play() with the right animation and checks the current frame to
know when an attack is active."

---

## 5. How the sounds and music are made

`tools/audiogen.py` **synthesises** all 27 effects and 4 music tracks with numpy (22 050 Hz WAV):

| Building block | Technique | Used for |
|---|---|---|
| `sweep(f0, f1)` | oscillator whose frequency glides (geometric) | jumps, swings |
| `noise` + `lowpass` / `bandpass_sweep` | filtered white noise, one-pole filters | whooshes, splashes, hits |
| `pluck` | **Karplus–Strong** string: a noise burst in a delay line, averaged each pass | music melodies |
| `bell` | sum of inharmonic sine partials (1, 2.76, 5.4, 8.93×) | shrines, memories |
| `croak` | low pulse train with rough amplitude modulation | frogs |
| `reverb` | several feedback delay lines (comb filters) | music space |
| `env` | attack/release envelope | shaping every sound |

Music = a drone + a plucked melody on a scale + soft drums + a **frog chorus** rhythm
("brekekekex koax koax"), cross-faded at the loop point (`fade_loop`).

**In the game**, `Audio` (autoload, scripts/autoload/audio.gd):
- keeps a **pool of 14 `AudioStreamPlayer`s** used round-robin, so many sounds can overlap;
- adds ±8% random pitch to each effect so repeats don't sound robotic;
- plays music on its own player, **cross-fading** with a Tween when the track changes, and loops it.

Usage anywhere: `Audio.sfx("heavy_hit")`, `Audio.music("music_boss")`.

---

## 6. How a level is built from a text file

### 6.1 The map
`assets/levels/level_1.txt` is plain text. **One character = one 1 × 1 m tile; row 0 is the top.**
`#` ground, `=` wooden platform, `~` water, letters are objects (`h` hopper, `S` shrine, `k` key…;
see `docs/LEVELS.md`). `@theme reeds` picks the look.

`LevelData` (scripts/world/level_data.gd) parses it. Because rows count down but 3D y counts up,
it converts with:

```
row_bottom(row) = height − 1 − row        (world y of the bottom of that row)
```

### 6.2 `LevelBuilder` (scripts/world/level_builder.gd), step by step
It's a `@tool` script, so it also runs in the editor (open `scenes/world/level_preview.tscn`).

1. **Atmosphere**: creates `WorldEnvironment` (sky, fog, volumetric fog, SSAO, SSR, glow, tonemap,
   colour adjustment) and a `DirectionalLight3D` sun with shadows, using the colours of the theme
   (`themes.gd`).
2. **Terrain mesh**: walks every solid tile and adds quads with **`SurfaceTool`** (a mesh builder):
   - a **top face** only when the tile above is empty (grass texture),
   - a **front face**, plus left/right faces only where the neighbour is empty (rock texture),
   - a mossy "lip" hanging over front edges.
   - **UVs = world position / 1.92 m.** The textures are 64 px, and 64 px × 0.03 m = 1.92 m, so the
     ground has *exactly* the same pixel density as the sprites.
   - **Vertex colours darken faces with depth** below the surface (`shade = 1 − clamp(depth/7, 0, 0.62)`),
     which gives the gradient that makes cliffs look deep.
   - Terrain is also drawn 24 tiles past both ends of the map so the world never stops abruptly.
3. **Collision**: rather than one box per tile, a **greedy merge** grows each box right as far as possible,
   then down while the whole row below is solid. The result is a few big `BoxShape3D`s in one `StaticBody3D`.
   Invisible walls at both ends and a lid on top keep everything inside.
4. **Platforms** (`=`): plank meshes + thin boxes on **collision layer 3** (one-way, see §8.5).
5. **Water** (`~`): a plane with the water shader at the surface, plus an `Area3D` "Drown" zone below it.
6. **Backdrop**: the river bank behind the lane, mirror-like lakes in front and behind, and two ridges of
   hills and mountains (height = sums of sines), fading into the fog.
7. **Entities**: each letter is instanced from a scene (`SCENES` table) and placed at its tile.
   Shrines are sorted left to right and numbered (that number is what gets saved).
8. **Decoration**: trees, reeds, grass, flowers and lanterns (each lantern is a sprite plus an
   `OmniLight3D`). Placement uses a **hash function** (`_h(i, k)`) instead of `randf()`, so the decoration is
   random-looking but **identical every time** the level loads.

**If the teacher asks "how did you design levels in the engine?"**
"Levels are tile maps stored as text. A tool script, the LevelBuilder, turns the map into 3D meshes with
SurfaceTool, merges solid tiles into collision boxes, and instances the scenes for enemies, items and
checkpoints. Because it's a tool script, the level appears live in the editor too."

---

## 7. How the HD-2D look is rendered

HD-2D means **pixel-art sprites inside a real 3D world** with modern lighting (Octopath Traveler style).

| Effect | Engine feature | Setting / file |
|---|---|---|
| Lit, shadowed sprites | `Sprite3D` with `shaded`, `alpha_cut`, `cast_shadow` | props.gd |
| Sun + shadows | `DirectionalLight3D`, `shadow_enabled` | level_builder.gd |
| Lantern glow | `OmniLight3D` + `light_volumetric_fog_energy` | level_builder.gd |
| Mist with light shafts | **volumetric fog** + distance fog with aerial perspective | Environment |
| Soft contact shadows | **SSAO** (screen-space ambient occlusion) | Environment |
| Reflections in water | **SSR** (screen-space reflections) + custom water shader | water.gdshader |
| Glow on bright things | **Glow** (bloom); HDR colours > 1.0 bloom | Environment |
| Cinematic colours | **Filmic tonemapping**, contrast/saturation adjustment | Environment |
| Miniature / diorama feel | **Depth of field** (`CameraAttributesPractical`) | camera_rig.gd |
| Sky gradient | `ProceduralSkyMaterial` | level_builder.gd |
| Five moods | per-level theme table | themes.gd |

### The water shader (scripts/world/water.gdshader)
A **spatial shader** (runs on the GPU for every pixel of the water):
- `height(p)` = three sine waves moving with `TIME`.
- The **normal** is computed from the slope of that height (finite differences: `dx`, `dz`), so the surface
  *looks* rippled without moving any vertices.
- **Fresnel**: `pow(1 − dot(NORMAL, VIEW), 3)` makes the water brighter at grazing angles, like real water.
- `ROUGHNESS = 0.04` (almost a mirror), so the engine's SSR reflects the hunter, trees and lanterns in it.

### The impact-frame shader (scripts/fx/impact_frame.gdshader)
A **canvas_item shader** on a full-screen rectangle. It reads the rendered screen
(`hint_screen_texture`), turns each pixel's brightness into **two tones** (black or white, optionally
inverted) and paints the mid-tones red. It's shown for 45 ms steps on big hits (§12).

---

## 8. The hunter: movement

File: `scripts/actors/player.gd`, scene `scenes/actors/player.tscn`
(`CharacterBody3D` + capsule collision + `SheetSprite` + `Hitbox` Area3D).

### 8.1 The state machine
The hunter is always in exactly one **state**:

```
NORMAL ─J→ ATTACK ─J→ ATTACK…          NORMAL ─L→ HEAVY
NORMAL ─W+J→ LAUNCH ─Space→ NORMAL(air)   NORMAL(air) ─J→ AIR_ATTACK ─J→ AIR_ATTACK…
NORMAL(air) ─S+J / L→ DIVE ─land→ NORMAL   NORMAL(air) ─Shift→ AIR_DASH
NORMAL ─Shift→ DODGE   NORMAL ─hold K→ BLOCK   any ─hit→ HURT   hp 0 → DEAD
NORMAL ─U (full spirit)→ SPECIAL   talking → TALK
```

`_physics_process` runs the function for the current state (`match state:`). Each state decides
movement, which animation plays and which states it can go to next. That keeps every move's rules in
one place and stops impossible combinations, like attacking while dodging.

### 8.2 Running and jumping: the numbers

| Setting | Value | Meaning |
|---|---|---|
| run_speed | 6.6 m/s | top speed |
| ground_accel / decel | 60 / 70 m/s² | how fast it reaches top speed / stops (not instant = weight) |
| air_accel | 38 m/s² | less control in the air |
| jump_velocity | 14.5 m/s | |
| gravity | 30 m/s² | stronger than real (9.8) for a snappy arc |
| fall_multiplier | 1.5 | falls faster than it rises (feels less floaty) |
| max_fall_speed | 24 m/s | terminal velocity |

**Jump height** = v² / 2g = 14.5² / 60 = **3.5 m**. That's why levels use ledges of at most 3 tiles,
and 4 tiles needs a crate or wall-jump.

Movement each physics tick: `velocity.x = move_toward(velocity.x, input × speed, accel × delta)`, gravity is
added to `velocity.y`, then **`move_and_slide()`** moves the body and slides it along walls and floors.

### 8.3 Platformer "feel" tricks
- **Coyote time (0.1 s)**: you can still jump just after running off a ledge.
- **Jump buffer (0.13 s)**: pressing jump slightly *before* landing still jumps when you land.
- **Variable jump height**: releasing Space while rising multiplies `velocity.y` by 0.45.
- **Wall slide**: pushing into a wall while falling caps fall speed at 3.2 m/s.
- **Wall jump**: jump while touching a wall gives an upward velocity plus a 7.6 m/s push away, with
  0.17 s of input lock so you can't cancel the push.
- **Staff Vault** (power, memory 1): one extra jump in mid-air (12.5 m/s).
- **Air Dash** (power, memory 2): 15 m/s horizontal burst for 0.2 s, gravity off, invulnerable,
  damages enemies it passes through.

### 8.4 Safe ground
While standing on the floor for 0.35 s, the position is remembered. Falling into water costs a heart
and puts you back there (`drown()`).

### 8.5 One-way wooden platforms
Platforms are on **collision layer 3**. Each tick the hunter turns layer 3 **on in its mask only while
falling** (`velocity.y <= 0.5`), so you jump up through them and land on top. **Down + Jump** switches
it off for 0.3 s to drop through.

```gdscript
set_collision_mask_value(3, velocity.y <= 0.5 and _drop_timer <= 0.0)
```

### 8.6 Pushing crates
After `move_and_slide()` the hunter checks what it bumped (`get_slide_collision`). If it's a
`RigidBody3D` and you're pushing toward it, it applies an impulse, and the physics engine slides the crate.

---

## 9. The hunter: combat

BREKEKEKEX's combat rules: **direction matters** (horizontal swings for crowds, vertical strikes for
one target), **defence is movement** (block and dodge), **air juggling**, and hits do real damage.

### 9.1 How a hit is detected
The hunter has an **`Area3D` hitbox** (`$Hitbox`) that is resized and moved in front of him for each move
(`_set_hitbox(size, offset)`). On the move's **active frames** it asks
`hitbox.get_overlapping_bodies()`. Each enemy found gets `take_hit(...)` **once per swing** (its id is stored
in `_hit_ids`). Crates (RigidBody3D) get an impulse instead, and a heavy hit smashes them.

### 9.2 The moves (frame data)

| Move | Input | Active frames | Damage | Special effect |
|---|---|---|---|---|
| Sweep | J | 1–2 of 5 (16 fps) | 1 | wide; chains into a 2nd sweep; can dodge-cancel |
| **Launcher** | W + J | 1–2 of 5 | 1 | **lift 13 m/s**: throws the enemy into the air; Space follows it up |
| Smash | L | 2–3 of 6 (14 fps) | 3 | heavy: big knockback, staggers anything, smashes crates; 28 stamina |
| **Air combo** | J in air | whole spin | 1 per hit | you **float** (55% gravity) and hits keep the enemy up: **juggle** (up to 4 swings) |
| **Dive** | S + J or L in air | while falling | 2 | plunges at 26 m/s, bounces enemies back up, shockwave on landing |
| **Moon Breaker** | U, full spirit | landing | 5 to all within 7.5 m | leap + crash; launches everything; impact frame; camera crane shot |
| Spirit Wave | L (memory 3) | — | 2 | the smash sends a glowing shockwave along the ground |

**Juggling, explained:** a hit can carry a **lift** value. If the enemy can be launched
(`juggle_resist < 1`) its `velocity.y` is set to that lift and it enters the **"air" state**, helpless and
falling slowly until it lands. Air hits re-apply a little lift (`velocity.y = max(velocity.y, 4.5)`),
and every air hit also bumps the hunter up, so you can keep a frog in the air.

### 9.3 Defence
- **Block (hold K)**: frontal hits cost 18 stamina instead of health. At 0 stamina the guard breaks
  and the hit goes through.
- **PARRY (tap K just before a hit)**: pressing K starts a **0.26 s window** (`_parry_t`). If a hit
  arrives while blocking inside that window: the attacker is **stunned for 1.6 s** (and takes +1
  damage from every hit while stunned), +25 spirit, hit-stop, impact frame, "PARRY" popup.
- **Dodge (Shift)**: 0.34 s roll at 11.5 m/s, invulnerable, 22 stamina.
- **PERFECT DODGE**: if an attack connects within the first **0.22 s** of the roll, time slows to 30% for
  0.7 s ("frog time"), stamina is refunded, +20 spirit, "PERFECT" popup. Rolling *through* an attack also
  counts.

`take_damage()` returns what happened (`"hit"`, `"blocked"`, `"parried"`, `"dodged"`, `"immune"`), so
thrown daggers know whether to stop, fly past or bounce back.

### 9.4 Stamina and spirit
- **Stamina** (green): spent by dodge, smash and blocked hits; refills at 34/s after a short delay.
  It stops you spamming defence.
- **Spirit** (gold): **earned by fighting well**: +6 per hit, +10 heavy hit, +25 parry, +20 perfect dodge,
  +10 knocking back a dagger, +2 per orb. When it's full, **U** fires the Moon Breaker.

### 9.5 Powers from memories
Each memory eye gives back a power (`GameState.POWERS`, checked with `GameState.has_power()`):

| Memory | Power | Effect |
|---|---|---|
| 1 Reedwake | **Staff Vault** | double jump |
| 2 Drowned Grove | **Air Dash** | Shift in mid-air; cuts through enemies |
| 3 Glowing Hollows | **Spirit Wave** | the smash fires a ground shockwave |
| 4 Sunken Temple | **Koax's Blessing** | spirit fills 50% faster |

On pickup a "NEW POWER" title card appears. **Chapters** on the title screen start any land with the powers
of the lands before it.

---

## 10. The enemies

### 10.1 One base class, many enemies
`scripts/actors/enemy.gd` (`class_name Enemy`) contains everything shared: gravity, facing, taking hits,
juggles, stuns, dying, orb drops, attack tells. Each type **extends** it and only writes `think(delta)`,
which holds its decisions (**inheritance + polymorphism**).

```
Enemy ─┬─ Hopper
       ├─ Cultist
       └─ Brute ── ToadKing (boss)
```

The enemy is a small state machine too: `idle / walk / hop` plus its attack states, and the shared
`hurt`, `air` (juggled), `down`, `stunned`, `evade` and `dead`.

### 10.2 Why they are not predictable

| Mechanism | How it works |
|---|---|
| **Tells** | `windup(anim, seconds)` freezes the first frame of the attack and flashes the sprite red, then releases |
| **Random timing** | every wind-up length is multiplied by a random 0.75–1.25, so there is no fixed rhythm to count |
| **Feints** | with `feint_chance`, the wind-up is a bluff: it flashes, then the enemy hops back instead |
| **Evasion** | when you start a swing in front of an enemy, the player calls `threatened()`; with `evade_chance` it dodges back and your hit shows **MISS** |
| **Combos** | cultists slash 1–3 times, brutes punch once or twice; follow-ups have short tells |
| **Mixed ranges** | hoppers pounce from mid-range, cultists throw daggers from far, brutes charge across the arena |
| **Attack slots** | a static dictionary allows at most **2 enemies attacking at once**; the rest reposition. Groups surround you without an unfair pile-on |

### 10.3 Each enemy

| Enemy | HP | Dmg | Behaviour |
|---|---|---|---|
| **Hopper** | 3 | 1 | erratic hops (25% hop away); tongue lash up close; **pounce** (flying body attack) from 3–6 m; 30% evade |
| **Cultist** | 5 | 1 | keeps ~3 m away and **sways** in and out of reach; 1–3 slash combos; **throws daggers** from 4.5–9 m; 45% evade, 25% feint |
| **Brute** | 10 | 2 | **super armour** (light hits don't stagger); punch combos; **charge** rush; **leaping slam** with a two-sided shockwave |
| **Toad King** | 45 | 2 | a giant brute (1.8× size) that summons hoppers. **Phase 2** under 50%: roars, turns red, attacks faster, **double slams**, charges more, bluffs, summons 3 |

### 10.4 Projectiles (scripts/actors/projectile.gd)
A thrown dagger is a glowing `PrismMesh` with a small light that moves every physics tick and uses a
**raycast** (`PhysicsRayQueryParameters3D`) to stop at walls. If the hunter is **swinging** next to it, or
**parries** it, it is **reflected** back at its thrower (it flips to friendly and turns gold). If he
dodges, it flies past. The Spirit Wave is the same class, created as friendly.

---

## 11. The camera

File: `scripts/camera/camera_rig.gd`. This is where the **BREKEKEKEX / anime-arena-fighter feel** lives.
The camera is never glued to the hunter; every value is *pulled toward* a goal.

### 11.1 Delayed follow: a spring
The camera's focus point is a **critically-damped spring**:

```
acceleration = (goal − position) · ω²  −  velocity · 2ω       (ω = follow_speed = 4.5)
velocity += acceleration · delta
position += velocity · delta
```

It lags behind the hunter, catches up smoothly and **never overshoots**. When you fall fast, ω is
increased so you don't fall off-screen.

### 11.2 Look-ahead and air tilt
- The goal is shifted 2.4 m in the facing direction (+ a bit with speed), so you see where you are going.
- In the air the camera **pitches down** (−11° to −22°), so you see where you will land.

### 11.3 Arena framing (combat mode)
When an enemy is within 8 m:
- the camera **dollies in** (13 m → 9 m) and widens the FOV,
- it **swings round up to 22°** to the side of the enemies, over the hunter's shoulder,
- the focus **leans toward the midpoint** between the hunter and the nearest enemy, and the camera
  **pulls back as they separate**. Like an arena fighter, it keeps **both fighters in frame**.

### 11.4 Event cameras (cinematic moves)
Gameplay calls `get_tree().call_group("camera", "event", "launch")`, and the camera layers a short
move on top of the follow. Each has a duration and offsets in yaw, pitch, distance and FOV, blended
by an **envelope** (snaps in during the first 15%, holds, eases out). It runs on **real time**, so it
still plays during slow motion.

| Event | Shot |
|---|---|
| `launch` | **low angle looking up** at the launched enemy, push in |
| `dive` | **high angle** looking down at the plunge |
| `dash` | FOV whip (+10°) |
| `parry`, `perfect`, `kill` | slow **push-in** with a slight swing (during the slow-mo) |
| `special` | **crane shot**: swings 34° round and looks up while the hunter rises |
| `slam` | pull back, look down, heavy shake |
| `roar` | boss phase 2: push in + shake |

### 11.5 Shake, FOV punch, depth of field
- **Trauma shake**: hits add "trauma" (0–1) that decays over time. The shake is trauma², applied as
  `h_offset`/`v_offset` plus a little roll, driven by **FastNoiseLite** (smooth noise, not jitter).
- **FOV punch**: a heavy hit narrows the FOV by 5° for a moment (a "zoom punch").
- **Depth of field**: blur distances are set every frame from the camera distance: sharp on the lane,
  blurred far bank and near reeds.

**If the teacher asks "how did you implement the camera?"**
"A Camera3D on a rig script. A spring-damper follows the player with a delay and look-ahead; in combat it
frames the player and the nearest enemy, dollies in and swings over the shoulder; gameplay events trigger short
cinematic offsets like a low angle on launchers; shake uses noise-driven offsets from a trauma value; and
depth of field is updated every frame."

---

## 12. Game feel

| Effect | How |
|---|---|
| **Hit-stop** | `GameState.hitstop(duration, scale)` sets `Engine.time_scale` to 5% for 55 ms (light) / 120 ms (heavy), then restores it with a timer that ignores the time scale. A token makes overlapping calls safe |
| **Slow motion** | the same function with a gentler scale: perfect dodge 30% for 0.7 s, big kills 25% for 0.45 s |
| **Impact frames** | `ImpactFrame` (scripts/fx/impact_frame.gd) shows the two-tone red/black/white shader for 2–3 steps of 45 ms on heavy hits, parries and the special |
| **White flash** | a hit enemy's sprite `modulate` is set to (3,3,3) for 90 ms (over-bright = white) |
| **Red tell flash** | wind-ups alternate the modulate with red every 60 ms |
| **Sparks / dust / splashes** | `HitFx` makes one-shot `CPUParticles3D` bursts with a soft round texture; sparks use HDR colours so they bloom |
| **Shockwave rings** | a `TorusMesh` scaled outward and faded with a Tween |
| **Popups** | `Label3D` words ("PARRY", "PERFECT", "MISS", "REFLECT") that pop, rise and fade |
| **Combo counter** | the HUD counts hits that land within 1.8 s of each other |
| **Fireflies** | a `CPUParticles3D` box of glowing motes that follows the camera |

---

## 13. World objects

| Object | Node type | How it works |
|---|---|---|
| **Pickup** (orb, peach, key, eye) | `Area3D` | `body_entered` → effect; orbs drift toward you within 3.2 m; bobbing via `sin(time)` |
| **Gate** | `StaticBody3D` + sensing `Area3D` | if you have a key: uses it, disables its collision, sinks with a Tween |
| **Shrine** | `Area3D` | lights up (texture swap + light), restores health, **saves** with its index |
| **Exit** | `Area3D` | only opens if this land's memory eye was found → level complete |
| **Crate** | **`RigidBody3D`** | real physics; axis locks keep it on the lane; smash → orb + respawn at home so puzzles can't break |
| **Thorns** | `Area3D` | damages you every tick you overlap (invulnerability frames stop it draining instantly) |
| **Water** | `Area3D` | you: lose a heart and return to safe ground; enemies drown; crates respawn |
| **Old Koax** (NPC) | `Area3D` + `Label3D` | standing near sets `interact_target`; E starts the conversation |

Most of them are `@tool` scripts so their sprites appear in the editor, while their gameplay code is skipped
there (`if Engine.is_editor_hint(): return`).

---

## 14. UI

- **HUD** (scripts/ui/hud.gd): one `Control` that draws everything in `_draw()`:
  - hearts from the heart curve `x = 16 sin³t, y = 13 cos t − 5 cos 2t − 2 cos 3t − cos 4t`,
  - stamina and spirit bars, orbs, keys, the 5 memory eyes, the combo counter, the boss bar,
  - a fading title card and hints.

  It runs with `PROCESS_MODE_ALWAYS` so it still updates while the game is paused.
- **Dialogue** (scripts/ui/dialogue_box.gd): a `PanelContainer` with portrait, name and text. The text
  types out by increasing `visible_characters` (48 per second). While talking, the game **pauses**
  (`get_tree().paused = true`) and the dialogue box keeps running because its process mode is ALWAYS.
- **Menus** (scripts/ui/menus.gd): pause (Esc), game over, level complete and the ending (a Tween sequence of
  story pages → "BREKEKEKEX KOAX KOAX" → "TO BE CONTINUED…").
- **Title** (scripts/ui/title.gd): builds the real level 1 behind the menu with a drifting camera.
  Continue / New Game / **Chapters** / Controls / Quit.
- **Story text** lives in `assets/dialogue/story.json` (conversations, hints by x position, memories, powers,
  ending), so writing is separate from code.

---

## 15. Saving and loading

`GameState.save_game()` writes a **`ConfigFile`** (an INI-style file) to `user://save.cfg`:

```ini
[progress]
level=2
checkpoint=1        ; index of the last shrine lit
orbs=37
memories=[1]
deaths=4
best_level=2
```

It saves when a **shrine** is lit, a **memory** is found, a **level** starts and when you **die**.
**Continue** calls `load_game()` and `game.gd` places you at shrine number `checkpoint`.
On macOS `user://` is `~/Library/Application Support/Godot/app_userdata/BREKEKEKEX - The Hunter Who Forgot/`.

---

## 16. Physics layers and collisions

A body's **layer** says what it *is*; its **mask** says what it *collides with / detects*.

| # | Layer | Who is on it | Who detects / collides with it |
|---|---|---|---|
| 1 | world | terrain, gates | player, enemies, crates, projectile raycasts |
| 2 | player | the hunter | pickups, shrines, exit, NPC, thorns, water |
| 3 | platform | wooden platforms | player (only while falling), enemies, crates |
| 4 | enemy | frogs, cultists, boss | the player's hitbox, water |
| 5 | pickup | orbs, keys, eyes | — |
| 6 | crate | crates | player, hitbox, water, other crates |
| 7 | hazard | thorns, water | — |

Node types: **CharacterBody3D** (hunter, enemies: code decides velocity, `move_and_slide` resolves
collisions), **StaticBody3D** (terrain), **RigidBody3D** (crates: the physics engine simulates them),
**Area3D** (triggers: detect overlap without blocking).

---

## 17. Testing

- **Godot debugger**: Output (prints and errors), Debugger → Monitors (FPS ≈ 60, draw calls), the Remote
  scene tree, *Debug → Visible Collision Shapes*.
- **Reachability check**: a script checked every level map so every key, eye, shrine and exit can be
  reached with the hunter's jump height and distance.
- **Automated test bot** (`tools/autotest.tscn`): loads a level, presses keys through `Input.action_press`,
  takes screenshots and prints results. Verified so far:

| Test | Result |
|---|---|
| Wall-jump shafts (levels 1, 3, 4) | climbed 7 m → 19–21 m |
| Crate puzzle | crate pushed to the ledge, hunter on top of the ledge (y = 9) |
| One-way platform | jumped up through (y 6 → 9), dropped down (9 → 6) |
| Launcher → juggle → dive | enemy launched (11 m/s), killed in the air |
| Parry | enemy stunned, +25 spirit, no damage taken |
| Perfect dodge | time scale 0.30, +20 spirit, no damage taken |
| Boss → ending | final memory, ending and sequel tease play |

```bash
godot --path . res://tools/autotest.tscn -- --level=1 --duel
```

---

## 18. Viva question bank

**Engine & structure**
- *Which engine and why?* Godot 4.7: free, open source, scene/node architecture, GDScript, built-in 3D
  renderer with volumetric fog/SSR/SSAO, exports to all desktops.
- *Scene vs node?* A node is one component; a scene is a saved, reusable tree of nodes.
- *What's an autoload?* A singleton node loaded at startup that survives scene changes (GameState, Audio, Controls).
- *How do objects communicate?* Signals (events, e.g. `player.died`), groups (`call_group("camera", …)`), and direct
  calls for known references.
- *`_process` vs `_physics_process`?* Every frame vs fixed 60 Hz. Movement and collision use physics for stability.
- *Why multiply by delta?* So speed is in units per second, independent of frame rate.

**Graphics**
- *How are sprites made?* C++ rasterizer: polygons → affine matrices (hierarchical skeleton) → scan-line fill →
  1 px outline → sprite-sheet PNG + JSON.
- *What algorithms from the course?* Scan-line polygon fill and 2D composite transformations (translate/rotate/scale,
  rotation about a pivot) in the sprite generator; per-cell clipping of every polygon to its sprite-sheet cell.
- *How does animation work?* AnimatedSprite3D + SpriteFrames built from AtlasTexture regions of the sheet.
- *Why 2D sprites in 3D?* HD-2D: pixel art that gets real light, shadows, fog, reflections and parallax depth.
- *How are the water reflections done?* A custom shader makes the water a rippled near-mirror; screen-space
  reflections reflect the scene in it; Fresnel brightens it at grazing angles.
- *What is a shader?* A small GPU program run per vertex/pixel. We wrote a spatial (3D) water shader and a
  canvas_item (2D) impact-frame shader.
- *How is the level mesh made?* SurfaceTool builds quads only for exposed faces, with world-space UVs and
  vertex-colour depth shading.

**Physics & gameplay**
- *Collision layers vs masks?* Layer = what I am, mask = what I collide with/detect.
- *One-way platforms?* Platform layer is enabled in the player's mask only while falling.
- *Kinematic vs rigid body?* CharacterBody3D is moved by code (`move_and_slide`); RigidBody3D is simulated by the
  physics engine (crates).
- *How do attacks hit?* An Area3D hitbox positioned per move; on active frames `get_overlapping_bodies()`; each target
  hit once per swing.
- *Coyote time / jump buffer?* Small grace windows that forgive input timing (0.1 s / 0.13 s).
- *How is juggling done?* Hits carry a lift velocity; the enemy enters an "air" state with reduced gravity; air hits
  re-apply lift.
- *Parry / perfect dodge?* Timing windows: block pressed ≤0.26 s before the hit → stun; hit within 0.22 s of a dodge
  → slow motion.
- *How is the AI made?* State machines with telegraphed, randomised wind-ups, feints, evasion, combos, and attack
  slots limiting simultaneous attackers; the boss has a second phase.
- *How is hit-stop done?* `Engine.time_scale` set very low for a few hundredths of a second with a timer that ignores time scale.

**Camera, audio, saving**
- *Camera?* Spring-damper follow with look-ahead, combat framing of both fighters, over-the-shoulder swing, event
  cameras for special moves, noise shake, FOV punch, DOF.
- *Audio?* Synthesised WAVs (Karplus–Strong, filtered noise, bells); a pool of AudioStreamPlayers; music cross-fade with Tween.
- *Saving?* ConfigFile at `user://save.cfg`, written at shrines/memories/level start/death; Continue restores level + shrine.

**Story**
- *What's the story?* Iko, a frog hunter, loses his memory to the Toad King's cult, which seals memories inside frog eyes.
  Old Koax guides him through five lands. Each eye returns a memory and a power. He defeats the Toad King and remembers
  everything, but something vast wakes under the marsh. Sequel tease.

---

## 19. File index

| File | What it does |
|---|---|
| `project.godot` | engine settings: main scene, autoloads, window, layers, Vulkan |
| `scripts/autoload/controls.gd` | input actions (keyboard + gamepad) |
| `scripts/autoload/game_state.gd` | progress, hp, spirit, powers, save/load, hit-stop |
| `scripts/autoload/audio.gd` | sound pool + music cross-fade |
| `scripts/actors/player.gd` | the hunter: state machine, movement, combat, parry, dodge, powers, special |
| `scripts/actors/enemy.gd` | enemy base: tells, feints, evasion, attack slots, juggles, stun, death |
| `scripts/actors/hopper.gd` / `cultist.gd` / `brute.gd` / `toad_king.gd` | each enemy's decisions |
| `scripts/actors/projectile.gd` | daggers and spirit waves (reflectable) |
| `scripts/actors/sheet_sprite.gd` | sprite sheet → SpriteFrames animations |
| `scripts/camera/camera_rig.gd` | the dynamic camera |
| `scripts/fx/hit_fx.gd` | particles, rings, popups |
| `scripts/fx/impact_frame.gd` + `.gdshader` | anime impact frames |
| `scripts/world/level_data.gd` | parses level text files |
| `scripts/world/level_builder.gd` | builds the 3D level from the map |
| `scripts/world/themes.gd` | the five lands' looks |
| `scripts/world/props.gd` | sprite props + shared sprite style |
| `scripts/world/water.gdshader` | water |
| `scripts/world/pickup.gd`, `gate.gd`, `shrine.gd`, `level_exit.gd`, `crate.gd`, `thorns.gd`, `water_zone.gd`, `npc.gd` | world objects |
| `scripts/ui/hud.gd`, `dialogue_box.gd`, `menus.gd`, `title.gd`, `ui_style.gd` | interface |
| `scripts/game/game.gd` | runs a level: spawn, story, memories, exit, boss, death |
| `assets/levels/level_1..5.txt` | the maps |
| `assets/dialogue/story.json` | all story text |
| `tools/assetgen.cpp` | draws all sprites and textures |
| `tools/audiogen.py` | synthesises all audio |
| `tools/autotest.gd/.tscn` | automated test bot |
