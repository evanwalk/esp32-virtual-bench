# Spec provenance and conformance

Electrical rules are **not** invented here. The assignment makes Mechanic's electrical
spec binding. Until a rule is confirmed against Mechanic's spec it is marked
`PROVISIONAL` and the conformance table below tracks it.

## Status legend

* `CONFIRMED` — checked line-by-line against Mechanic's spec revision.
* `PROVISIONAL` — implemented from the ESP32 datasheet / Espressif TRM plus module
  convention, waiting on Mechanic's spec. Numbers are cited, behaviour is not guessed.
* `STUBBED` — the rule exists, the model behind it is a placeholder.

**Current state: Mechanic's spec has not landed in this thread, so every electrical
rule ships `PROVISIONAL` and cites a primary source.** Mechanic's spec wins wherever it
disagrees; the table is how we reconcile without a merge fight.

## Conformance table

| Rule id | Statement | Source | Status |
|---|---|---|---|
| `E_RAIL_SHORT_5V_GND` | 5V tied to GND by a zero-ohm path | Kirchhoff; any supply | PROVISIONAL |
| `E_RAIL_SHORT_3V3_GND` | 3V3 tied to GND by a zero-ohm path | as above | PROVISIONAL |
| `E_RAIL_SHORT_5V_3V3` | 5V rail bridged straight to 3V3 rail | LDO has no reverse path | PROVISIONAL |
| `E_5V_INTO_GPIO` | Node driven above 3.6 V on a 3.3 V GPIO | ESP32 DS §4.2 abs max, VDD+0.3 | PROVISIONAL |
| `E_INPUT_ONLY_DRIVEN` | GPIO 34–39 configured as output | ESP32 DS §4.1, input-only pins | PROVISIONAL |
| `E_STRAPPING_BOOT` | Strapping pin at boot-critical level (0/2/5/12/15) | ESP32 DS §4.3 boot strapping | PROVISIONAL |
| `E_ADC2_WIFI` | ADC2 pin used as analog while WiFi is active | Espressif TRM; ADC2 shared with radio | PROVISIONAL |
| `E_OVERCURRENT_PIN` | Branch current over the pin's safe source limit | ESP32 DS §4.2, 40 mA abs max / 12 mA sane | PROVISIONAL |
| `E_OVERCURRENT_REG` | Summed draw over the on-module regulator budget | AMS1117/DevKit convention, 500 mA | PROVISIONAL |
| `W_FLOATING_INPUT` | Input pin on a net with no defined source level | CMOS floating-input behaviour | PROVISIONAL |
| `E_NO_GROUND` | Powered circuit with no GND return to the board | Kirchhoff | PROVISIONAL |
| `W_LED_REVERSED` | LED anode/cathode reversed against the drive | LED polarity | PROVISIONAL |
| `W_LED_NO_RESISTOR` | LED branch with no series resistance | LED V-I curve | PROVISIONAL |
| `E_FLASH_PIN_USED` | GPIO 6–11 used | Wired to SPI flash on module | PROVISIONAL |
| `W_SERIES_R_TOLERANCE` | Series resistor outside the LED's sane band | LED derating | STUBBED |

## Numbers in force, and where they came from

| Quantity | Value | Source |
|---|---|---|
| GPIO logic high | 3.3 V (VDD) | ESP32 DS §4.2 |
| GPIO abs-max input | 3.6 V | ESP32 DS §4.2 |
| GPIO source/sink safe | 12 mA | DS note, conservative half of 40 mA abs max |
| GPIO abs-max current | 40 mA | ESP32 DS §4.2 |
| 3V3 regulator budget | 500 mA total board | DevKit schematic convention |
| LED forward drop (red) | 1.8 V | LED datasheet typical |
| LED forward drop (green/blue) | 2.8 / 3.0 V | LED datasheet typical |
| Brownout threshold | 2.5 V | ESP32 DS §5 |
| Soft power-on settle | 20 ms | model choice, documented |

## Known gaps (explicitly not modelled yet)

1. **Transient/inrush behaviour.** Current is steady-state only; a 100 µF cap on the rail
   does not smooth the first millisecond.
2. **Thermal derating.** A 12 mA pin at 85 °C is treated the same as at 20 °C.
3. **Inductive kickback.** Motor/relay coils are modelled as resistors, so no freewheel
   requirement is raised yet.
4. **Strapping timing.** The rule fires on the *level at boot*, not on a voltage that
   arrives after the boot window.
5. **Per-pin ADC attenuation and reference.** ADC rules fire on channel conflict and pin
   capability only; measured-value accuracy is out of scope for pre-flight.
6. **GPIO matrix / peripheral routing.** UART/I2C/PWM exist as pin modes but only their
   electrical effect is modelled, not the routing validity.
