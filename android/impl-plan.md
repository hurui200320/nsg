# Nikon Smart GPS (Android PoC) — Implementation Plan

## Goal
Build a minimal Android PoC that mimics the Nikon SnapBridge smart-device GPS flow.
The app will **not** use real GPS; instead it will generate a fake/random GPS + time payload on demand.
The main screen exposes three buttons:

1. **Pair** – scan for a Nikon camera in smart-device mode, run the Blowfish pairing handshake, and save the camera.
2. **Connect** – select a previously saved camera and reconnect using the persisted handshake data.
3. **Send** – when connected/paired, write a fake 41-byte GEO payload to the camera.

## Scope
- Target the protocol described in `doc/nikon-z-gps.md`.
- Use raw Android BLE APIs (no Nordic/Android-BLE-Library for this PoC).
- Use a foreground `Service` to own the BLE connection and state machine.
- Use a Compose UI with a `ViewModel` that binds to the service.
- Use `SharedPreferences` (with JSON strings) for persisting paired cameras.
- Request `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, `ACCESS_FINE_LOCATION`, and `POST_NOTIFICATIONS` at runtime.

---

## 1. UUID Constants

Base: `0000xxxx-3dd4-4255-8d62-6dc7b9bd5561`

| Name | Short | Full UUID |
|------|-------|-----------|
| Service | `0xDE00` | `0000de00-3dd4-4255-8d62-6dc7b9bd5561` |
| PAIR | `0x2000` | `00002000-3dd4-4255-8d62-6dc7b9bd5561` |
| NOT1 | `0x2008` | `00002008-3dd4-4255-8d62-6dc7b9bd5561` |
| ID | `0x2002` | `00002002-3dd4-4255-8d62-6dc7b9bd5561` |
| GEO | `0x2007` | `00002007-3dd4-4255-8d62-6dc7b9bd5561` |
| CCCD | `0x2902` | `00002902-0000-1000-8000-00805f9b34fb` |

Nikon manufacturer ID: `0x0399` (little-endian).

---

## 2. `AndroidManifest.xml` Additions

```xml
<uses-feature
    android:name="android.hardware.bluetooth_le"
    android:required="true" />

<uses-permission
    android:name="android.permission.BLUETOOTH_SCAN"
    android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />

<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE" />

<application ...>
    ...
    <service
        android:name=".service.CameraConnectionService"
        android:enabled="true"
        android:exported="false"
        android:foregroundServiceType="connectedDevice" />
</application>
```

Optional: add `RECEIVE_BOOT_COMPLETED` and a `BootReceiver` later if auto-start is needed.

---

## 3. Dependencies

Add to `gradle/libs.versions.toml`:

```toml
[versions]
coroutines = "1.8.1"
lifecycleService = "2.8.2"

[libraries]
kotlinx-coroutines-android = { group = "org.jetbrains.kotlinx", name = "kotlinx-coroutines-android", version.ref = "coroutines" }
androidx-lifecycle-service = { group = "androidx.lifecycle", name = "lifecycle-service", version.ref = "lifecycleService" }
```

Add to `app/build.gradle.kts`:

```kotlin
dependencies {
    ...
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.androidx.lifecycle.service)
}
```

---

## 4. Permissions Handling

Runtime permissions requested from the UI:

- `BLUETOOTH_SCAN`
- `BLUETOOTH_CONNECT`
- `ACCESS_FINE_LOCATION`
- `POST_NOTIFICATIONS` (Android 13+)

Also check:
- Bluetooth adapter enabled (request `ACTION_REQUEST_ENABLE` if not).
- Location system toggle enabled (required by some OEMs even with `BLUETOOTH_SCAN` + `neverForLocation`).

Permission rationale is shown before the request.

---

## 5. Architecture

```
MainActivity
  └── MainViewModel (binds to service, exposes UiState)
         └── CameraConnectionService (foreground service)
                ├── CameraBleManager (BluetoothGatt wrapper + callbacks)
                ├── NikonPairingEngine (Blowfish handshake logic)
                ├── GeoPayloadGenerator (fake 41-byte GEO payload)
                └── SettingsRepository (SharedPreferences)
