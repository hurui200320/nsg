package info.skyblond.nsp.service

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
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
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.ParcelUuid
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import info.skyblond.nsp.MainActivity
import info.skyblond.nsp.R
import info.skyblond.nsp.ble.BleEvent
import info.skyblond.nsp.ble.CameraBleManager
import info.skyblond.nsp.ble.GeoPayloadGenerator
import info.skyblond.nsp.ble.protocol.NikonPairingEngine
import info.skyblond.nsp.ble.protocol.PairingMessage
import info.skyblond.nsp.data.DiscoveredCamera
import info.skyblond.nsp.data.PairedCamera
import info.skyblond.nsp.data.SettingsRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch

private const val TAG = "CameraConnectionService"

@SuppressLint("MissingPermission")
class CameraConnectionService : Service(), CameraBleManager.BleListener {

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private val binder = LocalBinder()

    private lateinit var settingsRepository: SettingsRepository
    private val pairingEngine = NikonPairingEngine()

    private val bluetoothManager by lazy { getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager }
    private val bluetoothAdapter by lazy { bluetoothManager.adapter }
    private val scanner by lazy { bluetoothAdapter.bluetoothLeScanner }

    private var bleManager: CameraBleManager? = null
    private var currentDevice: BluetoothDevice? = null
    private var savedCamera: PairedCamera? = null
    private var controllerName: String = DEFAULT_CONTROLLER_NAME

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
    private var reconnectScanCallback: ScanCallback? = null
    private var reconnectScanTimeoutJob: kotlinx.coroutines.Job? = null

    private val _state = MutableStateFlow<ConnectionState>(ConnectionState.Idle)
    val state: StateFlow<ConnectionState> = _state.asStateFlow()

    private val _events = MutableSharedFlow<String>(extraBufferCapacity = 10)
    val events: MutableSharedFlow<String> = _events

    private val _discoveredCameras = MutableStateFlow<List<DiscoveredCamera>>(emptyList())
    val discoveredCameras: StateFlow<List<DiscoveredCamera>> = _discoveredCameras.asStateFlow()

