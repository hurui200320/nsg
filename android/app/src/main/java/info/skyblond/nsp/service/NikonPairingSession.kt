package info.skyblond.nsp.service

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.ParcelUuid
import android.util.Log
import androidx.core.content.ContextCompat
import info.skyblond.nsp.R
import info.skyblond.nsp.ble.BleEvent
import info.skyblond.nsp.ble.CameraBleManager
import info.skyblond.nsp.ble.protocol.NikonPairingEngine
import info.skyblond.nsp.ble.protocol.PairingMessage
import info.skyblond.nsp.ble.protocol.SnapBridgeIdSolver
import info.skyblond.nsp.data.DiscoveredCamera
import info.skyblond.nsp.data.PairedCamera
import info.skyblond.nsp.data.SettingsRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

private const val TAG = "NikonPairingSession"

/**
 * Owns the Bluetooth pairing state machine: BLE scanning, the Nikon handshake,
 * classic discovery/bonding, saved-camera reconnects and SnapBridge ID
 * auto-extraction. The service stays a thin shell around it.
 */
@SuppressLint("MissingPermission")
class NikonPairingSession(
    private val context: Context,
    private val scope: CoroutineScope,
    private val settings: SettingsRepository,
    private val host: Host
) : CameraBleManager.BleListener {

    /** Callbacks the session uses to poke the owning service. */
    interface Host {
        fun currentState(): ConnectionState
        fun updateState(state: ConnectionState)
        fun log(message: String)
        fun refreshSavedCameras()
        fun onSessionReady()
        fun onSessionDisconnected()
    }

    private val pairingEngine = NikonPairingEngine()
    private val bluetoothManager by lazy {
        context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    }
    private val bluetoothAdapter: BluetoothAdapter? by lazy { bluetoothManager.adapter }
    private val scanner: android.bluetooth.le.BluetoothLeScanner? by lazy {
        bluetoothAdapter?.bluetoothLeScanner
    }

    private var bleManager: CameraBleManager? = null
    private var currentDevice: BluetoothDevice? = null
    private var savedCamera: PairedCamera? = null
    private var controllerName: String = BleHelpers.DEFAULT_CONTROLLER_NAME
    private var currentStage1: PairingMessage? = null
    private var pairingStep = 0
    private var pairingMode = PairingMode.NEW
    private var idWriteTimeoutJob: kotlinx.coroutines.Job? = null
    private var bondingTimeoutJob: kotlinx.coroutines.Job? = null
    private var discoveryReceiver: BroadcastReceiver? = null
    private var discoveryRestartJob: kotlinx.coroutines.Job? = null
    private var isAwaitingBond: Boolean = false
    private var classicDevice: BluetoothDevice? = null
    private var classicBondComplete: Boolean = false
    private var reBondAfterRemoval: Boolean = false
    private var reconnectScanCallback: ScanCallback? = null
    private var adoptedDeviceId: Long? = null
    private var lastAdvertisedDevice: Long? = null
    private var stage1RetryCount = 0
    private var reconnectRetryCount = 0
    private var autoExtractActive = false
    private var autoExtractCamera: PairedCamera? = null
    private val autoExtractQueue = ArrayDeque<SnapBridgeIdSolver.Candidate>()
    private var autoExtractOriginalFixedId: String? = null
    private var classicDiscoveryRetryCount = 0

    private val _discoveredCameras = MutableStateFlow<List<DiscoveredCamera>>(emptyList())
    val discoveredCameras: StateFlow<List<DiscoveredCamera>> = _discoveredCameras.asStateFlow()

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult?) {
            result ?: return
            logScanResult(result, "ScanResult")
            handleScanResult(result)
        }

        override fun onBatchScanResults(results: MutableList<ScanResult>?) {
            results?.forEach {
                logScanResult(it, "BatchScanResult")
                handleScanResult(it)
            }
        }

        override fun onScanFailed(errorCode: Int) {
            Log.w(TAG, "Scan failed: errorCode=$errorCode")
            host.log(context.getString(R.string.log_scan_failed, errorCode))
            host.updateState(ConnectionState.Error("Scan failed: $errorCode"))
        }
    }

    private val bondReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                BluetoothDevice.ACTION_BOND_STATE_CHANGED -> {
                    val device = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                    }
                    if (device == null) return
                    val isRelevant = device.address == currentDevice?.address || device.address == classicDevice?.address
                    if (!isRelevant) return
                    val bondState = intent.getIntExtra(
                        BluetoothDevice.EXTRA_BOND_STATE,
                        BluetoothDevice.BOND_NONE
                    )
                    val previousBondState = intent.getIntExtra(
                        BluetoothDevice.EXTRA_PREVIOUS_BOND_STATE,
                        BluetoothDevice.BOND_NONE
                    )
                    Log.d(TAG, "Bond state changed for ${device.address}: $previousBondState -> $bondState")
                    when (bondState) {
                        BluetoothDevice.BOND_BONDING -> host.updateState(ConnectionState.Bonding)
                        BluetoothDevice.BOND_BONDED -> {
                            bondingTimeoutJob?.cancel()
                            if (device.address == classicDevice?.address) {
                                Log.d(TAG, "Classic Bluetooth device bonded; will use it for the BLE connection")
                                classicBondComplete = true
                            }
                            if (isAwaitingBond) {
                                Log.d(TAG, "Bonded while disconnected; reconnecting to complete handshake")
                                isAwaitingBond = false
                                stopClassicDiscovery()
                                reconnectAfterBonding()
                            } else if (pairingStep >= 5) {
                                onBonded()
                            } else {
                                Log.d(TAG, "Bonded before handshake completed, waiting for handshake")
                            }
                        }
                        BluetoothDevice.BOND_NONE -> {
                            if (reBondAfterRemoval) {
                                reBondAfterRemoval = false
                                Log.d(TAG, "Stale bond removed; creating fresh bond now")
                                @Suppress("MissingPermission")
                                val created = device.createBond()
                                Log.d(TAG, "createBond() after removal returned $created")
                                if (!created) {
            host.log(context.getString(R.string.log_repairing_manual_hint))
                                }
                                return
                            }
                            Log.w(TAG, "Bonding failed for ${device.address}; waiting for discovery to find camera again")
                            host.log(context.getString(R.string.log_pairing_removed_or_failed))
                        }
                    }
                }

                BluetoothDevice.ACTION_PAIRING_REQUEST -> {
                    val device = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                    }
                    val isRelevant = device != null && (device.address == currentDevice?.address || device.address == classicDevice?.address)
                    if (!isRelevant) return
                    val variant = intent.getIntExtra(BluetoothDevice.EXTRA_PAIRING_VARIANT, 0)
                    val key = intent.getIntExtra(BluetoothDevice.EXTRA_PAIRING_KEY, 0)
                    Log.d(TAG, "Pairing request from ${device?.address}: variant=$variant key=$key")
                    val passkey = String.format("%06d", key)
                    host.log(context.getString(R.string.log_camera_pairing_request, passkey))
                }
            }
        }
    }

    fun registerReceivers() {
        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
            addAction(BluetoothDevice.ACTION_PAIRING_REQUEST)
        }
        ContextCompat.registerReceiver(context, bondReceiver, filter, ContextCompat.RECEIVER_EXPORTED)
    }

    fun dispose() {
        try {
            context.unregisterReceiver(bondReceiver)
        } catch (_: IllegalArgumentException) {
            // already unregistered
        }
        bleManager?.close()
        bleManager = null
    }

    // -------------------------------------------------------------------------
    // Public commands (delegated from the service)
    // -------------------------------------------------------------------------

    fun startPairingScan() {
        scope.launch {
            pairingMode = PairingMode.NEW
            savedCamera = null
            adoptedDeviceId = null
            _discoveredCameras.value = emptyList()
            host.updateState(ConnectionState.Scanning)
            val bleScanner = scanner
            if (bleScanner == null) {
                host.log(context.getString(R.string.log_bluetooth_scanner_unavailable))
                host.updateState(ConnectionState.Error("Bluetooth scanner unavailable"))
                return@launch
            }
            try {
                Log.d(TAG, "Starting BLE scan with Nikon service filter")
                val filter = ScanFilter.Builder()
                    .setServiceUuid(ParcelUuid(CameraBleManager.SERVICE_UUID))
                    .build()
                val scanSettings = ScanSettings.Builder()
                    .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                    .build()
                bleScanner.startScan(listOf(filter), scanSettings, scanCallback)
                // Stop scan automatically after 15 seconds.
                scope.launch {
                    delay(15_000)
                    if (host.currentState() is ConnectionState.Scanning) {
                        stopScan()
                        host.log("Scan timed out")
                    }
                }
            } catch (e: SecurityException) {
                host.updateState(ConnectionState.Error("Missing permission: ${e.message}"))
            } catch (e: Exception) {
                host.updateState(ConnectionState.Error("Scan start failed: ${e.message}"))
            }
        }
    }

    fun stopScan() {
        scope.launch {
            try {
                scanner?.stopScan(scanCallback)
            } catch (_: Exception) {
            }
            if (host.currentState() is ConnectionState.Scanning) {
                host.updateState(ConnectionState.Idle)
            }
        }
    }

    /** Writes a GEO payload through the active BLE connection (used by the service). */
    fun writeGeo(payload: ByteArray) {
        bleManager?.writeGeo(payload)
    }

    fun selectDiscoveredCamera(camera: DiscoveredCamera) {
        scope.launch {
            Log.d(TAG, "selectDiscoveredCamera: ${camera.name} [${camera.address}]")
            stopScan()
            pairingMode = PairingMode.NEW
            savedCamera = null
            reconnectRetryCount = 0
            ensureSpoofName()
            val advertised = camera.manufacturerData?.let { BleHelpers.extractAdvertisedDeviceId(it) }
            val fixedDevice = settings.fixedDeviceId()
            if (advertised != null && fixedDevice != null && advertised != fixedDevice) {
                // The fixed identity no longer matches what the camera advertises (e.g. the
                // camera was re-paired with another device). Clear it so the auto-extraction
                // below can recover the correct identity instead of failing with status 133.
                host.log(
                    context.getString(
                        R.string.log_fixed_id_mismatch_reextract,
                        advertised,
                        fixedDevice
                    )
                )
                settings.setFixedDeviceId(null)
            }
            if (advertised != null && settings.fixedDeviceId() == null) {
                // The camera already has a pairing record (it advertises the device ID it
                // expects) - most likely SnapBridge's. Auto-crack the full SnapBridge
                // DeviceID and connect with it, so no record deletion is needed.
                host.log(
                    context.getString(R.string.log_paired_record_autocrack, advertised)
                )
                onAutoExtractCameraFound(
                    camera = PairedCamera(
                        name = camera.name,
                        address = camera.address,
                        addressType = BluetoothDevice.DEVICE_TYPE_LE,
                        device = advertised,
                        nonce = 0L,
                        controllerName = settings.spoofControllerName() ?: BleHelpers.DEFAULT_CONTROLLER_NAME
                    ),
                    advertisedDevice = advertised
                )
                return@launch
            }
            adoptedDeviceId = advertised
            if (advertised != null) {
                host.log(context.getString(R.string.log_paired_record_adopt, advertised))
            }
            currentDevice = remoteDevice(camera.address)
            controllerName = settings.spoofControllerName() ?: BleHelpers.DEFAULT_CONTROLLER_NAME
            connectCurrentDevice()
        }
    }

    fun connectToSavedCamera(camera: PairedCamera) {
        scope.launch {
            Log.d(TAG, "connectToSavedCamera: ${camera.name} [${camera.address}]")
            pairingMode = PairingMode.RECONNECT
            savedCamera = camera
            adoptedDeviceId = null
            reconnectRetryCount = 0
            ensureSpoofName()
            controllerName = camera.controllerName.ifBlank {
                settings.spoofControllerName() ?: BleHelpers.DEFAULT_CONTROLLER_NAME
            }
            // The camera changes its BLE (random) address between sessions. Scan for the
            // current advertisement by name before connecting; if the scan fails, fall
            // back to the saved address.
            startReconnectScan(camera)
        }
    }

    /**
     * Automatically fill the controller name the camera will display, using the exact
     * SnapBridge algorithm: "Android_" + sanitized Build.MODEL + "_%04d" random suffix.
     * Only generates once (persists), so it stays stable across sessions like SnapBridge.
     */
    private fun ensureSpoofName() {
        if (!settings.spoofControllerName().isNullOrBlank()) return
        val name = BleHelpers.generateSnapBridgeControllerName()
        settings.setSpoofControllerName(name)
        host.log(context.getString(R.string.log_controller_name_generated, name))
    }

    /**
     * Automatically recover the SnapBridge DeviceID that the camera has stored.
     *
     * SnapBridge seeds its 8-byte DeviceID with `new Random(System.currentTimeMillis())`
     * at first launch (see SnapBridgeIdSolver). The camera advertises the first 4 bytes,
     * which lets us invert the LCG and enumerate all possible seed timestamps. We then
     * connect to the camera with each candidate identity until the camera accepts one.
     */
    fun startAutoExtract(camera: PairedCamera) {
        scope.launch {
            if (autoExtractActive) {
                host.log(context.getString(R.string.log_autoextract_in_progress))
                return@launch
            }
            val installTime = snapBridgeInstallTime()
            if (installTime == null) {
                host.log(context.getString(R.string.log_snapbridge_not_found_cannot_extract, SNAPBRIDGE_PACKAGE))
                host.updateState(ConnectionState.Error(context.getString(R.string.error_snapbridge_not_installed)))
                return@launch
            }
            autoExtractCamera = camera
            autoExtractActive = true
            autoExtractQueue.clear()
            host.log(context.getString(R.string.log_snapbridge_install_time_scanning, BleHelpers.formatTimestamp(installTime)))
            scanForAutoExtract(camera)
        }
    }

    /** SnapBridge install time (milliseconds), or null if SnapBridge is not installed. */
    private fun snapBridgeInstallTime(): Long? = try {
        context.packageManager.getPackageInfo(SNAPBRIDGE_PACKAGE, 0).firstInstallTime
    } catch (_: PackageManager.NameNotFoundException) {
        null
    }

    private fun scanForAutoExtract(camera: PairedCamera) {
        val bleScanner = scanner
        if (bleScanner == null) {
            host.log(context.getString(R.string.log_bluetooth_scanner_unavailable))
            autoExtractActive = false
            return
        }
        host.updateState(ConnectionState.Scanning)
        reconnectScanCallback?.let { try { bleScanner.stopScan(it) } catch (_: Exception) {} }
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult?) {
                result ?: return
                val name = result.device.name
                val advertised = BleHelpers.extractAdvertisedDeviceId(result.scanRecord)
                val nameMatch = name != null && name == camera.name
                if (advertised == null && !nameMatch) {
                    return
                }
                Log.d(TAG, "Auto-extract scan found: ${result.device.address} name=$name advertised=$advertised")
                try { bleScanner.stopScan(this) } catch (_: Exception) {}
                reconnectScanCallback = null
                onAutoExtractCameraFound(
                    camera = camera.copy(address = result.device.address),
                    advertisedDevice = advertised ?: camera.device
                )
            }

            override fun onScanFailed(errorCode: Int) {
                Log.w(TAG, "Auto-extract scan failed: $errorCode")
                host.log(context.getString(R.string.log_autoextract_scan_failed, errorCode))
                autoExtractActive = false
                host.updateState(ConnectionState.Error(context.getString(R.string.log_scan_failed, errorCode)))
            }
        }
        reconnectScanCallback = callback
        val scanSettings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()
        try {
            bleScanner.startScan(emptyList(), scanSettings, callback)
            scope.launch {
                delay(30_000)
                if (autoExtractActive && reconnectScanCallback === callback) {
                    try { bleScanner.stopScan(callback) } catch (_: Exception) {}
                    reconnectScanCallback = null
                    autoExtractActive = false
                    host.log(context.getString(R.string.log_autoextract_no_advertisement))
                    host.updateState(ConnectionState.Idle)
                }
            }
        } catch (e: SecurityException) {
            host.log(context.getString(R.string.log_autoextract_missing_bt_permission))
            autoExtractActive = false
            host.updateState(ConnectionState.Error(context.getString(R.string.error_missing_bt_permission)))
        } catch (e: Exception) {
            host.log(context.getString(R.string.log_autoextract_scan_start_failed, e.message))
            autoExtractActive = false
        }
    }

    private fun onAutoExtractCameraFound(camera: PairedCamera, advertisedDevice: Long) {
        val installTime = snapBridgeInstallTime()
        if (installTime == null) {
            autoExtractActive = false
            autoExtractOriginalFixedId = null
            host.log(
                context.getString(R.string.log_snapbridge_not_found_install_first, SNAPBRIDGE_PACKAGE)
            )
            host.updateState(
                ConnectionState.Error(
                    context.getString(R.string.error_snapbridge_not_installed)
                )
            )
            return
        }
        // Remember the previous fixed ID so we can restore it if every candidate is rejected.
        autoExtractOriginalFixedId = settings.fixedDeviceIdRaw()
        val now = System.currentTimeMillis()
        host.log(context.getString(R.string.log_camera_advertises_id_solving, advertisedDevice))
        val candidates = SnapBridgeIdSolver.candidatesFor(advertisedDevice, installTime, now)
        if (candidates.isEmpty()) {
            host.log(context.getString(R.string.log_no_candidates_try_alltime))
            val all = SnapBridgeIdSolver.candidatesFor(advertisedDevice, 1_420_070_400_000L, now)
            if (all.isEmpty()) {
                host.log(context.getString(R.string.log_no_candidates_failed))
                autoExtractActive = false
                host.updateState(ConnectionState.Error(context.getString(R.string.error_no_candidate_device_id)))
                return
            }
            host.log(context.getString(R.string.log_alltime_candidates_count, all.size))
            autoExtractQueue.addAll(all)
        } else {
            host.log(context.getString(R.string.log_candidates_found, candidates.size))
            autoExtractQueue.addAll(candidates)
        }
        autoExtractCamera = camera
        currentDevice = remoteDevice(camera.address)
        savedCamera = camera
        testNextAutoExtractCandidate()
    }

    private fun testNextAutoExtractCandidate() {
        val candidate = autoExtractQueue.removeFirstOrNull()
        val camera = autoExtractCamera
        if (candidate == null || camera == null) {
            autoExtractActive = false
            // Restore the previous identity so a failed extraction does not leave a
            // wrong fixed ID behind that would break future connections.
            settings.setFixedDeviceId(autoExtractOriginalFixedId)
            autoExtractOriginalFixedId = null
            host.log(context.getString(R.string.log_all_candidates_rejected))
            host.updateState(ConnectionState.Idle)
            return
        }
        host.log(context.getString(R.string.log_testing_candidate, candidate.fixedIdentityHex, BleHelpers.formatTimestamp(candidate.seed)))
        settings.setFixedDeviceId(candidate.deviceIdHex)
        pairingMode = PairingMode.RECONNECT
        savedCamera = camera
        adoptedDeviceId = null
        controllerName = settings.spoofControllerName() ?: BleHelpers.DEFAULT_CONTROLLER_NAME
        currentDevice = remoteDevice(camera.address)
        connectCurrentDevice()
    }

    @SuppressLint("MissingPermission")
    private fun startReconnectScan(camera: PairedCamera) {
        val bleScanner = scanner
        if (bleScanner == null) {
            Log.e(TAG, "BluetoothLeScanner is null, cannot start reconnect scan")
            currentDevice = remoteDevice(camera.address)
            connectCurrentDevice()
            return
        }
        host.updateState(ConnectionState.Connecting)
        host.log(context.getString(R.string.log_scanning_saved_camera))
        reconnectScanCallback?.let { try { bleScanner.stopScan(it) } catch (_: Exception) {} }

        lastAdvertisedDevice = null
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult?) {
                result ?: return

                // Check name, we've already filtered for the manufacturer so if it doesn't match this is not our camera
                val name = result.device.name
                if (name != camera.name) {
                    Log.d(TAG, "Reconnect scan (other): ${result.device.address} name=$name rssi=${result.rssi}")
                    return
                }

                Log.d(
                    TAG,
                    "Reconnect scan candidate: ${result.device.address} name=$name rssi=${result.rssi} " +
                        "manufacturer=[${BleHelpers.formatManufacturerData(result.scanRecord)}]"
                )

                val advertised = BleHelpers.extractAdvertisedDeviceId(result.scanRecord)
                if (advertised != null) {
                    // The camera advertises the device ID it expects when a pairing record
                    // exists. Adopting it makes the camera treat this app as that device,
                    // so switching between SnapBridge and this app needs no record deletion.
                    if (advertised != lastAdvertisedDevice) {
                        lastAdvertisedDevice = advertised
                        host.log(
                            context.getString(
                                R.string.log_camera_found_expects_id,
                                advertised,
                                result.device.address,
                                result.rssi
                            )
                        )
                    }
                    if (settings.fixedDeviceId() != null) {
                        Log.d(TAG, "Fixed device ID configured, ignoring advertised ID $advertised")
                    } else if (advertised != camera.device) {
                        Log.d(
                            TAG,
                            "Adopting advertised device ID 0x%08X (saved was 0x%08X)".format(advertised, camera.device)
                        )
                        host.log(
                            context.getString(
                                R.string.log_device_id_mismatch_adopt,
                                camera.device,
                                advertised
                            )
                        )
                        val adopted = camera.copy(device = advertised)
                        settings.saveCamera(adopted)
                        host.refreshSavedCameras()
                        savedCamera = adopted
                    }
                }

                reconnectRetryCount = 0
                Log.d(TAG, "Reconnect scan found current BLE address: ${result.device.address} (saved was ${camera.address})")
                reconnectScanCallback?.let { try { bleScanner.stopScan(it) } catch (_: Exception) {} }
                reconnectScanCallback = null
                // Update the persisted address so next time we can try directly first.
                val updated = (savedCamera ?: camera).copy(address = result.device.address)
                settings.saveCamera(updated)
                host.refreshSavedCameras()
                savedCamera = updated
                currentDevice = result.device
                connectCurrentDevice()
            }

            override fun onBatchScanResults(results: MutableList<ScanResult>?) {
                results?.forEach { onScanResult(ScanSettings.CALLBACK_TYPE_ALL_MATCHES, it) }
            }

            override fun onScanFailed(errorCode: Int) {
                Log.w(TAG, "Reconnect scan failed: errorCode=$errorCode")
                reconnectScanCallback = null
                currentDevice = remoteDevice(camera.address)
                connectCurrentDevice()
            }
        }
        reconnectScanCallback = callback
        val scanSettings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_BALANCED)
            .build()
        try {
            // No service-UUID filter: the camera uses a fresh random BLE address between
            // sessions and may not always include the service UUID in its advertisement.
            // We filter on anything Nikon so we're allowed to scan while the screen is off.
            // We then match the advertised name in the callback to find this camera.
            val filter = ScanFilter.Builder()
                .setManufacturerData(
                    0x0399,
                    byteArrayOf(0),
                    byteArrayOf(0)
                )
                .build()
            bleScanner.startScan(listOf(filter), scanSettings, callback)
        } catch (e: SecurityException) {
            host.updateState(ConnectionState.Error("Missing permission: ${e.message}"))
        } catch (e: Exception) {
            Log.w(TAG, "Reconnect scan start failed: ${e.message}", e)
            currentDevice = remoteDevice(camera.address)
            connectCurrentDevice()
        }
    }

    /** Tears down the session (BLE, scans, timers); the service keeps its own cleanup. */
    fun disconnect() {
        if (autoExtractActive) {
            autoExtractActive = false
            autoExtractQueue.clear()
            settings.setFixedDeviceId(autoExtractOriginalFixedId)
            autoExtractOriginalFixedId = null
        }
        idWriteTimeoutJob?.cancel()
        bondingTimeoutJob?.cancel()
        reconnectScanCallback?.let { try { scanner?.stopScan(it) } catch (_: Exception) {} }
        reconnectScanCallback = null
        stopClassicDiscovery()
        stopScan()
        bleManager?.disconnect()
        bleManager?.close()
        bleManager = null
        currentDevice = null
        currentStage1 = null
        pairingStep = 0
        reBondAfterRemoval = false
    }

    private fun remoteDevice(address: String): BluetoothDevice? = bluetoothAdapter?.getRemoteDevice(address)

    // -------------------------------------------------------------------------
    // BLE callbacks
    // -------------------------------------------------------------------------

    override fun onEvent(event: BleEvent) {
        scope.launch {
            when (event) {
                is BleEvent.Connected -> {
                    Log.d(TAG, "onEvent: Connected")
                    host.updateState(ConnectionState.Discovering)
                }
                is BleEvent.ServicesDiscovered -> {
                    Log.d(TAG, "onEvent: ServicesDiscovered")
                    bleManager?.prepare()
                }
                is BleEvent.SubscriptionsEnabled -> {
                    Log.d(TAG, "onEvent: SubscriptionsEnabled")
                    host.updateState(ConnectionState.Pairing)
                    beginHandshake()
                }

                is BleEvent.MtuChanged -> {
                    Log.d(TAG, "onEvent: MtuChanged mtu=${event.mtu}")
                    host.log(context.getString(R.string.log_mtu_set, event.mtu))
                }
                is BleEvent.PairIndication -> {
                    Log.d(TAG, "onEvent: PairIndication ${event.data.size} bytes")
                    handlePairIndication(event.data)
                }
                is BleEvent.Not1Notification -> {
                    Log.d(TAG, "onEvent: Not1Notification ${event.data.size} bytes")
                    handleNot1Notification(event.data)
                }
                is BleEvent.WriteDone -> {
                    Log.d(TAG, "onEvent: WriteDone uuid=${event.uuid} status=${event.status}")
                    handleWriteDone(event.uuid, event.status)
                }
                is BleEvent.Disconnected -> {
                    Log.d(TAG, "onEvent: Disconnected")
                    if (isAwaitingBond) {
                        Log.d(TAG, "Disconnected while waiting for classic bond - keeping state")
                    } else if (reconnectScanCallback != null) {
                        Log.d(TAG, "Disconnected while reconnect scan in flight - keeping state")
                    } else {
                        host.updateState(ConnectionState.Error(context.getString(R.string.error_camera_disconnected)))
                    }
                    host.onSessionDisconnected()
                }
                is BleEvent.Error -> {
                    Log.e(TAG, "onEvent: Error ${event.message}")
                    if (isAwaitingBond) {
                        Log.d(TAG, "Ignoring BLE error while waiting for classic bond: ${event.message}")
                    } else if (
                        event.message.contains("Connection state change") &&
                        savedCamera != null &&
                        pairingMode == PairingMode.RECONNECT &&
                        reconnectRetryCount < 2
                    ) {
                        // The camera rejected the connection (usually status=133 because it
                        // expects a different device ID, e.g. SnapBridge's). Rescan: the
                        // camera advertises the ID it expects, and we adopt it automatically.
                        reconnectRetryCount++
                        host.log(
                            context.getString(R.string.log_connection_rejected_rescan, reconnectRetryCount)
                        )
                        savedCamera?.let { startReconnectScan(it) }
                    } else {
                        host.log(context.getString(R.string.log_bluetooth_error, event.message))
                        if (event.message.contains("Connection state change")) {
                            host.log(context.getString(R.string.log_cannot_connect_hint))
                        }
                        host.updateState(ConnectionState.Error(event.message))
                    }
                }
            }
        }
    }

    private fun connectCurrentDevice() {
        val device = currentDevice ?: run {
            Log.w(TAG, "connectCurrentDevice: no current device")
            return
        }
        isAwaitingBond = false
        classicBondComplete = false
        classicDevice = null
        reconnectScanCallback?.let { try { scanner?.stopScan(it) } catch (_: Exception) {} }
        reconnectScanCallback = null
        stage1RetryCount = 0
        Log.d(TAG, "connectCurrentDevice: ${device.address} (${device.name ?: "no name"}) bondState=${device.bondState}")
        host.updateState(ConnectionState.Connecting)
        bleManager?.close()
        bleManager = CameraBleManager(context, this).also { it.connect(device) }
    }

    private fun beginHandshake() {
        // SnapBridge authenticates first (stage 1-4); the controller name is written to
        // the ID characteristic only AFTER the handshake succeeds (see writeControllerId).
        // Writing it earlier makes the camera reject the write with status=128.
        sendStage1()
    }

    private fun sendStage1() {
        Log.d(TAG, "sendStage1: generating stage 1 (mode=$pairingMode)")
        // Priority: manually fixed ID > camera-advertised ID > saved ID > fresh random.
        // Pass the full identity (device + nonce) so a SnapBridge-compatible 16-hex-digit
        // fixed ID is honored end to end; the camera rejects writes otherwise.
        val fixedIdentity = settings.fixedIdentity()
        val override = fixedIdentity?.device ?: adoptedDeviceId
        currentStage1 = pairingEngine.createStage1(
            savedCamera,
            deviceOverride = override,
            nonceOverride = fixedIdentity?.nonce
        )
        pairingStep = 1
        currentStage1?.let {
            Log.d(TAG, "sendStage1: stage 1 timestamp=${it.timestamp.toHexString()} device=${it.device.toHexString()} nonce=${it.nonce.toHexString()} override=$override")
            bleManager?.writePairMessage(it.encode())
        }
        if (override != null) {
            host.log(context.getString(R.string.log_stage1_sent_fixed_id, override))
        } else {
            host.log(context.getString(R.string.log_stage1_sent))
        }
    }

    private fun handlePairIndication(data: ByteArray) {
        Log.d(TAG, "handlePairIndication: step=$pairingStep data=${data.toHex()}")
        when (pairingStep) {
            1 -> {
                if (autoExtractActive) {
                    autoExtractActive = false
                    autoExtractQueue.clear()
                    autoExtractOriginalFixedId = null
                    val fixed = settings.fixedDeviceIdRaw()
                    Log.d(TAG, "Auto-extract: camera accepted candidate $fixed")
                    host.log(
                        context.getString(
                            R.string.log_autoextract_success,
                            fixed?.uppercase() ?: "?"
                        )
                    )
                }
                val stage2 = PairingMessage.decode(data)
                Log.d(TAG, "Received stage 2: timestamp=${stage2.timestamp.toHexString()} device=${stage2.device.toHexString()} nonce=${stage2.nonce.toHexString()}")
                val stage3 = pairingEngine.verifyStage2AndBuildStage3(
                    currentStage1 ?: return,
                    stage2
                )
                if (stage3 == null) {
                    Log.e(TAG, "Salt verification failed - handshake aborted")
                    host.log(context.getString(R.string.log_salt_verification_failed))
                    host.updateState(ConnectionState.Error("Blowfish salt mismatch"))
                    return
                }
                Log.d(TAG, "Sending stage 3: device=${stage3.device.toHexString()} nonce=${stage3.nonce.toHexString()}")
                bleManager?.writePairMessage(stage3.encode())
                pairingStep = 2
                host.log(context.getString(R.string.log_stage3_sent))
            }
            2 -> {
                val stage4 = PairingMessage.decode(data)
                val serial = pairingEngine.extractSerial(stage4)
                Log.d(TAG, "Received stage 4: serial='$serial' timestamp=${stage4.timestamp.toHexString()} raw=${data.toHex()}")
                host.log(context.getString(R.string.log_camera_serial, serial))
                // SnapBridge/smart-device handshake does not send stage 5; the camera sends the
                // final 01 00 success notification on NOT1 after stage 4. Wait briefly for it;
                // if it does not arrive, write the controller ID anyway.
                pairingStep = 3
                idWriteTimeoutJob?.cancel()
                idWriteTimeoutJob = scope.launch {
                    delay(3_000)
                    if (pairingStep != 3) return@launch
                    Log.d(TAG, "No NOT1 success after stage 4, writing controller ID anyway")
                    writeControllerId()
                }
                Log.d(TAG, "Waiting for final OK on NOT1 before writing ID")
            }
            else -> {
                Log.w(TAG, "Unexpected PAIR indication in step $pairingStep")
                host.log(context.getString(R.string.log_unexpected_pairing_data, pairingStep))
            }
        }
    }

    private fun handleNot1Notification(data: ByteArray) {
        Log.d(TAG, "handleNot1Notification: step=$pairingStep data=${data.toHex()}")
        val isSuccess = data.size >= 2 && data[0] == 0x01.toByte() && data[1] == 0x00.toByte()
        if (isSuccess) {
            Log.d(TAG, "Received success notification 01 00 on NOT1")
            when (pairingStep) {
                3 -> {
                    idWriteTimeoutJob?.cancel()
                    writeControllerId()
                }
                4 -> {
                    idWriteTimeoutJob?.cancel()
                    Log.d(TAG, "Final OK received while waiting for ID write; proceeding")
                    pairingStep = 5
                    checkBondedAndFinish()
                }
                else -> {
                    Log.d(TAG, "Success notification ignored in step $pairingStep")
                }
            }
        } else {
            host.log("NOT1: ${data.joinToString(" ") { "%02x".format(it) }}")
        }
    }

    private fun writeControllerId() {
        if (pairingStep >= 4) {
            Log.d(TAG, "writeControllerId: already triggered or done, skipping")
            return
        }
        pairingStep = 4
        idWriteTimeoutJob?.cancel()

        // SnapBridge and the Z50II reference write a fixed 32-byte ASCII name.
        val nameBytes = controllerName.toByteArray(Charsets.US_ASCII)
        val padded = ByteArray(32) { 0x00 }
        val copyLen = minOf(nameBytes.size, padded.size)
        nameBytes.copyInto(padded, 0, 0, copyLen)
        Log.d(TAG, "writeControllerId: $controllerName -> ${padded.toHex()}")
        bleManager?.writeId(padded)
        host.log(context.getString(R.string.log_writing_controller_name, controllerName))

        // Some cameras (notably Z50II) do not always acknowledge the ID write.
        // Proceed after a short timeout so we don't hang forever.
        idWriteTimeoutJob = scope.launch {
            delay(3_000)
            Log.w(TAG, "ID write callback did not arrive in 3s, proceeding anyway")
            if (pairingStep == 4) {
                pairingStep = 5
                checkBondedAndFinish()
            }
        }
    }

    private fun handleWriteDone(uuid: java.util.UUID, status: Int) {
        Log.d(TAG, "handleWriteDone: uuid=$uuid status=$status step=$pairingStep")
        if (status != android.bluetooth.BluetoothGatt.GATT_SUCCESS) {
            Log.e(TAG, "Write failed on $uuid: status=$status")
            host.log(context.getString(R.string.log_write_failed, status))
            if (uuid == CameraBleManager.PAIR_UUID && pairingStep == 1) {
                if (autoExtractActive) {
                    Log.d(TAG, "Auto-extract: candidate rejected (status=$status), trying next")
                    host.log(context.getString(R.string.log_candidate_rejected_testing_next, status))
                    scope.launch {
                        delay(1_500)
                        testNextAutoExtractCandidate()
                    }
                    return
                }
                if (stage1RetryCount < 1 && reconnectRetryCount < 2) {
                    stage1RetryCount++
                    reconnectRetryCount++
                    host.log(context.getString(R.string.log_pairing_write_rejected_retry, status, reconnectRetryCount))
                    scope.launch {
                        delay(1_000)
                        if (pairingStep != 1) return@launch
                        if (bleManager?.isConnected == true) {
                            beginHandshake()
                        } else {
                            Log.d(TAG, "GATT disconnected during stage-1 retry; reconnecting first")
                            host.log(context.getString(R.string.log_disconnected_reconnecting))
                            connectCurrentDevice()
                        }
                    }
                    return
                }
                val bondState = currentDevice?.bondState
                val bondText = when (bondState) {
                    BluetoothDevice.BOND_BONDED -> context.getString(R.string.bond_state_paired)
                    BluetoothDevice.BOND_BONDING -> context.getString(R.string.bond_state_pairing)
                    else -> context.getString(R.string.bond_state_not_paired)
                }
                val fixed = settings.fixedIdentity()
                host.log(
                    context.getString(R.string.log_camera_rejected_pairing_write, status, bondText) +
                        (if (fixed?.nonce != null) {
                            context.getString(R.string.log_rejected_with_fixed_identity, fixed.device, fixed.nonce)
                        } else {
                            context.getString(R.string.log_pairing_rejected_checklist)
                        })
                )
                host.updateState(ConnectionState.Error("Pairing rejected by camera (status=$status)"))
            }
            return
        }
        when (uuid) {
            CameraBleManager.ID_UUID -> {
                idWriteTimeoutJob?.cancel()
                if (pairingStep == 4) {
                    Log.d(TAG, "ID write confirmed, checking bond state")
                    pairingStep = 5
                    checkBondedAndFinish()
                }
            }
            CameraBleManager.GEO_UUID -> {
                host.updateState(ConnectionState.Ready)
                host.log(context.getString(R.string.log_gps_write_success))
            }
            else -> Unit
        }
    }

    private fun checkBondedAndFinish() {
        val bleDevice = currentDevice ?: return
        val classicBonded = classicBondComplete || classicDevice?.bondState == BluetoothDevice.BOND_BONDED
        Log.d(TAG, "checkBondedAndFinish: mode=$pairingMode bleBondState=${bleDevice.bondState} classicBonded=$classicBonded")
        if (bleDevice.bondState == BluetoothDevice.BOND_BONDED || classicBonded) {
            onBonded()
            return
        }
        // The camera may already be paired with the OS under its classic Bluetooth
        // address (from SnapBridge or a previous session). The camera's classic name is
        // the controller name (e.g. "Android_MRR-W29_4909"), so match against it too.
        // Look it up in the bonded-device list before starting a fresh classic pairing.
        val bonded = bluetoothAdapter?.bondedDevices?.firstOrNull {
            BleHelpers.namesMatch(it.name, bleDevice.name) ||
                BleHelpers.namesMatch(it.name, savedCamera?.name) ||
                BleHelpers.namesMatch(it.name, controllerName)
        }
        if (bonded != null) {
            Log.d(TAG, "Found bonded classic device ${bonded.address} (${bonded.name})")
            classicDevice = bonded
            classicBondComplete = true
            onBonded()
            return
        }
        Log.d(TAG, "No bonded classic device found, running classic pairing")
        // The camera's classic Bluetooth address is usually different from its BLE address.
        // We start classic discovery during the handshake and disconnect the BLE GATT after
        // the handshake so the classic pairing/system dialog can proceed. When the classic
        // device bonds, we reconnect on the BLE address and complete the flow.
        host.updateState(ConnectionState.Bonding)
        isAwaitingBond = true
        Log.d(TAG, "Not bonded yet; disconnecting BLE GATT to allow classic pairing")
        bleManager?.disconnect()
        bondingTimeoutJob?.cancel()
        bondingTimeoutJob = scope.launch {
            delay(90_000)
            if (isAwaitingBond) {
                Log.w(TAG, "Bonding did not complete within 90s")
                host.log(context.getString(R.string.log_pairing_timeout))
                isAwaitingBond = false
                stopClassicDiscovery()
                host.updateState(ConnectionState.Error("Classic bonding timed out"))
            }
        }
        // Give the camera a moment to switch to classic mode after the BLE handshake
        // before scanning for it over classic Bluetooth.
        scope.launch {
            delay(1_500)
            if (isAwaitingBond) startClassicDiscovery()
        }
    }

    private fun onBonded() {
        bondingTimeoutJob?.cancel()
        stopClassicDiscovery()
        isAwaitingBond = false
        Log.d(TAG, "onBonded: mode=$pairingMode")
        if (currentDevice != null && currentStage1 != null) {
            val camera = PairedCamera(
                name = currentDevice?.name ?: "Nikon",
                address = currentDevice?.address ?: return,
                addressType = currentDevice?.type ?: BluetoothDevice.DEVICE_TYPE_UNKNOWN,
                device = currentStage1?.device ?: return,
                nonce = currentStage1?.nonce ?: return,
                controllerName = controllerName
            )
            settings.saveCamera(camera)
            host.refreshSavedCameras()
            Log.d(TAG, "Saved paired camera: ${camera.name} [${camera.address}]")
        }
        pairingStep = 6
        host.updateState(ConnectionState.Ready)
        host.onSessionReady()
        host.log(context.getString(R.string.log_camera_ready))
    }

    @SuppressLint("MissingPermission")
    private fun reconnectAfterBonding() {
        val device = currentDevice ?: run {
            Log.w(TAG, "reconnectAfterBonding: no current device")
            return
        }
        val stage1 = currentStage1 ?: run {
            Log.w(TAG, "reconnectAfterBonding: no stage 1 data")
            return
        }
        Log.d(TAG, "reconnectAfterBonding: ${device.address} using saved stage 1 data")
        pairingMode = PairingMode.RECONNECT
        val newCamera = PairedCamera(
            name = device.name ?: "Nikon",
            address = device.address,
            addressType = device.type,
            device = stage1.device,
            nonce = stage1.nonce,
            controllerName = controllerName
        )
        savedCamera = newCamera
        settings.saveCamera(newCamera)
        host.refreshSavedCameras()
        connectCurrentDevice()
        classicBondComplete = true
    }

    @SuppressLint("MissingPermission")
    private fun removeBondCompat(device: BluetoothDevice): Boolean {
        // BluetoothDevice.removeBond() is a hidden API; call it via reflection.
        return try {
            val method = BluetoothDevice::class.java.getMethod("removeBond")
            method.invoke(device) as? Boolean ?: false
        } catch (e: Exception) {
            Log.w(TAG, "removeBond via reflection failed: ${e.message}")
            false
        }
    }

    @SuppressLint("MissingPermission")
    private fun startClassicDiscovery() {
        val adapter = bluetoothAdapter
        if (adapter == null) {
            Log.e(TAG, "BluetoothAdapter is null, cannot start classic discovery")
            return
        }
        if (adapter.isDiscovering) {
            Log.d(TAG, "Classic discovery already running")
            return
        }
        // Clean up any previous receiver.
        stopClassicDiscovery()
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                when (intent.action) {
                    BluetoothAdapter.ACTION_DISCOVERY_STARTED -> {
                        Log.d(TAG, "Classic discovery started")
                    }
                    BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
                        Log.d(TAG, "Classic discovery finished")
                        if (isAwaitingBond || host.currentState() == ConnectionState.Bonding) {
                            Log.d(TAG, "Discovery finished while still awaiting bond; restarting in 1s")
                            discoveryRestartJob?.cancel()
                            discoveryRestartJob = scope.launch {
                                delay(1_000)
                                startClassicDiscovery()
                            }
                        }
                    }
                    BluetoothDevice.ACTION_FOUND -> {
                        val found = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                        } else {
                            @Suppress("DEPRECATION")
                            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                        }
                        val foundName = intent.getStringExtra(BluetoothDevice.EXTRA_NAME) ?: found?.name
                        Log.d(TAG, "Classic discovery found: ${found?.address} name=$foundName")
                        if (found == null) return
                        val target = currentDevice ?: return
                        // The camera often advertises a different classic Bluetooth address
                        // than its BLE address, so match by name (with a fuzzy match, since
                        // some ROMs report a slightly different name over classic discovery).
                        if (found.address == target.address || BleHelpers.namesMatch(foundName, target.name)) {
                            Log.d(TAG, "Target camera found via classic discovery, creating bond")
                            classicDevice = found
                            stopClassicDiscovery()
                            if (found.bondState == BluetoothDevice.BOND_BONDED) {
                                if (pairingMode == PairingMode.NEW) {
                                    // The camera never confirmed this stale bond (no 6-digit code
                                    // was ever shown on the camera), so it is not a valid pairing.
                                    // Remove it and re-pair from scratch so the system dialog and
                                    // the camera passkey prompt both appear.
                                    Log.w(TAG, "NEW mode found stale bond on ${found.address}; removing to re-pair")
                                    host.log(context.getString(R.string.log_stale_pairing_removing))
                                    reBondAfterRemoval = true
                                    classicDevice = found
                                    bondingTimeoutJob?.cancel()
                                    bondingTimeoutJob = scope.launch {
                                        delay(15_000)
                                        if (isAwaitingBond && classicDevice == found && reBondAfterRemoval) {
                                            host.log(context.getString(R.string.log_stale_pairing_remove_timeout))
                                        }
                                    }
                                    @Suppress("MissingPermission")
                                    val removed = removeBondCompat(found)
                                    Log.d(TAG, "removeBond() returned $removed")
                                    if (!removed) {
                                        reBondAfterRemoval = false
                                        host.log(context.getString(R.string.log_stale_pairing_remove_failed))
                                    }
                                    return
                                }
                                Log.d(TAG, "Camera already bonded, skipping createBond")
                                host.log(context.getString(R.string.log_camera_paired_continuing))
                                classicBondComplete = true
                                isAwaitingBond = false
                                // The BLE GATT link was dropped after the handshake; reconnect
                                // before reporting Ready so the GPS channel actually works.
                                reconnectAfterBonding()
                                return
                            }
                            host.log(context.getString(R.string.log_found_camera_requesting_pairing, foundName ?: found.address))
                            bondingTimeoutJob?.cancel()
                            bondingTimeoutJob = scope.launch {
                                delay(20_000)
                                if (isAwaitingBond && classicDevice == found) {
                                                    host.log(context.getString(R.string.log_pairing_request_not_confirmed))
                                }
                            }
                            @Suppress("MissingPermission")
                            val created = found.createBond()
                            Log.d(TAG, "createBond() from discovery returned $created")
                            if (!created) {
                                bondingTimeoutJob?.cancel()
                                classicDiscoveryRetryCount++
                                if (classicDiscoveryRetryCount >= MAX_CLASSIC_RETRIES) {
                                    Log.w(TAG, "createBond kept failing, giving up classic pairing")
                                    host.log(
                                        context.getString(R.string.log_repeated_pairing_failures)
                                    )
                                    isAwaitingBond = false
                                    stopClassicDiscovery()
                                    host.updateState(ConnectionState.Error(context.getString(R.string.error_classic_pairing_failed)))
                                    return
                                }
                                scope.launch {
                                    delay(3_000)
                                    if (isAwaitingBond && classicDevice == found) {
                                        Log.w(TAG, "createBond returned false, retrying discovery")
                                        host.log(context.getString(R.string.log_pairing_request_failed_retry))
                                        // Re-arm the pairing timeout for this retry.
                                        bondingTimeoutJob?.cancel()
                                        bondingTimeoutJob = scope.launch {
                                            delay(20_000)
                                            if (isAwaitingBond && classicDevice == found) {
                                                host.log(context.getString(R.string.log_pairing_request_not_confirmed))
                                            }
                                        }
                                        startClassicDiscovery()
                                    }
                                }
                            } else {
                                classicDiscoveryRetryCount = 0
                            }
                        } else {
                            Log.d(TAG, "Ignoring non-camera device: $foundName (${found.address})")
                        }
                    }
                }
            }
        }
        discoveryReceiver = receiver
        val filter = IntentFilter().apply {
            addAction(BluetoothAdapter.ACTION_DISCOVERY_STARTED)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
            addAction(BluetoothDevice.ACTION_FOUND)
        }
        ContextCompat.registerReceiver(context, receiver, filter, ContextCompat.RECEIVER_EXPORTED)
        val started = adapter.startDiscovery()
        Log.d(TAG, "startDiscovery() returned $started")
        if (started) {
            host.log(context.getString(R.string.log_searching_camera_bt))
        } else {
            Log.w(TAG, "startDiscovery() returned false, will retry in 2s")
            discoveryRestartJob?.cancel()
            discoveryRestartJob = scope.launch {
                delay(2_000)
                startClassicDiscovery()
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun stopClassicDiscovery() {
        discoveryRestartJob?.cancel()
        discoveryReceiver?.let {
            try {
                context.unregisterReceiver(it)
            } catch (_: IllegalArgumentException) {
                // already unregistered
            }
            discoveryReceiver = null
        }
        bluetoothAdapter?.takeIf { it.isDiscovering }?.cancelDiscovery()
    }

    private fun handleScanResult(result: ScanResult) {
        val record = result.scanRecord
        val name = result.device.name ?: "<no name>"
        val address = result.device.address ?: "<no address>"
        val serviceUuids = record?.serviceUuids?.map { it.uuid.toString() } ?: emptyList()
        val hasNikonService = record?.serviceUuids?.any { it.uuid == CameraBleManager.SERVICE_UUID } == true

        Log.d(
            TAG,
            "[BLE SCAN] name=$name address=$address rssi=${result.rssi} " +
                "services=$serviceUuids " +
                "manufacturer=[${BleHelpers.formatManufacturerData(record)}] " +
                "isConnectable=${result.isConnectable}"
        )

        if (hasNikonService) {
            Log.d(TAG, "[BLE SCAN] Nikon service UUID found on $address")
        }

        // Only add Nikon cameras to the UI list.
        if (!hasNikonService) {
            return
        }

        val saved = settings.loadSavedCameras()
        val isNew = saved.none { it.address == result.device.address }
        val hasManData = (record?.manufacturerSpecificData?.size() ?: 0) > 0

        if (hasManData) {
            val advertised = BleHelpers.extractAdvertisedDeviceId(record)
            if (advertised != null && advertised != lastAdvertisedDevice) {
                lastAdvertisedDevice = advertised
                Log.d(TAG, "[BLE SCAN] Camera $address advertises known device ID=0x%08X".format(advertised))
                if (pairingMode == PairingMode.NEW) {
                    host.log(context.getString(R.string.log_found_paired_camera_switch, advertised))
                }
            }
        }

        val discovered = DiscoveredCamera(result, isNew)
        val current = _discoveredCameras.value.toMutableList()
        if (current.none { it.address == discovered.address }) {
            current.add(discovered)
            _discoveredCameras.value = current
            Log.d(TAG, "[BLE SCAN] Added ${discovered.name} (${discovered.address}) to UI list")
        }
    }

    private fun logScanResult(result: ScanResult, source: String) {
        val record = result.scanRecord
        val name = result.device.name ?: "<no name>"
        val address = result.device.address ?: "<no address>"
        val serviceUuids = record?.serviceUuids?.map { it.uuid.toString() } ?: emptyList()
        Log.v(
            TAG,
            "[$source] name=$name address=$address rssi=${result.rssi} " +
                "services=$serviceUuids manufacturer=[${BleHelpers.formatManufacturerData(record)}]"
        )
    }

    private enum class PairingMode { NEW, RECONNECT }

    private companion object {
        const val SNAPBRIDGE_PACKAGE = "com.nikon.snapbridge.cmru"
        const val MAX_CLASSIC_RETRIES = 3
    }
}
