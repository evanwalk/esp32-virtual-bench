## Board spec: ESP32-DevKitC-V1 class module (38-pin, ESP32-WROOM-32).
##
## Board data is pure data: capabilities, strapping roles, ADC channels, and limits.
## The solver reads it; nothing here knows about VR or rendering.
##
## Sources: Espressif ESP32 datasheet §4.1-4.3 (pin functions, abs max, strapping),
## ESP32-WROOM-32 datasheet (flash pin usage), DevKitC-V1 schematic (rail names,
## regulator). All numbers PROVISIONAL pending Mechanic's binding spec — see
## docs/SPEC-PROVENANCE.md.
class_name BoardSpec
extends RefCounted

const BoardSpec_ := true

## Capability tags used by rules and by the VR pin picker.
const CAP_DIGITAL := "digital"
const CAP_OUTPUT := "output"
const CAP_INPUT := "input"
const CAP_ADC := "adc"
const CAP_DAC := "dac"
const CAP_PWM := "pwm"
const CAP_I2C := "i2c"
const CAP_UART := "uart"
const CAP_TOUCH := "touch"
const CAP_STRAP := "strap"
const CAP_FLASH := "flash"
const CAP_INPUT_ONLY := "input_only"

## Electrical limits (microvolts / milliamps / microamps).
const VDD_UV := 3_300_000
const VIN_UV := 5_000_000
const GPIO_ABS_MAX_UV := 3_600_000
const GPIO_SOURCE_MA_SAFE := 12
const GPIO_ABS_MAX_MA := 40
const REG_BUDGET_MA := 500
const BROWNOUT_UV := 2_500_000
const LOGIC_HIGH_MIN_UV := 2_475_000   # 0.75 * VDD
const LOGIC_LOW_MAX_UV := 825_000      # 0.25 * VDD
const INPUT_LEAK_UA := 1
const GPIO_SERIES_OHM := 25

var id := ""
var display_name := ""
## gpio number -> { caps: Array[String], adc: int, strap_level: int }
var _pins: Dictionary = {}
## Strapping pins and the level required at boot for normal flash boot.
## 1 = must be high at boot, 0 = must be low, -1 = don't-care/other boot mode.
var strap_expected: Dictionary = {}

const _ADC1 := {36: 0, 37: 1, 38: 2, 39: 3, 32: 4, 33: 5, 34: 6, 35: 7, 25: 8, 26: 9, 27: 7}
const _ADC2 := {4: 0, 0: 1, 2: 2, 15: 3, 13: 4, 12: 5, 14: 6, 27: 7, 25: 8, 26: 9}

func _init() -> void:
	id = "esp32-devkitc-v1"
	display_name = "ESP32-DevKitC V1 (38-pin)"

	# Plain digital GPIO.
	_add_pin(4, [CAP_DIGITAL, CAP_INPUT, CAP_OUTPUT, CAP_PWM, CAP_TOUCH])
	_add_pin(13, [CAP_DIGITAL, CAP_INPUT, CAP_OUTPUT, CAP_PWM, CAP_TOUCH])
	_add_pin(14, [CAP_DIGITAL, CAP_INPUT, CAP_OUTPUT, CAP_PWM, CAP_TOUCH])
	_add_pin(27, [CAP_DIGITAL, CAP_INPUT, CAP_OUTPUT, CAP_PWM, CAP_TOUCH])
	_add_pin(32, [CAP_DIGITAL, CAP_INPUT, CAP_OUTPUT, CAP_PWM, CAP_TOUCH])
	_add_pin(33, [CAP_DIGITAL, CAP_INPUT, CAP_OUTPUT, CAP_PWM, CAP_TOUCH])
	# DAC-capable pins.
	_add_pin(25, [CAP_DIGITAL, CAP_INPUT, CAP_OUTPUT, CAP_DAC, CAP_PWM])
	_add_pin(26, [CAP_DIGITAL, CAP_INPUT, CAP_OUTPUT, CAP_DAC, CAP_PWM])
	# Input-only pins: no output driver.
	for g in [34, 35, 36, 37, 38, 39]:
		_add_pin(g, [CAP_DIGITAL, CAP_INPUT, CAP_INPUT_ONLY, CAP_TOUCH])
	# Flash pins: bonded to the SPI flash die on a module.
	for g in [6, 7, 8, 9, 10, 11]:
		_add_pin(g, [CAP_FLASH])
	# UART0 console.
	_add_pin(1, [CAP_DIGITAL, CAP_INPUT, CAP_OUTPUT, CAP_UART])
	_add_pin(3, [CAP_DIGITAL, CAP_INPUT, CAP_OUTPUT, CAP_UART])
	# I2C default pins.
	_add_pin(21, [CAP_DIGITAL, CAP_INPUT, CAP_OUTPUT, CAP_I2C, CAP_PWM])
	_add_pin(22, [CAP_DIGITAL, CAP_INPUT, CAP_OUTPUT, CAP_I2C, CAP_PWM])
	# Strapping pins.
	_add_pin(0, [CAP_DIGITAL, CAP_INPUT, CAP_OUTPUT, CAP_STRAP, CAP_PWM])
	_add_pin(2, [CAP_DIGITAL, CAP_INPUT, CAP_OUTPUT, CAP_STRAP, CAP_PWM])
	_add_pin(5, [CAP_DIGITAL, CAP_INPUT, CAP_OUTPUT, CAP_STRAP, CAP_PWM])
	_add_pin(12, [CAP_DIGITAL, CAP_INPUT, CAP_OUTPUT, CAP_STRAP, CAP_PWM])
	_add_pin(15, [CAP_DIGITAL, CAP_INPUT, CAP_OUTPUT, CAP_STRAP, CAP_PWM])
	# ADC channels are a property of the silicon, added for every capable pin.
	for g in _ADC1:
		if _pins.has(g):
			_pins[g]["caps"].append(CAP_ADC)
	strap_expected = {0: 1, 2: 1, 5: 1, 12: 0, 15: 1}

func _add_pin(g: int, caps: Array) -> void:
	_pins[g] = {
		"caps": caps.duplicate(),
		"adc1": _ADC1.get(g, -1),
		"adc2": _ADC2.get(g, -1),
		"strap_level": -1,
	}

func _adc1_channel(g: int) -> int:
	return _ADC1.get(g, -1)

func _adc2_channel(g: int) -> int:
	return _ADC2.get(g, -1)

func has_gpio(g: int) -> bool:
	return _pins.has(g)

func caps(g: int) -> Array:
	return _pins.get(g, {}).get("caps", [])

func can(g: int, cap: String) -> bool:
	return caps(g).has(cap)

func is_input_only(g: int) -> bool:
	return can(g, CAP_INPUT_ONLY)

func is_flash_pin(g: int) -> bool:
	return can(g, CAP_FLASH)

func is_strapping(g: int) -> bool:
	return can(g, CAP_STRAP)

func adc1_channel(g: int) -> int:
	return _pins.get(g, {}).get("adc1", -1)

func adc2_channel(g: int) -> int:
	return _pins.get(g, {}).get("adc2", -1)

func gpio_numbers() -> Array:
	var out: Array = _pins.keys()
	out.sort()
	return out

## Every GPIO that can actually be driven/read (excludes flash pins).
func usable_gpios() -> Array:
	var out: Array = []
	for g in gpio_numbers():
		if not is_flash_pin(g):
			out.append(g)
	return out
