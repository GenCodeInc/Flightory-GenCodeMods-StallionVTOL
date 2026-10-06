# FlightoryGenCodeMods — Stallion VTOL

Motor-mount modification and wingtip LED scripts for the Flightory Stallion VTOL. All files are in the repository root.

## Motor Mount

Modified front motor mount for the SPARKHOBBY / KINGMAX KM1203MD mini digital servo.

| File | Contents |
| --- | --- |
| `MOTOR MOUNT FRONT-LARGER-HORN-METAL.f3d` | Editable Fusion 360 design |
| `MOTOR MOUNT FRONT-LARGER-HORN-METAL.stl` | Printable mesh |

## Wingtip LED Scripts

Two SpeedyBee WS2812 boards, four LEDs per wing, controlled by a TBS Lucid H7 Wing running ArduPilot Lua through S13. No separate LED controller is used.

### stallion_led_nav.lua

- Left wing red; right wing green.
- All four LEDs on each wing show their navigation colour between flashes.
- Rear two LEDs per wing flash white twice; front two remain red/green.
- Full-brightness navigation colours and white strobes.
- Timing: 60 ms flash, 80 ms gap, 60 ms flash, 900 ms pause.
- Strobes run while disarmed by default.

### stallion_led_demo.lua

Four patterns run for five seconds each, then repeat:

1. **UFO orbit:** purple comet with a fading trail through all eight LEDs in data-chain order.
2. **Police pursuit:** alternating red/blue double flashes between wings.
3. **Rainbow chase:** moving rainbow colours across all eight LEDs.
4. **Reactor pulse:** cyan pulse with a white flash at the peak.

Brightness is controlled by `BRIGHTNESS` (0–255). The demo setting used for this build is `180`.

## LED Wiring

| Source | Destination |
| --- | --- |
| FC S13 | Left-wing DIN |
| Left-wing DOUT | Right-wing DIN, routed through the fuselage |
| Right-wing DOUT | Unconnected |
| Regulated 5 V | Both boards' positive inputs |
| Common ground | Both boards' negative inputs and FC ground |

DIN faces the front of each wing; DOUT faces the rear. The first four pixels are on the left wing, and the next four are on the right wing. The 5 V supply must support the LED load, including white flashes.

## Installation

1. Set `SCR_ENABLE = 1` and `SERVO13_FUNCTION = 94` (Script Out 1).
2. Copy either `stallion_led_nav.lua` or `stallion_led_demo.lua` into `APM/scripts` on the FC's SD card.
3. Remove any other script controlling these LEDs from that folder.
4. Reboot the FC.

Run only one LED script at a time. Filenames may be changed but must retain the `.lua` extension. The demo replaces the navigation-light pattern while installed.

## Credits

Original aircraft design: [Flightory](https://flightory.com/product/stallion/). Modifications: Ed Scott / GenCode. LED project inspired by Ralf Åhman's ESP32 navigation lights.

Original aircraft designs remain subject to the [Flightory License Agreement](https://flightory.com/license/). This repository contains modifications, not the complete aircraft plans.
