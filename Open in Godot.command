#!/bin/bash
# Double-click to open the project in the Godot editor.
cd "$(dirname "$0")"
GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
[ -x "$GODOT" ] || GODOT="$(command -v godot)"
if [ -z "$GODOT" ]; then echo "Godot not found. Install it with: brew install --cask godot"; read -n1; exit 1; fi
exec "$GODOT" --path . --editor --rendering-driver vulkan
