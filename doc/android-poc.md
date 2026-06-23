# Nikon Smart GPS — Android PoC Notes

This document describes the Android-specific implementation details of the Nikon Smart GPS PoC. It complements `doc/nikon-z-gps.md`, which documents the protocol itself.

The PoC targets the **Nikon Z50 II** Bluetooth smart-device mode and sends fake/random GPS/time data to the camera.

---

## 1. Permissions

Runtime permissions requested at launch:

- `BLUETOOTH_SCAN`
- `BLUETOOTH_CONNECT`
- `ACCESS_FINE_LOCATION`
- `ACCESS_COARSE_LOCATION`
- `POST_NOTIFICATIONS` (Android 13+)

Manifest also declares `BLUETOOTH`, `BLUETOOTH_ADMIN`, `FOREGROUND_SERVICE`, and `FOREGROUND_SERVICE_CONNECTED_DEVICE`.

`ACCESS_FINE_LOCATION` is requested even though the app does not use real location, because some OEMs require it for Bluetooth Classic discovery.

---

## 2. Architecture

```
MainActivity
  └── MainViewModel
        └── CameraConnectionService (foreground Service)
              ├── CameraBleManager    (BluetoothGatt wrapper)
              ├── NikonPairingEngine  (Blowfish handshake)
              ├── GeoPayloadGenerator (fake 41-byte GEO payload)
              └── SettingsRepository  (SharedPreferences persistence)
```

The service owns the single `BluetoothGatt` instance and the pairing state machine. The UI binds to the service, observes `state`, `events`, `discoveredCameras`, and `savedCameras`, and issues commands.

---

## 3. Pair Flow

1. **Start foreground service** and show a persistent notification.
2. **BLE scan** filtered by the Nikon primary service UUID (`0000de00-3dd4-4255-8d62-6dc7b9bd5561`).
3. The user selects a discovered camera from the list.
4. **Connect BLE GATT**, discover services, negotiate MTU 517.
5. Enable **indications** on `PAIR` and **notifications** on `NOT1`.
6. Run the **5-stage Blowfish handshake**:
   - Stage 1: random timestamp + `device` (LSB `0x01`) + random `nonce`.
   - Stage 2: receive camera challenge, find matching salt.
   - Stage 3: send Blowfish response.
   - Stage 4: receive camera serial number.
   - Stage 5: send all-zero final message.
7. **Write controller name** to the `ID` characteristic as a fixed 32-byte ASCII field, zero-padded.
8. **Disconnect the BLE GATT** so the camera can switch to Bluetooth Classic bonding mode.
9. **Start Bluetooth Classic discovery** and wait for the camera to appear.
10. When the camera is found by name, call `createBond()` on the discovered **classic** `BluetoothDevice`.
11. The user confirms the numeric passkey in the system dialog.
12. On `BOND_BONDED`, save the camera and **reconnect over BLE**.
13. Run the handshake again with the saved `device`/`nonce` and transition to `Ready`.

### Important Android notes

- **Classic discovery must start during the handshake**, not after. The camera becomes visible to classic discovery only while/after the BLE handshake runs, but the 12-second discovery window may expire before the camera appears. The app restarts discovery automatically when it finishes.
- **Bond the classic address, not the BLE address.** The camera exposes a different classic BD-ADDR than its BLE random address. Bonding the BLE address fails; the bond that matters is on the classic address.
- **Auto-accept is not possible.** `BluetoothDevice.setPairingConfirmation()` requires `BLUETOOTH_PRIVILEGED`, which is only available to system apps. The app logs the passkey and relies on the user to confirm the dialog.
- **Z50II does not send the final `01 00` on `NOT1`.** The app proceeds as soon as the stage-5 write is acknowledged.
- **ID write does not always produce a callback.** The app waits for the callback but falls back after 3 seconds.

---

## 4. Connect Flow (Reconnect to Saved Camera)

1. Load the saved `PairedCamera`.
2. **Scan for the camera's current BLE address.** The camera uses a random BLE address that changes between sessions, so the saved address is only a last-known fallback.
3. When the camera is found by name + service UUID, update the saved address and connect.
4. Run the handshake with the saved `device`/`nonce`.
5. Write the controller name to `ID`.
6. **Skip bonding.** Reconnect assumes the camera is already OS-paired; forcing bonding again can drop the connection.
7. Transition to `Ready`.

### Persistence

- `SettingsRepository` keys cameras by **name**, not by address. The address is stored only as a fallback.
- Because the BLE address is random, the saved address is updated every time a reconnect scan succeeds.

---

## 5. Key Files

| File | Responsibility |
|------|----------------|
| `service/CameraConnectionService.kt` | Foreground service, state machine, bonding, reconnect scan. |
| `ble/CameraBleManager.kt` | GATT connect/disconnect, MTU, subscriptions, writes. |
| `ble/protocol/NikonPairingEngine.kt` | Pairing message encode/decode, salt search, handshake stages. |
| `ble/protocol/BlowfishHasher.kt` | JCE `Blowfish/ECB/NoPadding` block encryption. |
| `ble/GeoPayloadGenerator.kt` | Build the 41-byte fake GEO payload. |
| `data/SettingsRepository.kt` | Save/load paired cameras by name. |
| `ui/MainActivity.kt`, `MainViewModel.kt`, `CameraDialogs.kt` | Compose UI and service binding. |

---

## 6. Known Android Gotchas

| Issue | Mitigation |
|-------|------------|
| Classic discovery starts before the camera is visible | Start it early and restart automatically on `ACTION_DISCOVERY_FINISHED`. |
| Camera has separate classic and BLE addresses | Bond the device discovered via `ACTION_FOUND`, not the original BLE `BluetoothDevice`. |
| BLE GATT holds the connection during bonding | Disconnect the GATT after the `ID` write before expecting the system pairing dialog. |
| Pairing dialog must be manually confirmed | Log the passkey and rely on the user; auto-accept is blocked. |
| BLE address changes after camera restart | Reconnect scans for the current advertisement by name and updates the saved address. |
| BLE device object shows `BOND_NONE` even when paired | The OS bond is on the classic address; for reconnects, skip the bond check and proceed to `Ready`. |

---

## 7. Testing Checklist

- [ ] Put camera in **Connect to smart device → Pairing**.
- [ ] Tap **Pair**, select camera, complete handshake.
- [ ] Confirm numeric passkey in system dialog.
- [ ] Verify app reconnects and reaches `Ready`.
- [ ] Tap **Send** repeatedly and check camera GPS menu.
- [ ] Restart camera and app.
- [ ] Tap **Connect** and verify the saved camera is found by scan and reaches `Ready`.
- [ ] Tap **Send** and verify fake GPS is still accepted.
