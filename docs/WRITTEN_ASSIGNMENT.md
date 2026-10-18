# Assignment 6 — Developing the Game using a Game Engine

**Name:** Vedant Ghule   **Subject:** Computer Graphics & Gaming (BCE25PE01)
**Game:** BREKEKEKEX — *The Hunter Who Forgot*   **Game Engine:** Godot 4.7

---

## Theory

In Assignments 1–5 the game was coded from scratch using computer-graphics algorithms
(line/circle drawing, polygon filling, 2D transformations, clipping). In this assignment
the **same game is rebuilt using a game engine**. A game engine provides ready-made
systems for rendering, physics, input, audio and scene management, so the developer can
focus on game design instead of re-coding everything. The engine chosen is **Godot 4.7**.

---

## 1. Installation of Game Engine

- **Development platform:** Godot 4.7 (free, open-source engine) on macOS. It uses a
  *scene–node* system and the *GDScript* language.
- **Installation:** Godot was installed via Homebrew (`brew install --cask godot`); no
  extra plugins were needed as rendering, physics and audio are built in.
- **Interface understood:**
  - *Scene dock / hierarchy* – shows the tree of nodes in the current scene.
  - *FileSystem (asset/project window)* – all project files (scripts, sprites, levels).
  - *Inspector* – edit the properties of the selected node.
  - *Game view / viewport* – 2D and 3D preview; F5 runs the game.
- **Project settings configured:** window size 1280×720, main scene set to the title
  screen, renderer set to Vulkan (fixes a macOS freeze), and an **Input Map** defining
  actions like *jump*, *attack*, *dodge* bound to keyboard keys and a gamepad.

---

## 2. Conceptualization of Game Theme

- **Theme & genre:** a 2.5D (HD-2D) action-platformer set in a foggy swamp, inspired by
  the game *BREKEKEKEX*.
- **Main objective:** the hunter must recover his lost memories and defeat the frog cult.
- **Game elements:**
  - *Player:* Iko, a staff-wielding hunter.
  - *Enemies:* hopper frogs, cultists, brute frogs, and the Toad King (boss).
  - *Environment:* reed marshes, flooded groves, caves, a temple, the cult's throne.
  - *Obstacles:* water pits, thorns, locked gates.
  - *Collectibles:* spirit orbs, health peaches, keys, memory eyes.
- **Game flow (storyboard):** Start screen → Level 1 → fight enemies, solve platforming,
  collect the memory eye → reach exit → next level → … → boss fight → ending.
- **Win / lose conditions:** *Win* – clear all 5 levels and defeat the boss.
  *Lose* – health reaches zero (respawn at the last checkpoint).

---

## 3. Character Design

- **Main character & sprites:** the hunter and all enemies are **2D pixel-art sprites**
  created using the course algorithms (polygons placed by **transformation matrices**,
  filled with the **scan-line algorithm**, outlined). These are the same techniques used
  in Assignments 2–4.
- **Textures, colours, visual properties:** sprites are drawn in a 3D world as cut-outs
  that receive lighting and shadows (the HD-2D look).
- **Animation states:** each character has multiple states — *idle, run, jump, fall,
  attack, heavy, dodge, block, hurt, death*. In the engine these are loaded as a
  `SpriteFrames` animation resource and played with `AnimatedSprite3D`.

---

## 4. Movement and Character Control

- **Input:** keyboard and gamepad are mapped through the engine's Input Map (move, jump,
  attack, dodge, interact).
- **Movement:** horizontal run, jump, wall-jump, and drop-through-platform are
  implemented. Gravity and acceleration give the movement weight.
- **Actions:** jumping (with variable height), dodging, and attacking with the staff.
- **Animation linked to movement:** a **state machine** chooses the correct animation for
  the current action (e.g. running plays the "run" animation).
- **Testing:** controls were tuned with *coyote time* and *jump buffering* so they feel
  smooth and responsive.

---

## 5. Level Design

- **Game world:** five levels, each with its own theme (marsh, grove, caves, temple,
  throne).
- **Level construction:** levels are stored as **tile maps** (a grid where one letter =
  one tile). A builder script converts the grid into 3D ground, platforms and water.
- **Obstacles & enemies:** water gaps, thorns, gates, and enemies are placed from the map.
- **Interactive & collectible objects:** orbs, keys, health pickups, checkpoints (shrines)
  and the level exit are placed in each level.
- **Organization:** objects are grouped into layers (ground, platforms, enemies,
  pickups, hazards) using **collision layers**.

---

## 6. Player–World Interaction

- **Collision detection:** handled by the engine using collision shapes on each object.
- **Player–environment interaction:** standing on platforms, pushing crates, falling into
  water, touching thorns.
- **Actions:** collecting orbs/keys, opening gates with keys, lighting shrines
  (checkpoints), and reaching the exit.
- **Game rules:** health (hearts), a score of spirit orbs, and level progress are tracked
  and shown on the HUD.
- **Physics engine:** gravity, collisions and forces are used — e.g. crates are
  `RigidBody3D` objects that can be pushed and stacked.

---

## 7. Audio Integration

- **Background music & SFX:** all audio is synthesised (plucked strings, frog croaks,
  bells, filtered noise) — 27 sound effects and 4 music tracks.
- **Audio sources:** an *Audio* autoload manages a pool of audio players so many sounds
  can play at once.
- **Action sounds:** jumping, attacking, collecting, taking damage, shrine saves, and the
  boss's roar all have sounds.
- **Volume & playback:** effects have a little random pitch to avoid repetition; music
  **cross-fades** when the level changes and loops.
- **Testing:** audio was checked in-game to confirm sounds trigger on the right events.

---

## 8. Camera and Rendering

- **Camera:** a `Camera3D` that **follows the player with a delay** (a spring, so it lags
  then settles) and, during combat, zooms in and swings over the shoulder to frame the
  fight.
- **Lighting & materials:** a directional light (sun) with shadows, plus lantern point-
  lights in volumetric fog.
- **Textures & effects:** reflective water, bloom (glow), depth of field, ambient
  occlusion (SSAO), and colour grading give the HD-2D look.
- **Rendering settings:** Forward+ renderer, Vulkan driver.
- **Verification & optimization:** all objects display correctly and the game runs at
  ~60 FPS.

---

## 9. Testing and Debugging

- Ran the game and tested every feature.
- Checked character movement and controls (jump, dodge, wall-jump).
- Tested collisions and interactions (pickups, gates, checkpoints).
- Verified collectibles, health/score, and win/lose conditions.
- Checked audio and rendering.
- Errors found were fixed — e.g. a macOS freeze was solved by switching the renderer to
  Vulkan; level maps were checked so every key and exit is reachable.

---

## 10. Final Game Build

- All 5 levels and features (combat, boss, save/continue, audio, story) completed.
- The full game was tested from start screen to ending.
- The game can be **exported** as a standalone application (via *Project → Export*) for
  macOS/Windows.
- The final build was verified to run independently of the editor.

---

## Conclusion

The game built with graphics algorithms in Assignments 1–5 was successfully recreated in
the **Godot game engine**. The engine handled rendering, physics, input, audio and scene
management, while the original course concepts (polygon filling and transformation
matrices) were reused to create the character art. The result is a complete 5-level
HD-2D action game with movement, combat, collectibles, checkpoints, a save system, a
dynamic camera, audio and a storyline.

*(Attach screenshots: title screen, a level, a combat moment, the boss fight.)*
