# NSG - ESP32 impl

## Hardware

Supported boards:
- **ESP32 WROOM 32E** with u-blox GNSS module — fully functional (serial-based pairing flow; no display)

> **M5Stack Core2 support has been removed.** The M5Stack Core2 board implementation
> (`src/boards/m5stack-core2/`, its environments in `platformio.ini`, and the 16 MB
> partition table) was removed to keep the project focused on custom hardware. If you
> need the Core2 code, it is preserved in the `core2-backup` tag:
> ```bash
> git fetch origin tag core2-backup
> git checkout core2-backup -- esp32/
> ```

Supported GNSS:
- u-blox NEO-M10 GPS module (or anything speaks the same protocol)

## Software approach

- Use PlatformIO with the Arduino framework.
- The firmware targets a single custom board (ESP32 WROOM 32E), so hardware-specific behavior — boot-mode detection on pin 19, RGB status LED, RTC handling, status logging — lives directly in the application code instead of behind a board abstraction layer.
- The core-1 `loop()` only processes GNSS UART + RTC time-sync and prints the status. All application-level BLE work (scan-queue handling, (re)connect/handshake, TIME/GEO broadcast) runs in a dedicated FreeRTOS task pinned to core 0 (`BleWorker`), so a (re)connect — which can block for up to 45s — never freezes the UI.
- Drain the GPS serial buffer at the start of every loop so no NMEA data is missed.

### Build environments

No `default_envs` is set — specify the environment explicitly:

| Environment | Board |
|---|---|
| `esp32-wroom-32e-release` / `esp32-wroom-32e-debug` | ESP32 WROOM 32E |
| `native` | Host machine (unit tests) |

Example: `pio run -e esp32-wroom-32e-release`

Setup:
+ Detect boot mode (NVS pairing flag from long-press, or short pin 19 to GND)
+ Call setup_pair() or setup_normal()

Setup Pair:
+ Initialize BLE scan
+ Pairing, saving
+ Exit (reboot)

Setup Normal:
+ Start BLE scan, set handler to filter device and check device in manufacture data, put device address to somewhere
+ Setup GPS, set GPS fix = false

Loop (core 1):
+ Process GPS output, save GPS location and fix, update RTC
+ Draw status screen
+ Push GNSS/RTC snapshot to the BLE worker

BLE worker task (core 0), one pass:
+ Block up to 1s for a scan result (the tick that also keeps the 30s broadcast timer running)
+ Watchdog: drop connected clients that have had no successful communication within the deadline
+ Send due TIME/GEO payloads to connected cameras (every 30s per camera); a failed write drops the whole client so its BLE slot is released
+ Process scan results: tear down disconnected clients and reconnect (retry-gated, at most one handshake per pass)
+ Refresh the BLE status snapshot, then resume scanning

Structure:
+ Snapshots (`src/normal/Snapshots.h`) — GNSS / RTC / BLE status data shared between the core-1 loop and the BLE worker
+ SavedCamera (camera name, device, nonce)
+ PendingCamera (camera name, address)
+ ConnectedCamera (camera name, last gps push)

## Modes

The device has two modes:

1. **Pairing mode** — enter by holding pin 19 (the exposed button) for 3 seconds in normal mode: the firmware writes an NVS flag and reboots into pairing mode, clearing the flag on the way in. Shorting pin 19 to GND during the 3-second boot detection window remains as a fallback (that window doubles as the RGB LED self-check: R, G, B each light up for one second). Scans for a new Nikon camera, runs the 4-stage BLE handshake, bonds over Bluetooth Classic, and saves the camera info. Holding the button for 3 seconds inside pairing mode reboots back to normal mode.
2. **Normal mode** — the default. Scans for saved cameras, reconnects when in range, and sends the 41-byte GPS payload to the camera whenever a fresh GPS fix is available. Should support multiple cameras connecting at the same time.

## BLE reconnection robustness

