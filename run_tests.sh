#!/usr/bin/env bash
# Test entry point. Exit 0 = all pass.
#
# The suite runs headless: the simulation kernel and the error engine have no scene
# dependency, so this needs no GPU, no headset and no display.
set -euo pipefail

GODOT="${GODOT:-./Godot_v4.7.2-stable_linux.x86_64}"
if [ ! -x "$GODOT" ]; then
  GODOT="$(command -v godot || true)"
fi
if [ -z "$GODOT" ] || [ ! -x "$GODOT" ]; then
  echo "Godot 4.7 binary not found; set GODOT=/path/to/Godot_v4.7.2-stable" >&2
  exit 2
fi

"$GODOT" --headless --import > /dev/null 2>&1 || true
"$GODOT" --headless --script res://tests/runner.gd
