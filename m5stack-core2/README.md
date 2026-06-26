# NSG - M5Stack Core2 impl

## Hardware

- M5Stack Core2 v1.1
- u-blox NEO-M9N GPS module

## Software approach

- Use PlatformIO with the Arduino framework and M5Unified.
- Keep the program in a single `loop()` with a state machine; FreeRTOS is not needed for the first version.
- Drain the GPS serial buffer at the start of every loop so no NMEA data is missed.

Setup:
+ Initialize touch screen, decide mode
+ Call setup_pair() or setup_normal()

Setup Pair:
+ Initialize BLE scan, set up screen
+ Pairing, saving
+ Exit (reboot)

Setup Normal:
+ Start BLE scan, set handler to filter device and check device in manufacture data, put device address to somewhere
+ Setup GPS, set GPS fix = false

Loop:
+ Process GPS output, save GPS location and fix, update RTC
+ Scan for pending device, do handshake for each one of them
+ For each connected device, check timer and send GPS payload (every minute or 30s?)
+ If got 0x80 or other error from camera, disconnect

Structure:
+ SavedCamera (camera name, device, nonce)
+ PendingCamera (camera name, address)
+ ConnectedCamera (camera name, last gps push)

## Modes

The device has two modes:

1. **Pairing mode** — run when the user taps a button during the 3-second boot splash. Scans for a new Nikon camera, runs the 4-stage BLE handshake, bonds over Bluetooth Classic, and saves the camera info.
2. **Normal mode** — the default. Scans for saved cameras, reconnects when in range, and sends the 41-byte GPS payload to the camera whenever a fresh GPS fix is available. Should support multiple cameras connecting at the same time.

## UI / power saving

- Show a simple status screen with GPS fix and connection status.
- Turn the screen backlight off after a timeout; wake it on touch or button press.
- Start with one camera; multi-camera support can be added later.

## Open tasks

- Implement the pairing and reconnect state machines.
- Test the first end-to-end connection with a Nikon Z camera.
