#!/bin/bash
# Double-click to play BREKEKEKEX (runs the project directly with Godot).
cd "$(dirname "$0")"
GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
[ -x "$GODOT" ] || GODOT="$(command -v godot)"
if [ -z "$GODOT" ]; then echo "Godot not found. Install it with: brew install --cask godot"; read -n1; exit 1; fi
# first run: import the assets (creates the hidden .godot folder)
[ -d .godot ] || "$GODOT" --headless --path . --import
exec "$GODOT" --path . --rendering-driver vulkan