    private val _savedCameras = MutableStateFlow<List<PairedCamera>>(emptyList())
    val savedCameras: StateFlow<List<PairedCamera>> = _savedCameras.asStateFlow()

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
            logEvent("Scan failed: errorCode=$errorCode")
            updateState(ConnectionState.Error("Scan failed: $errorCode"))
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
                        BluetoothDevice.BOND_BONDING -> updateState(ConnectionState.Bonding)
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
                            Log.w(TAG, "Bonding failed for ${device.address}; waiting for discovery to find camera again")
                            logEvent("Bonding removed / failed")
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
                    logEvent("Pairing request from camera (passkey=$passkey) - confirm in system dialog")
                }
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        settingsRepository = SettingsRepository(this)
        refreshSavedCameras()
        createNotificationChannel()
        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
            addAction(BluetoothDevice.ACTION_PAIRING_REQUEST)
        }
        ContextCompat.registerReceiver(this, bondReceiver, filter, ContextCompat.RECEIVER_EXPORTED)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_DISCONNECT) {
            disconnect()
            stopSelf()
            return START_NOT_STICKY
        }
        startForeground(NOTIFICATION_ID, buildNotification())
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent): IBinder = binder

    override fun onDestroy() {
        super.onDestroy()
        try {
            unregisterReceiver(bondReceiver)
        } catch (_: IllegalArgumentException) {
            // already unregistered
        }
        bleManager?.close()
        serviceScope.cancel()
    }

    // -------------------------------------------------------------------------
    // Public commands
    // -------------------------------------------------------------------------

    fun startPairingScan() {
        serviceScope.launch {
            pairingMode = PairingMode.NEW
            savedCamera = null
            _discoveredCameras.value = emptyList()
            updateState(ConnectionState.Scanning)
            try {
                Log.d(TAG, "Starting BLE scan with Nikon service filter")
                val filter = ScanFilter.Builder()
                    .setServiceUuid(ParcelUuid(CameraBleManager.SERVICE_UUID))
                    .build()
                val settings = ScanSettings.Builder()
                    .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                    .build()
                scanner.startScan(listOf(filter), settings, scanCallback)
                // Stop scan automatically after 15 seconds.
                serviceScope.launch {
                    delay(15_000)
                    if (state.value is ConnectionState.Scanning) {
                        stopScan()
                        logEvent("Scan timed out")
                    }
                }
            } catch (e: SecurityException) {
                updateState(ConnectionState.Error("Missing permission: ${e.message}"))
            } catch (e: Exception) {
                updateState(ConnectionState.Error("Scan start failed: ${e.message}"))
            }
        }
    }

    fun stopScan() {
        serviceScope.launch {
            try {
                scanner.stopScan(scanCallback)
            } catch (_: Exception) {
            }
            if (state.value is ConnectionState.Scanning) {
                updateState(ConnectionState.Idle)
            }
        }
    }

    fun selectDiscoveredCamera(camera: DiscoveredCamera) {
        serviceScope.launch {
            Log.d(TAG, "selectDiscoveredCamera: ${camera.name} [${camera.address}]")
            stopScan()
            pairingMode = PairingMode.NEW
            savedCamera = null
            currentDevice = bluetoothAdapter.getRemoteDevice(camera.address)
            controllerName = DEFAULT_CONTROLLER_NAME
            connectCurrentDevice()
        }
    }

    fun connectToSavedCamera(camera: PairedCamera) {
        serviceScope.launch {
            Log.d(TAG, "connectToSavedCamera: ${camera.name} [${camera.address}]")
            pairingMode = PairingMode.RECONNECT
            savedCamera = camera
            controllerName = camera.controllerName
            // The camera changes its BLE (random) address between sessions. Scan for the
            // current advertisement by name before connecting; if the scan fails or times
            // out, fall back to the saved address.
            startReconnectScan(camera)
        }
    }

    @SuppressLint("MissingPermission")
    private fun startReconnectScan(camera: PairedCamera) {
        val scanner = this.scanner
        if (scanner == null) {
            Log.e(TAG, "BluetoothLeScanner is null, cannot start reconnect scan")
            currentDevice = bluetoothAdapter.getRemoteDevice(camera.address)
            connectCurrentDevice()
            return
        }
        updateState(ConnectionState.Connecting)
        logEvent("Scanning for saved camera...")
        reconnectScanTimeoutJob?.cancel()
        reconnectScanCallback?.let { try { scanner.stopScan(it) } catch (_: Exception) {} }

        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult?) {
                result ?: return
                val name = result.device.name
                if (name == camera.name) {
                    Log.d(TAG, "Reconnect scan found current BLE address: ${result.device.address} (saved was ${camera.address})")
                    reconnectScanTimeoutJob?.cancel()
                    reconnectScanCallback?.let { try { scanner.stopScan(it) } catch (_: Exception) {} }
                    reconnectScanCallback = null
                    // Update the persisted address so next time we can try directly first.
                    val updated = camera.copy(address = result.device.address)
                    settingsRepository.saveCamera(updated)
                    refreshSavedCameras()
                    savedCamera = updated
                    currentDevice = result.device
                    connectCurrentDevice()
                }
            }

            override fun onBatchScanResults(results: MutableList<ScanResult>?) {
                results?.forEach { onScanResult(ScanSettings.CALLBACK_TYPE_ALL_MATCHES, it) }
            }

            override fun onScanFailed(errorCode: Int) {
                Log.w(TAG, "Reconnect scan failed: errorCode=$errorCode")
                reconnectScanCallback = null
                currentDevice = bluetoothAdapter.getRemoteDevice(camera.address)
                connectCurrentDevice()
            }
        }
        reconnectScanCallback = callback
        val filter = ScanFilter.Builder()
            .setServiceUuid(ParcelUuid(CameraBleManager.SERVICE_UUID))
            .build()
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()
        try {
            scanner.startScan(listOf(filter), settings, callback)
            reconnectScanTimeoutJob = serviceScope.launch {
                delay(10_000)
                if (reconnectScanCallback != null) {
                    Log.w(TAG, "Reconnect scan timed out; using saved address as fallback")
                    try { scanner.stopScan(reconnectScanCallback!!) } catch (_: Exception) {}
                    reconnectScanCallback = null
                    currentDevice = bluetoothAdapter.getRemoteDevice(camera.address)
                    connectCurrentDevice()
                }
            }
        } catch (e: SecurityException) {
            updateState(ConnectionState.Error("Missing permission: ${e.message}"))
        } catch (e: Exception) {
            Log.w(TAG, "Reconnect scan start failed: ${e.message}", e)
            currentDevice = bluetoothAdapter.getRemoteDevice(camera.address)
            connectCurrentDevice()
        }
    }

    fun disconnect() {
        serviceScope.launch {
            idWriteTimeoutJob?.cancel()
            bondingTimeoutJob?.cancel()
            reconnectScanTimeoutJob?.cancel()
            reconnectScanCallback?.let { try { scanner.stopScan(it) } catch (_: Exception) {} }
            reconnectScanCallback = null
            stopClassicDiscovery()
            stopScan()
            bleManager?.disconnect()
            bleManager?.close()
            bleManager = null
            currentDevice = null
            currentStage1 = null
            pairingStep = 0
            updateState(ConnectionState.Idle)
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    fun sendFakeGeo() {
        serviceScope.launch {
            if (state.value != ConnectionState.Ready) {
                logEvent("Not ready - cannot send GPS")
                return@launch
            }
            val payload = GeoPayloadGenerator.buildFake()
            bleManager?.writeGeo(payload)
            updateState(ConnectionState.Busy)
            logEvent("Sending fake GEO payload (${payload.size} bytes)")
        }
    }

    // -------------------------------------------------------------------------
    // BLE callbacks
    // -------------------------------------------------------------------------

    override fun onEvent(event: BleEvent) {
        serviceScope.launch {
            when (event) {
                is BleEvent.Connected -> {
                    Log.d(TAG, "onEvent: Connected")
                    updateState(ConnectionState.Discovering)
                }
                is BleEvent.ServicesDiscovered -> {
                    Log.d(TAG, "onEvent: ServicesDiscovered")
                    bleManager?.prepare()
                }
                is BleEvent.SubscriptionsEnabled -> {
                    Log.d(TAG, "onEvent: SubscriptionsEnabled")
                    updateState(ConnectionState.Pairing)
                    beginHandshake()
                }
                is BleEvent.MtuChanged -> {
                    Log.d(TAG, "onEvent: MtuChanged mtu=${event.mtu}")
                    logEvent("MTU changed to ${event.mtu}")
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
                    } else {
                        updateState(ConnectionState.Error("Camera disconnected"))
                    }
                }
                is BleEvent.Error -> {
                    Log.e(TAG, "onEvent: Error ${event.message}")
                    if (isAwaitingBond) {
                        Log.d(TAG, "Ignoring BLE error while waiting for classic bond: ${event.message}")
                    } else {
                        logEvent("BLE error: ${event.message}")
                        updateState(ConnectionState.Error(event.message))
                    }
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // Private helpers
    // -------------------------------------------------------------------------

    private fun connectCurrentDevice() {
        val device = currentDevice ?: run {
            Log.w(TAG, "connectCurrentDevice: no current device")
            return
        }
        isAwaitingBond = false
        classicBondComplete = false
        classicDevice = null
        reconnectScanTimeoutJob?.cancel()
        reconnectScanCallback?.let { try { scanner.stopScan(it) } catch (_: Exception) {} }
        reconnectScanCallback = null
        Log.d(TAG, "connectCurrentDevice: ${device.address} (${device.name ?: "no name"}) bondState=${device.bondState}")
        updateState(ConnectionState.Connecting)
        bleManager?.close()
        bleManager = CameraBleManager(this, this).also { it.connect(device) }
    }

    private fun beginHandshake() {
        Log.d(TAG, "beginHandshake: generating stage 1 (mode=$pairingMode)")
        currentStage1 = pairingEngine.createStage1(savedCamera)
        pairingStep = 1
        currentStage1?.let {
            Log.d(TAG, "beginHandshake: stage 1 timestamp=${it.timestamp.toHexString()} device=${it.device.toHexString()} nonce=${it.nonce.toHexString()}")
            bleManager?.writePairMessage(it.encode())
        }
        logEvent("Sent pairing stage 1")
        // The camera becomes visible to classic Bluetooth discovery while/after the handshake.
        // Start discovery early so we can initiate createBond() from the phone side as soon as
        // the camera appears in the system device list.
        startClassicDiscovery()
    }

    private fun handlePairIndication(data: ByteArray) {
        Log.d(TAG, "handlePairIndication: step=$pairingStep data=${data.toHex()}")
        when (pairingStep) {
            1 -> {
                val stage2 = PairingMessage.decode(data)
                Log.d(TAG, "Received stage 2: timestamp=${stage2.timestamp.toHexString()} device=${stage2.device.toHexString()} nonce=${stage2.nonce.toHexString()}")
                val stage3 = pairingEngine.verifyStage2AndBuildStage3(
                    currentStage1 ?: return,
                    stage2
                )
                if (stage3 == null) {
                    Log.e(TAG, "Salt verification failed - handshake aborted")
                    logEvent("Salt verification failed - handshake aborted")
                    updateState(ConnectionState.Error("Blowfish salt mismatch"))
                    return
                }
                Log.d(TAG, "Sending stage 3: device=${stage3.device.toHexString()} nonce=${stage3.nonce.toHexString()}")
                bleManager?.writePairMessage(stage3.encode())
                pairingStep = 2
                logEvent("Sent pairing stage 3")
            }
            2 -> {
                val stage4 = PairingMessage.decode(data)
                val serial = pairingEngine.extractSerial(stage4)
                Log.d(TAG, "Received stage 4: serial='$serial' timestamp=${stage4.timestamp.toHexString()} raw=${data.toHex()}")
                logEvent("Camera serial: $serial")
                bleManager?.writePairMessage(pairingEngine.buildStage5().encode())
                pairingStep = 3
                logEvent("Sent pairing stage 5")
            }
            else -> {
                Log.w(TAG, "Unexpected PAIR indication in step $pairingStep")
                logEvent("Unexpected PAIR indication in step $pairingStep")
            }
        }
    }

    private fun handleNot1Notification(data: ByteArray) {
        Log.d(TAG, "handleNot1Notification: step=$pairingStep data=${data.toHex()}")
        val isSuccess = data.size >= 2 && data[0] == 0x01.toByte() && data[1] == 0x00.toByte()
        if (isSuccess) {
            Log.d(TAG, "Received success notification 01 00 on NOT1")
            if (pairingStep < 4) {
                idWriteTimeoutJob?.cancel()
                writeControllerId()
            } else {
                Log.d(TAG, "Success notification arrived while ID write already in progress")
            }
        } else {
            logEvent("NOT1: ${data.joinToString(" ") { "%02x".format(it) }}")
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
        logEvent("Writing controller ID: $controllerName")

        // Some cameras (notably Z50II) do not always acknowledge the ID write.
        // Proceed after a short timeout so we don't hang forever.
        idWriteTimeoutJob = serviceScope.launch {
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
            logEvent("Write failed on $uuid: status=$status")
            return
        }
        when (uuid) {
            CameraBleManager.PAIR_UUID -> {
                // Z50II does not always send the post-auth final OK on NOT1.
                // Give the camera a short moment before writing the ID, matching the reference.
                if (pairingStep == 3) {
                    Log.d(TAG, "Stage 5 write acknowledged, scheduling ID write in 200ms")
                    idWriteTimeoutJob?.cancel()
                    idWriteTimeoutJob = serviceScope.launch {
                        delay(200)
                        writeControllerId()
                    }
                }
            }
            CameraBleManager.ID_UUID -> {
                idWriteTimeoutJob?.cancel()
                if (pairingStep == 4) {
                    Log.d(TAG, "ID write confirmed, checking bond state")
                    pairingStep = 5
                    checkBondedAndFinish()
                }
            }
            CameraBleManager.GEO_UUID -> {
                updateState(ConnectionState.Ready)
                logEvent("Fake GEO sent successfully")
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
        // Reconnect mode assumes the camera was already paired with the OS. The BLE
        // device object often shows BOND_NONE because the actual bond is stored under the
        // camera's classic Bluetooth address, so we skip the bonding step for reconnects.
        if (pairingMode == PairingMode.RECONNECT) {
            Log.d(TAG, "Reconnect mode: skipping bonding check, proceeding to Ready")
            onBonded()
            return
        }
        // The camera's classic Bluetooth address is usually different from its BLE address.
        // We start classic discovery during the handshake and disconnect the BLE GATT after
        // the handshake so the classic pairing/system dialog can proceed. When the classic
        // device bonds, we reconnect on the BLE address and complete the flow.
        updateState(ConnectionState.Bonding)
        isAwaitingBond = true
        Log.d(TAG, "Not bonded yet; disconnecting BLE GATT to allow classic pairing")
        bleManager?.disconnect()
        bondingTimeoutJob?.cancel()
        bondingTimeoutJob = serviceScope.launch {
            delay(60_000)
            Log.w(TAG, "Bonding did not complete within 60s, proceeding anyway")
            isAwaitingBond = false
            stopClassicDiscovery()
            onBonded()
        }
        startClassicDiscovery()
    }

    private fun onBonded() {
        bondingTimeoutJob?.cancel()
        stopClassicDiscovery()
        isAwaitingBond = false
        Log.d(TAG, "onBonded: mode=$pairingMode")
        if (pairingMode == PairingMode.NEW && currentDevice != null && currentStage1 != null) {
            val camera = PairedCamera(
                name = currentDevice?.name ?: "Nikon",
                address = currentDevice?.address ?: return,
                addressType = currentDevice?.type ?: BluetoothDevice.DEVICE_TYPE_UNKNOWN,
                device = currentStage1?.device ?: return,
                nonce = currentStage1?.nonce ?: return,
                controllerName = controllerName
            )
            settingsRepository.saveCamera(camera)
            refreshSavedCameras()
            Log.d(TAG, "Saved paired camera: ${camera.name} [${camera.address}]")
        }
        pairingStep = 6
        updateState(ConnectionState.Ready)
        logEvent("Camera ready")
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
        savedCamera = PairedCamera(
            name = device.name ?: "Nikon",
            address = device.address,
            addressType = device.type,
            device = stage1.device,
            nonce = stage1.nonce,
            controllerName = controllerName
        )
        settingsRepository.saveCamera(savedCamera!!)
        refreshSavedCameras()
        connectCurrentDevice()
        classicBondComplete = true
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
                        if (isAwaitingBond || state.value == ConnectionState.Bonding) {
                            Log.d(TAG, "Discovery finished while still awaiting bond; restarting in 1s")
                            discoveryRestartJob?.cancel()
                            discoveryRestartJob = serviceScope.launch {
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
                        val foundName = intent.getStringExtra(BluetoothDevice.EXTRA_NAME)
                        Log.d(TAG, "Classic discovery found: ${found?.address} name=$foundName")
                        if (found == null) return
                        val target = currentDevice ?: return
                        // Match by address or name. The camera often advertises a different
                        // classic Bluetooth address than its BLE address, so we rely on the
                        // user-visible name.
                        if (found.address == target.address || foundName == target.name) {
                            Log.d(TAG, "Target camera found via classic discovery, creating bond")
                            classicDevice = found
                            stopClassicDiscovery()
                            @Suppress("MissingPermission")
                            val created = found.createBond()
                            Log.d(TAG, "createBond() from discovery returned $created")
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
        ContextCompat.registerReceiver(this, receiver, filter, ContextCompat.RECEIVER_EXPORTED)
        val started = adapter.startDiscovery()
        Log.d(TAG, "startDiscovery() returned $started")
        if (started) {
            logEvent("Searching for camera via Bluetooth discovery...")
        } else {
            Log.w(TAG, "startDiscovery() returned false, will retry in 2s")
            discoveryRestartJob?.cancel()
            discoveryRestartJob = serviceScope.launch {
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
                unregisterReceiver(it)
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
                "manufacturer=[${formatManufacturerData(record)}] " +
                "isConnectable=${result.isConnectable}"
        )

        if (hasNikonService) {
            Log.d(TAG, "[BLE SCAN] Nikon service UUID found on $address")
        }

        // Only add Nikon cameras to the UI list.
        if (!hasNikonService) {
            return
        }

        val saved = savedCameras.value
        val isNew = saved.none { it.address == result.device.address }
        val hasManData = (record?.manufacturerSpecificData?.size() ?: 0) > 0

        if (pairingMode == PairingMode.NEW && hasManData) {
            Log.w(
                TAG,
                "[BLE SCAN] Nikon camera $address has non-empty manufacturer data (likely already " +
                    "bonded to another phone). Skipping for pair scan."
            )
            return
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
                "services=$serviceUuids manufacturer=[${formatManufacturerData(record)}]"
        )
    }

    private fun formatManufacturerData(record: android.bluetooth.le.ScanRecord?): String {
        val data = record?.manufacturerSpecificData ?: return ""
        if (data.size() == 0) return "none"
        val sb = StringBuilder()
        for (i in 0 until data.size()) {
            val key = data.keyAt(i)
            val bytes = data.get(key) ?: continue
            sb.append("company=0x%04X ".format(key))
            sb.append(bytes.joinToString(" ") { "%02x".format(it) })
            if (i < data.size() - 1) sb.append("; ")
        }
        return sb.toString()
    }

    private fun refreshSavedCameras() {
        _savedCameras.value = settingsRepository.loadSavedCameras()
    }

    private fun logEvent(message: String) {
        _events.tryEmit(message)
    }

    private fun updateState(newState: ConnectionState) {
        _state.value = newState
        updateNotification()
    }

    // -------------------------------------------------------------------------
    // Notifications
    // -------------------------------------------------------------------------

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Camera Connection",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps the connection to the Nikon camera alive"
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_IMMUTABLE
        )
        val disconnectIntent = PendingIntent.getService(
            this,
            0,
            Intent(this, CameraConnectionService::class.java).apply {
                action = ACTION_DISCONNECT
            },
            PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Nikon Smart GPS")
            .setContentText(state.value.label)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentIntent(contentIntent)
            .addAction(R.drawable.ic_launcher_foreground, "Disconnect", disconnectIntent)
            .setOngoing(true)
            .build()
    }

    private fun updateNotification() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildNotification())
    }

    // -------------------------------------------------------------------------
    // Binder
    // -------------------------------------------------------------------------

    inner class LocalBinder : Binder() {
        val service: CameraConnectionService
            get() = this@CameraConnectionService
    }

    private enum class PairingMode { NEW, RECONNECT }

    companion object {
        const val ACTION_DISCONNECT = "info.skyblond.nsp.DISCONNECT"
        private const val CHANNEL_ID = "camera_connection_channel"
        private const val NOTIFICATION_ID = 1
        private const val DEFAULT_CONTROLLER_NAME = "nsg-poc"
    }
}

private fun ByteArray.toHex(): String =
    joinToString(" ") { "%02x".format(it) }

private fun Long.toHexString(): String =
    "0x%016x".format(this)