```

The service owns the only `BluetoothGatt` instance and the current pairing state. The UI binds to the service, issues commands, and observes state/events.

---

## 6. Data Model

### `PairedCamera`

```kotlin
data class PairedCamera(
    val name: String,              // user-facing camera name
    val address: String,           // BLE MAC address
    val addressType: Int,          // BluetoothDevice.AddressType or BluetoothDevice.DEVICE_TYPE_* if available
    val device: Long,              // 4-byte device id, stored as uint32
    val nonce: Long,               // 4-byte nonce, stored as uint32
    val controllerName: String       // string written to ID characteristic
)
```

### `DiscoveredCamera`

```kotlin
data class DiscoveredCamera(
    val name: String,
    val address: String,
    val manufacturerData: ByteArray?,
    val isNew: Boolean             // true if not already in saved list
)
```

---

## 7. Persistence — `SettingsRepository`

Store the list of paired cameras as a `Set<String>` in `SharedPreferences`. Each entry is a JSON object built with the built-in `org.json.JSONObject`.

API:

```kotlin
class SettingsRepository(context: Context) {
    fun loadSavedCameras(): List<PairedCamera>
    fun saveCamera(camera: PairedCamera)
    fun removeCamera(camera: PairedCamera)
}
```

---

## 8. Blowfish / Pairing Handshake

### `BlowfishHasher`

Use `javax.crypto.Cipher` with transformation `"Blowfish/ECB/NoPadding"` and the 8-byte key:

```
FF FF AA 55 11 22 33 00
```

The hash function is a custom CBC-MAC-like loop. Each 64-bit block is packed as **big-endian** bytes, encrypted, and unpacked as **big-endian** 32-bit words.

```kotlin
class BlowfishHasher {
    private val cipher = Cipher.getInstance("Blowfish/ECB/NoPadding").apply {
        init(Cipher.ENCRYPT_MODE, SecretKeySpec(KEY, "Blowfish"))
    }

