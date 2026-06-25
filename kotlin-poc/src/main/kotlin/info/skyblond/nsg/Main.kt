package info.skyblond.nsg

import com.welie.blessed.*
import info.skyblond.nsg.Const.GEO_CHAR_UUID
import info.skyblond.nsg.Const.NIKON_SERVICE_UUID
import info.skyblond.nsg.Const.TIME_CHAR_UUID
import info.skyblond.nsg.protocol.GeoPayloadGenerator
import info.skyblond.nsg.protocol.TimePayloadGenerator
import org.slf4j.LoggerFactory
import java.util.*
import kotlin.random.Random
import kotlin.system.exitProcess

val logger = LoggerFactory.getLogger("Application")

// paired camera should reuse device and nonce
// note: for BLE, each time camera gives a random address
//       but the classic bluetooth address is fixed
// keep these as null to initiate pairing
//val pairedDevice: Pair<Long, Long>? = null
// z50II
 val pairedDevice: Pair<Long, Long>? = Pair(2564355329, 794005425)
// z8
//val pairedDevice: Pair<Long, Long>? = Pair(2321449473, 1474676721)

fun main() {
    var central: BluetoothCentralManager? = null
    var cameraName: String? = null

    val bluetoothCentralManagerCallback = object : BluetoothCentralManagerCallback() {
        override fun onDiscoveredPeripheral(
            peripheral: BluetoothPeripheral,
            scanResult: ScanResult
        ) {
            val hasManufacturerData = scanResult.manufacturerData.isNotEmpty()
            logger.info(
                "Discovered device {}, addr: {}, manufacturer data: {}",
                peripheral.name, peripheral.address,
                formatManufacturerData(scanResult)
            )

            if (pairedDevice == null && !hasManufacturerData) {
                // we don't have paired device and the camera is also pairing (no manufacturer data)
                central?.stopScan()
                cameraName = scanResult.name ?: peripheral.name
                central?.connectPeripheral(
                    peripheral, NikonPeripheralCallback(
                        device = null, nonce = null, disconnectAfterHandshake = true
                    )
                )
            }
            if (pairedDevice != null && hasManufacturerData && verifyManufacturerData(
                    scanResult, pairedDevice.first
                )
            ) {
                // we have paired device and the camera is also looking for us
                central?.stopScan()
                central?.connectPeripheral(
                    peripheral, NikonPeripheralCallback(
                        device = pairedDevice.first,
                        nonce = pairedDevice.second,
                        disconnectAfterHandshake = false
                    ) { peripheral ->
                        Thread {
                            logger.info("Start sending fake GPS...")
                            while (peripheral.state == ConnectionState.CONNECTED) {
                                val timeBytes = TimePayloadGenerator.buildPackage()
                                peripheral.writeCharacteristic(
                                    NIKON_SERVICE_UUID, TIME_CHAR_UUID,
                                    timeBytes,
                                    BluetoothGattCharacteristic.WriteType.WITH_RESPONSE
                                )
                                Thread.sleep(1000)
                                val lat = Random.nextDouble(-90.0, 90.0)
                                val lon = Random.nextDouble(-180.0, 180.0)
                                val alt = Random.nextInt(-1000, 5000)
                                val satellites = Random.nextInt(3, 13)
                                val geoBytes = GeoPayloadGenerator.buildPackage(lat, lon, alt, satellites)
                                logger.info(
                                    "Sending fake GPS: lat={}, lon={}, alt={}, satellites={}, bytes={}",
                                    lat, lon, alt, satellites, geoBytes.toHex(" ")
                                )
                                peripheral.writeCharacteristic(
                                    NIKON_SERVICE_UUID, GEO_CHAR_UUID,
                                    geoBytes,
                                    BluetoothGattCharacteristic.WriteType.WITH_RESPONSE
                                )
                                Thread.sleep(2_000)
                            }
                        }.start()
                    }
                )
            }

        }

        override fun onDisconnectedPeripheral(
            peripheral: BluetoothPeripheral,
            status: BluetoothCommandStatus
        ) {
            logger.info(
                "Disconnected from {} ({}), status: {}",
                peripheral.name, peripheral.address, status
            )
            if (pairedDevice == null && cameraName != null) {
                logger.info("Starting classic bond for camera '{}'", cameraName)
                Thread({
                    try {
                        val classicAddress = createClassicBond(cameraName)
                        logger.info("Classic bond successful: {}", classicAddress)
                    } catch (e: Exception) {
                        logger.error("Classic bond failed", e)
                    } finally {
                        exitProcess(0)
                    }
                }, "classic-bond").apply { isDaemon = true }.start()
            }
            if (pairedDevice != null) {
                // disconnected, start connecting again
                central?.scanForPeripheralsWithServices(arrayOf<UUID>(NIKON_SERVICE_UUID))
            }
        }

        override fun onScanStarted() {
            println("Scan started")
        }

        override fun onScanStopped() {
            println("Scan stopped")
        }
    }

    // Create BluetoothCentralManager
    central = BluetoothCentralManager(bluetoothCentralManagerCallback)

    // Scan for peripherals with a certain service UUID
    central.scanForPeripheralsWithServices(arrayOf<UUID>(NIKON_SERVICE_UUID))
}