Cameras that disappear (switched off, standby, out of range) are handled without leaking BLE slots or hammering the radio (see issue #25):

- **Dead clients are destroyed, not just disconnected.** A zombie link can leave a client reporting `isConnected() == true` forever — the stack never delivers the disconnect event — so the client would hold its BLE slot until reboot and every later connect attempt is refused locally. On a failed TIME/GEO write the worker therefore destroys the whole client (`esp_ble_gattc_app_unregister` via the destructor), which releases the slot; the next advertisement produces a clean reconnect.
- **Per-camera retry gate.** A camera that keeps failing to (re)connect — or is skipped because all BLE slots are busy — is retried at most once per retry interval, counted from the end of the failed (or skipped) attempt, instead of on every advertisement (which was several hundred radio-heavy attempts per minute, degrading GNSS reception).
- **Payloads before connects.** Each pass sends due payloads before attempting new handshakes, and performs at most one handshake per pass, so a single ~45s connect attempt cannot starve already-connected cameras.
- **Liveness watchdog.** A connected client with no successful handshake or payload write within the deadline is treated as a zombie and destroyed. Before the GNSS time sync lands, connected cameras legitimately receive no payloads, so the deadline is tripled there and re-armed on the sync edge — a slow GNSS cold start does not drop healthy cameras, and a zombie still loses its slot eventually even if the GNSS never syncs (e.g. indoors).

Related build flags (defaults in the source headers — `src/normal/BleWorker.h` and `src/common/NikonBLEClient.h` — overridden in `platformio.ini`):

| Flag | Default | Meaning |
|---|---|---|
| `NIKON_BLE_CONNECT_RETRY_INTERVAL_MS` | 10000 | Min wait between reconnect attempts for the same camera |
| `NIKON_BLE_CLIENT_DEADLINE_MS` | 120000 | Max silence from a connected client before it is dropped (tripled until the GNSS time sync lands) |
| `NIKON_BLE_CONNECT_TIMEOUT_MS` | 45000 | Timeout for a single BLE (re)connect attempt |
| `NIKON_BLE_UPDATE_INTERVAL_MS` | 30000 | TIME/GEO broadcast interval per camera |

The ESP32 controller allows 3 simultaneous BLE connections by default (`CONFIG_BTDM_CTRL_BLE_MAX_CONN=3`). To serve more than three cameras at once, raise it (e.g. `CONFIG_BTDM_CTRL_BLE_MAX_CONN=4`) via the `custom_sdkconfig` section of `platformio.ini` — the reference build in issue #24 ran 4 cameras this way. (`CONFIG_BTDM_CONTROLLER_BLE_MAX_CONN` is a deprecated alias of this option that silently has no effect when set.)

## Status LED

The RGB status LED (`src/common/StatusLED.h`, global `statusLed`) is wired common anode — `STATUS_LED_ON = 0`, `STATUS_LED_OFF = 255`. Pin and level build flags: `STATUS_LED_PIN_R/G/B`, `STATUS_LED_ON/OFF`.

| Context | LED state |
|---|---|
| Boot self-check (GPIO-19 path) | R 1s → G 1s → B 1s, then off |
| Normal mode, no camera connected | G on |
| Normal mode, camera connected | G + B on |
| Pairing mode, scanning | R on |
| Pairing mode, handshake/pairing in progress | R + B on |
| Pairing mode, waiting for code confirmation on camera | R on, B blinking (1 Hz) |
| Pairing mode, fatal failure | R + G + B on (power cycle required) |

## RTC

The ESP32 WROOM 32E has no battery-backed external RTC, so it uses the chip's internal RTC with `TZ=GMT`. On cold boot the system clock reads 1970-01-01 until GNSS syncs it via `setRTC`. The `esp32-wroom-32e-*` environments select the internal 8.5 MHz oscillator divided by 256 (`CONFIG_RTC_CLK_SRC_INT_8MD256=y`) for better timekeeping accuracy at the cost of slightly higher deep-sleep current.
