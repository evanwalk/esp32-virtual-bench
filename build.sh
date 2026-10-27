#!/usr/bin/env bash
# Build a signed debug APK, from a clean clone.
#
# Sets up everything the export needs (export templates, engine .aar libraries, Android
# build template, a debug keystore) then invokes Godot. Idempotent: re-running is safe
# and only fills in what is missing.
#
# Requirements: Godot 4.7.2 binary, JDK 17, Android SDK with platform-tools /
# platforms;android-36 / build-tools;36.1.0 / ndk;29.0.14206865, and the matching
# export templates .tpz. See README.
set -euo pipefail

: "${ANDROID_HOME:?set ANDROID_HOME to your Android SDK}"
: "${JAVA_HOME:?set JAVA_HOME to a JDK 17}"
# Gradle refuses to build if ANDROID_SDK_ROOT names a different SDK, and CI images
# pre-set it. Align it with ANDROID_HOME.
export ANDROID_SDK_ROOT="$ANDROID_HOME"
GODOT="${GODOT:-./Godot_v4.7.2-stable_linux.x86_64}"
ARCH="$(uname -m)"
APP_VERSION="4.7.2.stable"

OUT="build/vbench.apk"
TPL="${GODOT_TPL_DIR:-$HOME/.local/share/godot/export_templates/$APP_VERSION}"
SRC_TPZ="${GODOT_TPZ:-Godot_v4.7.2-stable_export_templates.tpz}"

[ -x "$GODOT" ] || { echo "Godot 4.7.2 binary not found at $GODOT (set GODOT=)" >&2; exit 2; }
[ -f "$SRC_TPZ" ] || { echo "export templates .tpz not found at $SRC_TPZ (set GODOT_TPZ=)" >&2; exit 2; }

# 1. Export templates: both the engine .aar libraries and the Android source tree come
#    from inside the .tpz. Only the pieces this project needs are extracted.
if [ ! -f "$TPL/android_source.zip" ]; then
  echo "==> installing export templates into $TPL"
  mkdir -p "$TPL"
  unzip -o -j "$SRC_TPZ" 'templates/android_*' -d "$TPL" > /dev/null
fi

# 2. Android build template + the version marker Godot validates against.
if [ ! -f android/build/build.gradle ]; then
  echo "==> unpacking Android build template"
  rm -rf android/build
  mkdir -p android/build
  unzip -o "$TPL/android_source.zip" -d android/build > /dev/null
  : > android/build/.gdignore
fi
printf '%s\n' "$APP_VERSION" > android/.build_version

# 3. Engine libraries (gitignored, ~207 MB) live inside android_source.zip and must be
#    present in the Gradle project. Only the archive's libs/ tree is extracted.
if [ ! -f android/build/libs/debug/godot-lib.template_debug.aar ]; then
  echo "==> installing engine libraries"
  unzip -o "$TPL/android_source.zip" 'libs/*' -d android/build > /dev/null
fi

# 4. Debug keystore, generated once.
if [ ! -f debug.keystore ]; then
  echo "==> generating debug keystore"
  keytool -genkeypair -v -keystore debug.keystore -storepass android \
    -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=Android Debug,O=Android,C=US" > /dev/null
fi

# 5. Editor settings: the exporter reads SDK paths from here, not from the environment.
SETTINGS="${XDG_CONFIG_HOME:-$HOME/.config}/godot/editor_settings-4.7.tres"
if [ ! -f "$SETTINGS" ]; then
  echo "==> writing Godot editor settings ($SETTINGS)"
  mkdir -p "$(dirname "$SETTINGS")"
  cat > "$SETTINGS" <<EOF
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "$ANDROID_HOME"
export/android/java_sdk_path = "$JAVA_HOME"
export/android/debug_keystore = "$PWD/debug.keystore"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
EOF
fi

# 6. Export.
echo "==> importing and exporting ($ARCH)"
mkdir -p build
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/build-tools/36.1.0:$PATH"
"$GODOT" --headless --import > /dev/null
"$GODOT" --headless --export-debug "Quest3" "$OUT"

[ -s "$OUT" ] || { echo "export produced no APK" >&2; exit 1; }
echo "==> built $OUT ($(du -h "$OUT" | cut -f1))"
