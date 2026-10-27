# ESP32 Virtual Bench

A pre-flight simulator for ESP32 circuits, for Meta Quest 3.

Wire ESP32 projects on a virtual breadboard, hit the power switch, press your buttons,
and get told what is electrically wrong **before** you commit to solder. The app models
incorrect circuits on purpose: a 5V jumper onto a 3.3V GPIO, a rail short, a reversed
LED, a missing ground — all flagged with the reason and the fix, on a cold board, before
the switch closes.

This is not a toy. It refuses to power a broken circuit.

## Status

Vertical slice, running on device. One board (ESP32-DevKitC V1), one breadboard, and
jumpers, LEDs, resistors and buttons.

* Simulation kernel: nodal analysis with per-element conductance, LED forward drop and
  reverse bias, regulator budget, GPIO drive clamping. Headless-testable.
* Error engine: 13 rules across three severity tiers. Errors block power-on.
* VR: OpenXR on Quest 3, controller rays, snap placement, physical power switch and
  pressable buttons. Hand tracking falls back to controller input.

Every electrical rule currently ships **provisional** — see
[docs/SPEC-PROVENANCE.md](docs/SPEC-PROVENANCE.md) for the per-rule source, the numbers
in force, and the known gaps. Mechanic's spec overrides any number here.

## Requirements

* Godot **4.7.2** (standard, not .NET) — `Godot_v4.7.2-stable_linux.x86_64`
* Android SDK with `platform-tools`, `platforms;android-35`, `build-tools;35.0.0`
* JDK 17
* Godot **Android export templates** for 4.7.2 (`Godot_v4.7.2-stable_export_templates.tpz`)
* An `adb` connection to the headset, with Developer Mode enabled on the Quest

## Build

```sh
export ANDROID_HOME="$HOME/android-sdk"
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export GODOT=./Godot_v4.7.2-stable_linux.x86_64
export GODOT_TPZ=./Godot_v4.7.2-stable_export_templates.tpz

./build.sh        # -> build/vbench.apk
```

`build.sh` is idempotent and does the whole toolchain setup: extracts the export
templates, unpacks the Android build template, drops in the engine libraries, generates
the debug keystore, writes the Godot editor settings the exporter reads its SDK paths
from, then exports.

Three things are worth knowing, because each one is a non-obvious export requirement:

* The preset uses **OpenXR** `xr_mode`, which Godot only permits with a **Gradle build**,
  which in turn needs the Android build template present at `android/build/` plus
  `android/.build_version` holding the exact template version. `build.sh` handles both.
* The 207 MB of `godot-lib.*.aar` engine libraries are gitignored, so a fresh clone has
  no `android/build/libs`; `build.sh` copies them out of the templates. The rest of
  `android/` is committed.
* The exporter reads `ANDROID_HOME`/`JAVA_HOME` from Godot's editor settings file, not the
  environment. `build.sh` writes that file if absent.

The exporter signs with `debug.keystore` (committed; it is a debug key, not a secret) and
verifies the signature as its last step.

## Deploy to a Quest 3

```sh
adb devices                      # must show the headset, state "device"
adb install -r build/vbench.apk
adb shell am start -n dev.evanwalk.vbench/com.godot.game.GodotApp
```

In the headset, open **Virtual Bench** from *Unknown Sources*. Developer Mode must be on
(Quest mobile app → headset → Developer Mode).

To deploy without a cable, `adb push` the APK and install from a file manager with
install-unknown-sources allowed — the APK is arm64-v8a only, matching Quest 3.

## Controls

| Action | Controller |
|---|---|
| Point | aim the ray from either hand |
| Act on target | trigger |
| Cycle scenario | grip (or `N` on desktop) |
| Place a part | trigger a palette chip, then trigger two holes across the centre channel |
| Run a wire | trigger a start hole, trigger the destination |
| Power on/off | trigger the switch on the panel |
| Press a button | trigger it |
| Lift a part / pull a wire | trigger it |

The app runs flat on desktop too (arrow keys, `N`, `Space`), which is how it is
smoke-tested in CI.

## Tests

```sh
./run_tests.sh
```

or directly:

```sh
"$GODOT" --headless --script res://tests/runner.gd
```

Exit code 0 means pass. The suite covers the netlist and node resolution, board tie
physics, the solver (Ohm's law, dividers, open and closed buttons, source conflicts), the
power state machine, and **one test per error class** plus the clean circuit that proves
there are no false positives. See `tests/suites/`.

## Layout

```
sim/        kernel: netlist, node resolution, solver, diagnostics, power gate. No scene deps.
spec/       board and component data, every constant cited.
scenes/     VR: rig, bench view, interaction controller, HUD, scenarios.
tests/      runner, fixtures, one suite per concern.
tools/      screenshot + probe harnesses (need Xvfb, not part of the suite).
docs/       architecture, spec provenance and gaps.
android/    Godot's Android build template; required for an OpenXR export.
```

`sim/` and `spec/` compile and run with no renderer, which is why the physics is testable
and the tests are the contract.

## Screenshots and scene probing (no headset)

```sh
xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --rendering-driver opengl3 \
  --xr-mode off --resolution 1280x720 --script res://tools/shots.gd
```

Writes one PNG per scenario to `/tmp/shots`. `--xr-mode off` is required: with no OpenXR
runtime present the engine aborts before the first frame. `tools/probe.gd` prints
on-screen coordinates of the bench and HUD, which is how framing was verified.

## Faults it catches today

Rail shorts (5V–GND, 3V3–GND, 5V–3V3) · 5V onto a 3.3V GPIO · output driven on an
input-only pin · strapping pin held at the wrong boot level · ADC2 used while WiFi is up ·
flash pins used · pin over-current · regulator over-current · floating input · missing
ground · reversed LED · LED with no series resistor · out-of-band series resistor.

## Known gaps

Steady state only (no inrush or thermal derating), motors modelled as resistors,
strapping fires on level not timing, no ADC accuracy, no peripheral routing validation.
Full list with rationale in [docs/SPEC-PROVENANCE.md](docs/SPEC-PROVENANCE.md).

## Licence

MIT — see [LICENSE](LICENSE).
