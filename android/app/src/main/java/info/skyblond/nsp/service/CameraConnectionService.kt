package info.skyblond.nsp.service

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
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
                    if (device?.address != currentDevice?.address) return
                    val bondState = intent.getIntExtra(
                        BluetoothDevice.EXTRA_BOND_STATE,
                        BluetoothDevice.BOND_NONE
                    )
                    when (bondState) {
                        BluetoothDevice.BOND_BONDING -> updateState(ConnectionState.Bonding)
                        BluetoothDevice.BOND_BONDED -> onBonded()
                        BluetoothDevice.BOND_NONE -> logEvent("Bonding removed / failed")
                    }
                }

                BluetoothDevice.ACTION_PAIRING_REQUEST -> {
                    logEvent("Pairing request from camera - accept the OS dialog if shown")
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
        ContextCompat.registerReceiver(this, bondReceiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
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
            stopScan()
            currentDevice = bluetoothAdapter.getRemoteDevice(camera.address)
            controllerName = camera.name.take(12).ifEmpty { DEFAULT_CONTROLLER_NAME }
            connectCurrentDevice()
        }
    }

    fun connectToSavedCamera(camera: PairedCamera) {
        serviceScope.launch {
            pairingMode = PairingMode.RECONNECT
            savedCamera = camera
            currentDevice = bluetoothAdapter.getRemoteDevice(camera.address)
            controllerName = camera.controllerName
            connectCurrentDevice()
        }
    }

    fun disconnect() {
        serviceScope.launch {
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
                    updateState(ConnectionState.Discovering)
                }
                is BleEvent.ServicesDiscovered -> {
                    bleManager?.prepare()
                }
                is BleEvent.SubscriptionsEnabled -> {
                    updateState(ConnectionState.Pairing)
                    beginHandshake()
                }
                is BleEvent.MtuChanged -> {
                    logEvent("MTU changed to ${event.mtu}")
                }
                is BleEvent.PairIndication -> {
                    handlePairIndication(event.data)
                }
                is BleEvent.Not1Notification -> {
                    handleNot1Notification(event.data)
                }
                is BleEvent.WriteDone -> {
                    handleWriteDone(event.uuid, event.status)
                }
                is BleEvent.Disconnected -> {
                    updateState(ConnectionState.Error("Camera disconnected"))
                }
                is BleEvent.Error -> {
                    logEvent("BLE error: ${event.message}")
                    updateState(ConnectionState.Error(event.message))
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // Private helpers
    // -------------------------------------------------------------------------

    private fun connectCurrentDevice() {
        val device = currentDevice ?: return
        updateState(ConnectionState.Connecting)
        bleManager?.close()
        bleManager = CameraBleManager(this, this).also { it.connect(device) }
    }

    private fun beginHandshake() {
        currentStage1 = pairingEngine.createStage1(savedCamera)
        pairingStep = 1
        currentStage1?.let { bleManager?.writePairMessage(it.encode()) }
        logEvent("Sent pairing stage 1")
    }

    private fun handlePairIndication(data: ByteArray) {
        when (pairingStep) {
            1 -> {
                val stage2 = PairingMessage.decode(data)
                val stage3 = pairingEngine.verifyStage2AndBuildStage3(
                    currentStage1 ?: return,
                    stage2
                )
                if (stage3 == null) {
                    logEvent("Salt verification failed - handshake aborted")
                    updateState(ConnectionState.Error("Blowfish salt mismatch"))
                    return
                }
                bleManager?.writePairMessage(stage3.encode())
                pairingStep = 2
                logEvent("Sent pairing stage 3")
            }
            2 -> {
                val stage4 = PairingMessage.decode(data)
                val serial = pairingEngine.extractSerial(stage4)
                logEvent("Camera serial: $serial")
                bleManager?.writePairMessage(pairingEngine.buildStage5().encode())
                pairingStep = 3
                logEvent("Sent pairing stage 5")
            }
            else -> {
                logEvent("Unexpected PAIR indication in step $pairingStep")
            }
        }
    }

    private fun handleNot1Notification(data: ByteArray) {
        if (pairingStep == 3 && data.size >= 2 && data[0] == 0x01.toByte() && data[1] == 0x00.toByte()) {
            pairingStep = 4
            writeControllerId()
        } else {
            logEvent("NOT1: ${data.joinToString(" ") { "%02x".format(it) }}")
        }
    }

    private fun writeControllerId() {
        val nameBytes = controllerName.toByteArray(Charsets.US_ASCII).take(20).toByteArray()
        bleManager?.writeId(nameBytes)
        logEvent("Writing controller ID: $controllerName")
    }

    private fun handleWriteDone(uuid: java.util.UUID, status: Int) {
        if (status != android.bluetooth.BluetoothGatt.GATT_SUCCESS) {
            logEvent("Write failed on $uuid: status=$status")
            return
        }
        when (uuid) {
            CameraBleManager.ID_UUID -> {
                if (pairingStep == 4) {
                    pairingStep = 5
                    triggerBonding()
                }
            }
            CameraBleManager.GEO_UUID -> {
                updateState(ConnectionState.Ready)
                logEvent("Fake GEO sent successfully")
            }
            else -> Unit
        }
    }

    private fun triggerBonding() {
        val device = currentDevice ?: return
        updateState(ConnectionState.Bonding)
        if (device.bondState == BluetoothDevice.BOND_BONDED) {
            onBonded()
            return
        }
        try {
            @Suppress("MissingPermission")
            device.createBond()
        } catch (e: SecurityException) {
            updateState(ConnectionState.Error("Cannot create bond: ${e.message}"))
        }
    }

    private fun onBonded() {
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
        }
        pairingStep = 6
        updateState(ConnectionState.Ready)
        logEvent("Camera ready")
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