    fun hash(blocks: IntArray): Pair<Int, Int> {
        var left = 0x01020304
        var right = 0x05060708
        for (i in blocks.indices step 2) {
            var inL = blocks[i] xor left
            var inR = blocks[i + 1] xor right
            val enc = encryptBlock(inL, inR)
            left = enc.first
            right = enc.second
        }
        return Pair(left, right)
    }
}
```

### `NikonPairingEngine`

Encodes/decodes the 17-byte pairing messages and drives stages 1/3/5.

Message layout (little-endian on the wire):

| Byte | Field | Size |
|------|-------|------|
| 0 | stage | 1 |
| 1–8 | timestamp | 8 |
| 9–12 | device | 4 |
| 13–16 | nonce | 4 |

Stage 1:

- `timestamp` = random `uint64`
- `device` = random `uint32` with least significant byte `0x01`
- `nonce` = random `uint32`

Stage 2 verification:

- Split each timestamp into low 32 bits and high 32 bits.
- Convert each half from little-endian to big-endian using `Integer.reverseBytes()`.
- Hash input order for each salt: `[salt0, salt1, camLo, camHi, ourLo, ourHi]` (low half first, matching the furble reference).
- Try each of the 8 salts.
- Match: `h0 == reverseBytes(stage2.device)` and `h1 == reverseBytes(stage2.nonce)`.

Stage 3:

- Use the same salt but swap the timestamp order (our ts first, then camera ts).
- Hash input order: `[salt0, salt1, ourLo, ourHi, camLo, camHi]`.
- Compute `hash(...)` → `(r0, r1)`.
- `device = reverseBytes(r0)`, `nonce = reverseBytes(r1)`, `timestamp = stage1.timestamp`, `stage = 0x03`.
- This makes the little-endian wire bytes of `device`/`nonce` carry the big-endian representation of `r0`/`r1`, matching the furble reference.

Stage 5:

- All zeros except stage = `0x05`.

---

## 9. `CameraBleManager`

Implements `BluetoothGattCallback`. Responsibilities:

- Connect / disconnect / close.
- Discover services and validate required characteristics exist.
- Request MTU `517` (best effort; fallback if camera rejects).
- Enable **indications** on `PAIR` and **notifications** on `NOT1`.
- Write to `PAIR`, `ID`, and `GEO`.
- Emit events through a `BleListener` interface.

Events emitted:

```kotlin
sealed class BleEvent {
    data object Connected : BleEvent()
    data object Disconnected : BleEvent()
    data object ServicesDiscovered : BleEvent()
    data class MtuChanged(val mtu: Int) : BleEvent()
    data class PairIndication(val data: ByteArray) : BleEvent()
    data class Not1Notification(val data: ByteArray) : BleEvent()
    data class WriteDone(val uuid: UUID, val status: Int) : BleEvent()
    data class Error(val message: String) : BleEvent()
}
```

Important implementation notes:

- Use `BluetoothGattDescriptor.ENABLE_INDICATION_VALUE` for `PAIR`.
- Use `BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE` for `NOT1`.
- Write `PAIR` messages with `WRITE_TYPE_DEFAULT` (with response).
- The `ID` characteristic is written as a fixed 32-byte ASCII name (padded with zeros), matching SnapBridge behavior.
- The 41-byte `GEO` write relies on the MTU negotiation; if MTU is still 23, the write may fail and will need manual chunking (not implemented in this first pass).

---

## 10. `CameraConnectionService`

Extends `LifecycleService`. It is started as a foreground service when the user wants to interact with the camera.

State:

```kotlin
sealed class ConnectionState(val label: String) {
    data object Idle : ConnectionState("Idle")
    data object Scanning : ConnectionState("Scanning...")
    data object Connecting : ConnectionState("Connecting...")
    data object Discovering : ConnectionState("Discovering services...")
    data object Pairing : ConnectionState("Pairing...")
    data object Bonding : ConnectionState("Bluetooth Classic bonding...")
    data object Ready : ConnectionState("Ready")
    data object Busy : ConnectionState("Busy")
    data class Error(val reason: String) : ConnectionState("Error: $reason")
}
```

Exposed flows:

```kotlin
val state: StateFlow<ConnectionState>
val events: SharedFlow<String>          // one-off messages for the user
val discoveredCameras: StateFlow<List<DiscoveredCamera>>
val savedCameras: StateFlow<List<PairedCamera>>
```

Commands:

```kotlin
fun startPairingScan()
fun stopScan()
fun selectDiscoveredCamera(camera: DiscoveredCamera)   // pair to this new camera
fun connectToSavedCamera(camera: PairedCamera)         // reconnect handshake
fun disconnect()
fun sendFakeGeo()
```

Flow for **Pair**:

1. Start foreground service with a notification.
2. Start BLE scan filtered by the primary service UUID.
3. Show discovered cameras in the UI.
4. On user selection: stop scan, connect GATT, discover services, request MTU.
5. Enable `PAIR` indications and `NOT1` notifications.
6. Generate stage 1, write to `PAIR`.
7. Receive stage 2, verify salt, generate stage 3, write to `PAIR`.
8. Receive stage 4 (serial), write stage 5 to `PAIR`.
9. On some cameras (e.g. Coolpix B600) the camera sends a final `01 00` on `NOT1` after stage 5. On the Z50II this final OK is absent, so the app proceeds as soon as the stage 5 write is acknowledged.
10. Write controller name to `ID` as a fixed 32-byte ASCII field (unused bytes zeroed), matching SnapBridge / Z50II reference behavior.
10. When the BLE handshake begins, start classic Bluetooth discovery. The camera typically becomes visible to classic discovery only after the BLE handshake finishes.
11. After writing the controller name to `ID`, close the BLE GATT connection. This frees the camera for the classic Bluetooth pairing/system dialog, which does not reliably appear while the BLE connection is held.
12. When classic discovery finds the camera (by its name; the classic Bluetooth address is usually different from the BLE address), store that classic `BluetoothDevice` and call `createBond()` on it.
13. Listen for `ACTION_BOND_STATE_CHANGED` and wait for `BOND_BONDED` on either the BLE device or the discovered classic device (with a timeout fallback). If the system shows a pairing dialog, the user must accept it; the app will log the resulting bond state.
14. Listen for `ACTION_PAIRING_REQUEST` and log the pairing passkey so the user can confirm it in the system dialog. Auto-accepting via `setPairingConfirmation` is not possible on modern Android without `BLUETOOTH_PRIVILEGED`.
15. Once `BOND_BONDED` arrives while the BLE GATT is closed, save the camera and reconnect using the persisted stage-1 data, then run the handshake again to reach `Ready`.
16. Save camera to `SettingsRepository`.
17. Transition to `Ready`.

Flow for **Connect**:

1. Start foreground service.
2. Load selected saved camera.
3. Use the saved BLE address to `connectGatt`.
4. Same as steps 5–10 of the Pair flow (MTU, enable indications/notifications, handshake, ID write).
5. **Skip the bonding step.** Reconnect assumes the camera is already OS-paired; the bond is stored under the camera's classic Bluetooth address, so the BLE device object may report `BOND_NONE` even though the pairing is valid.
6. Transition to `Ready`.

Flow for **Send**:

1. If state is `Ready`, generate a fake 41-byte GEO payload.
2. Write it to `GEO` with response.
3. Emit a success or error event.

Bluetooth Classic bonding is handled by a dynamically registered `BroadcastReceiver` for:

- `BluetoothDevice.ACTION_BOND_STATE_CHANGED`
- `BluetoothDevice.ACTION_PAIRING_REQUEST`

Because the doc notes this step is not fully reverse-engineered, the service logs/waits for it but may require manual OS pairing by the user.

---

## 11. Fake GEO Payload

`GeoPayloadGenerator.buildFake()` returns exactly 41 bytes.

Fields:

| Offset | Size | Value |
|--------|------|-------|
| 0 | 2 | `0x007F` little-endian |
| 2 | 1 | lat direction `'N'` or `'S'` |
| 3 | 1 | lat degrees |
| 4 | 1 | lat minutes |
| 5 | 1 | lat submin1 |
| 6 | 1 | lat submin2 |
| 7 | 1 | lon direction `'E'` or `'W'` |
| 8 | 1 | lon degrees |
| 9 | 1 | lon minutes |
| 10 | 1 | lon submin1 |
| 11 | 1 | lon submin2 |
| 12 | 1 | satellites (3–12) |
| 13 | 1 | altitude ref `'P'` or `'M'` |
| 14 | 2 | altitude (absolute meters) little-endian |
| 16 | 7 | current UTC time (year LE, month, day, hour, minute, second) |
| 23 | 1 | subseconds (0–99) |
| 24 | 1 | valid `0x01` |
| 25 | 6 | `"WGS-84"` |
| 31 | 10 | `0x00` padding |

Coordinate conversion:

```kotlin
decimal = degrees + minutes/60 + submin1/6000 + submin2/600000
```

Example: lat = 34.123456 → `34° 07' 24"` style but encoded as two sub-minute bytes.

