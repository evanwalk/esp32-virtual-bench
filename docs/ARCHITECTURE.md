# ESP32 Virtual Bench — architecture

A pre-flight simulator for ESP32 microcontroller circuits, built for Meta Quest 3.
You place parts on a virtual breadboard, wire them, flip the power switch, press the
buttons, and the simulator tells you whether the circuit would actually work before
you solder anything real.

## Why Godot instead of Unity

The deliverable allowed a justified alternative. Godot 4.7 was chosen because:

* **Headless, scriptable build.** `godot --headless --export-release` produces an APK
  from CI with no GUI, no licensing server, and no per-seat account. Unity's Android
  export needs an activated Editor, an account, and a large licensed install. The repo
  builds end-to-end on a bare Linux box, which is what the delivery environment is.
* **Text-file scenes and a small runtime.** `.tscn`/`.tres` are line-based, so component
  and board definitions diff and review like code, and an untethered Quest build lands
  well under the size and load time of an equivalent Unity IL2CPP build.
* **OpenXR is first-class** (`OpenXRInterface`, `XRController3D`, `OpenXRHand`), so the
  interaction layer targets Quest 3 controllers *and* hand tracking without a vendor SDK.

Everything below the interaction layer is engine-agnostic GDScript with no scene
dependencies, so the simulation and the error engine are testable with zero graphics.

## Layering

```
scenes/            VR interaction: grab, snap-wire, power switch, button press
    |
    v
bench/             Bench model: where parts sit, which tie point is which
    |
    v
sim/               Netlist, node resolution, power model, diagnostics  <-- pure logic
    |
    v
spec/              Board + component data (pin capability, limits, failure modes)
```

`sim/` never references a `Node3D`, a material, or an input action. It runs headless
under `tests/`, and the same calls drive the VR scene. If the tests pass, the physics
of the app is decided; the VR layer only reports what the kernel already computed.

## Core objects

**Terminal** — one electrically distinct attach point: a breadboard tie point, a rail
stud, a component lead, or a board pin. Terminals have stable string ids
(`bb:12:c`, `bb:rail:+:left`, `esp:gpio2`, `led1:A`) so netlists serialize and replay.

**Netlist** — the graph. Vertices are terminals, edges are *conductive joins* created by
three things: a jumper wire, a breadboard's internal tie groups, and a component's own
internal conduction. Edges carry the element that made them, so the diagnostics can say
*which* wire made the circuit wrong.

**Node resolution** — union-find over the netlist. Every terminal resolves to a node id.
Two terminals in one node are the same copper.

**Power model** — 5V (VIN), 3V3 (LDO out), and GND are source nodes. Voltage propagates
across conducting elements with forward drops and series resistance. Per-branch current
comes from Ohm's law against the accumulated series resistance, clamped by the pin's
drive capability and summed against the regulator budget.

**Diagnostics** — an ordered list of rules over (netlist, nodes, resolved voltages,
currents, firmware pin modes). Each finding carries a severity, the electrical reason,
and a concrete fix. `ERROR` blocks the power-on commit; `WARNING` and `INFO` do not.

## Power state machine

`OFF -> CHECKING -> ON`, with `ON -> TRIPPED` on an over-current fault.

Power-on is a *commit*, not a toggle. With the switch off the solver still runs in
low-voltage mode and the error engine has already flagged the fault, which is the whole
point: the app reads "5V on a 3.3V GPIO" while the board is cold, and the switch refuses
to close until errors are clear. So a broken circuit is diagnosed before power flows,
not after the magic smoke.

## Firmware model

The vertical slice ships one fixed sketch per scenario (blink on GPIO2) plus per-pin
mode selection: `INPUT`, `INPUT_PULLUP`, `OUTPUT`, `ADC`, `DAC`, `I2C`, `UART`, `PWM`.
Pin mode is an input to the solver, exactly as the real `pinMode()` call is: it decides
drive direction, current capability, and which conflict rules are even applicable.

## Conventions

* SI units, integer microvolts internally where a float would drift.
* `snake_case` files, `PascalCase` classes.
* Every electrical constant lives in `spec/` with a citation; no magic numbers in `sim/`.
* Every rule has an id (`E_RAIL_SHORT`, ...) that the tests assert on, so renaming a rule
  is a test failure rather than a silent coverage loss.