---

## 12. UI

### `MainActivity`

- Permission gate: if not all permissions granted, show a request button.
- Bluetooth enable gate: if adapter off, show an enable button.
- Main screen with:
  - Status text (current `ConnectionState`)
  - Event log (last few messages)
  - **Pair** button
  - **Connect** button
  - **Send** button (enabled only when `Ready`)
  - **Disconnect** button
- Dialogs:
  - `DiscoveredCameraDialog` for pairing selection.
  - `SavedCameraDialog` for reconnect selection.

### `MainViewModel`

- Binds/unbinds to `CameraConnectionService`.
- Exposes `UiState`:

```kotlin
data class UiState(
    val permissionsGranted: Boolean = false,
    val bluetoothEnabled: Boolean = false,
    val serviceConnected: Boolean = false,
    val connectionState: ConnectionState = ConnectionState.Idle,
    val lastEvents: List<String> = emptyList(),
    val showDiscoveredDialog: Boolean = false,
    val discoveredCameras: List<DiscoveredCamera> = emptyList(),
    val showSavedDialog: Boolean = false,
    val savedCameras: List<PairedCamera> = emptyList()
)
```

- Calls service methods on button clicks.

---

## 13. Notifications

Create a notification channel in `Application.onCreate()` or in `CameraConnectionService.onCreate()`.

The foreground notification shows:

- Current status label
- Disconnect action
- Tap to open the app

When `disconnect()` is called, remove the notification and stop the service.

---

## 14. Testing / Validation

- Unit tests for `BlowfishHasher` and `NikonPairingEngine` against a known/reference C implementation or manually verified values.
- `GeoPayloadGenerator` test: assert length == 41 and structure matches the spec.
- Build the app with `./gradlew :app:assembleDebug`.
- On-device test:
  1. Put Nikon Z in “Connect to smart device → Pairing”.
  2. Tap **Pair**, select camera, complete pairing.
  3. Tap **Send** repeatedly.
  4. Check camera GPS/location menu to see if the fake coordinates appear.
  5. Kill the app and tap **Connect** to verify saved data is reused.

---

## 15. Known Risks

- **Bluetooth Classic bonding**: The biggest unknown. The camera exposes a different classic Bluetooth address than its BLE address; the app must discover that classic address and bond it. After writing the ID characteristic the camera may need the BLE GATT to be closed before the system pairing dialog can appear. The app starts classic discovery during the handshake, closes the BLE GATT after the handshake, and bonds the discovered classic device. Manual OS pairing may still be required on some phones/cameras.
- **MTU / 41-byte GEO write**: If the camera refuses a larger MTU, the GEO write will fail. Mitigation: request MTU 517; if rejected, log it and stop.
- **Address type / resolvable random addresses**: Saved MAC addresses may not survive camera resets. Reconnect is implemented by saved address for the PoC; scanning for manufacturer data can be added later.
- **OEM-specific BLE/location quirks**: This is why we request `ACCESS_FINE_LOCATION` even though we don’t use real location.

---

## 16. File List

New files to create:

```
android/app/src/main/java/info/skyblond/nsp/
├── NikonSmartGpsApplication.kt
├── data/
│   ├── PairedCamera.kt
│   └── SettingsRepository.kt
├── ble/
│   ├── BleEvent.kt
│   ├── CameraBleManager.kt
│   ├── protocol/
│   │   ├── NikonPairingEngine.kt
│   │   ├── BlowfishHasher.kt
│   │   └── PairingMessage.kt
│   └── GeoPayloadGenerator.kt
├── service/
│   ├── CameraConnectionService.kt
│   └── ServiceState.kt
└── ui/
    ├── MainActivity.kt
    ├── MainViewModel.kt
    ├── PermissionHandler.kt
    ├── CameraDialogs.kt
    └── theme/
        ...existing
```

Files to modify:

```
android/app/src/main/AndroidManifest.xml
android/app/build.gradle.kts
android/gradle/libs.versions.toml
```
