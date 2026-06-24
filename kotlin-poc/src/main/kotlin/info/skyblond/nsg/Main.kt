package info.skyblond.nsg

import com.welie.blessed.*
import info.skyblond.nsg.Const.ID_CHAR_UUID
import info.skyblond.nsg.Const.NIKON_SERVICE_UUID
import info.skyblond.nsg.Const.NOT1_CHAR_UUID
import info.skyblond.nsg.Const.PAIR_CHAR_UUID
import info.skyblond.nsp.ble.protocol.NikonPairingEngine
import info.skyblond.nsp.ble.protocol.PairingMessage
import org.slf4j.LoggerFactory
import java.util.*

val logger = LoggerFactory.getLogger("Application")

fun main() {
    // paired camera should reuse device and nonce
    // note: for BLE, each time camera gives a random address
    //       but the classic bluetooth address is fixed
    val pairedCameraName: String? = null
    // 1668104449
    val pairedDevice: Long? = null
    // 2056081517
    val pairedNonce: Long? = null

    var central: BluetoothCentralManager? = null

    val pairingPeripheralCallback = object : BluetoothPeripheralCallback() {
        private val pairingEngine = NikonPairingEngine()

        private var nikonService: BluetoothGattService? = null

        // 0: not started
        // 1, 3: us to cam
        // 2, 4: cam to us
        private var handshakeStageCounter = 0

        private var stage1Message: PairingMessage? = null
        private var stage2Message: PairingMessage? = null
        private var stage3Message: PairingMessage? = null
        private var stage4Message: PairingMessage? = null

        override fun onServicesDiscovered(
            peripheral: BluetoothPeripheral,
            services: List<BluetoothGattService?>
        ) {
            nikonService = peripheral.getService(NIKON_SERVICE_UUID)
                ?: error("Missing Nikon service")

            logger.info("Enable notify on characteristic PAIR")
            peripheral.setNotify(NIKON_SERVICE_UUID, PAIR_CHAR_UUID, true)

            logger.info("Enable notify on characteristic NOT1")
            peripheral.setNotify(NIKON_SERVICE_UUID, NOT1_CHAR_UUID, true)

            // begin handshake, send stage 1 message
            logger.info("Start handshake, sending stage 1 message...")
            handshakeStageCounter = 1
            stage1Message = pairingEngine.createStage1(null, null)
            logger.info("Handshake stage 1 message: $stage1Message")
            peripheral.writeCharacteristic(
                NIKON_SERVICE_UUID, PAIR_CHAR_UUID,
                stage1Message!!.encode(),
                BluetoothGattCharacteristic.WriteType.WITH_RESPONSE
            )
        }

        override fun onDescriptorWrite(
            peripheral: BluetoothPeripheral,
            value: ByteArray,
            descriptor: BluetoothGattDescriptor,
            status: BluetoothCommandStatus
        ) {
            logger.info("onDescriptorWrite descriptor: ${descriptor.uuid}, status: $status")
        }

        override fun onCharacteristicWrite(
            peripheral: BluetoothPeripheral,
            value: ByteArray,
            characteristic: BluetoothGattCharacteristic,
            status: BluetoothCommandStatus
        ) {
            logger.info("onCharacteristicWrite descriptor: ${characteristic.uuid}, status: $status")
        }

        override fun onCharacteristicUpdate(
            peripheral: BluetoothPeripheral,
            value: ByteArray,
            characteristic: BluetoothGattCharacteristic,
            status: BluetoothCommandStatus
        ) {

            when (characteristic.uuid) {
                NOT1_CHAR_UUID -> {
                    logger.info(
                        "onCharacteristicUpdate descriptor: NOT1, status: {}, value: {}",
                        status, value.toHex(" ")
                    )
                }

                PAIR_CHAR_UUID -> { // message 2 or 4
                    logger.info("onCharacteristicUpdate descriptor: PAIR, status: $status")
                    when (handshakeStageCounter) {
                        1 -> { // we sent stage 1, now it's stage 2 (cam to us)
                            handshakeStageCounter = 2
                            stage2Message = PairingMessage.decode(value)
                            logger.info("Received handshake stage 2 message: $stage2Message")
                            stage3Message = pairingEngine.verifyStage2AndBuildStage3(
                                stage1Message!!, stage2Message!!
                            )
                            // now sending stage 3 message
                            logger.info("Sending handshake stage 3 message: $stage3Message")
                            handshakeStageCounter = 3
                            peripheral.writeCharacteristic(
                                NIKON_SERVICE_UUID, PAIR_CHAR_UUID,
                                stage3Message!!.encode(),
                                BluetoothGattCharacteristic.WriteType.WITH_RESPONSE
                            )
                        }

                        3 -> { // we send stage 3, now it's stage 4
                            stage4Message = PairingMessage.decode(value)
                            logger.info("Received handshake stage 4 message: $stage4Message")
                            val serial = pairingEngine.extractSerial(stage4Message!!)
                            logger.info("Camera serial: $serial")
                            // now we should expect 01 00 on NOT1, wait 3 seconds
                            Thread.sleep(3000)
                            // write controller id
                            val nameBytes = "NSG-kotlin".toByteArray(Charsets.US_ASCII)
                            val padded = ByteArray(32) { 0x00 }
                            nameBytes.copyInto(
                                padded, 0, 0,
                                minOf(nameBytes.size, padded.size)
                            )
                            logger.info(
                                "Writing controller id: {} ({})",
                                "NSG-kotlin",
                                padded.toHex(" ")
                            )
                            peripheral.writeCharacteristic(
                                NIKON_SERVICE_UUID, ID_CHAR_UUID,
                                padded,
                                BluetoothGattCharacteristic.WriteType.WITH_RESPONSE
                            )
                            // wait 3 seconds
                            Thread.sleep(3000)
                            // here we can disconnect the device and switch to classic BT bond
                            peripheral.cancelConnection()
                        }

                        else -> logger.warn("onCharacteristicUpdate got message from PAIR, but unknown handshake stage: $handshakeStageCounter")
                    }
                }

                else -> logger.info("onCharacteristicUpdate descriptor: ${characteristic.uuid}, status: $status")
            }
        }

    }

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
                central?.connectPeripheral(peripheral, pairingPeripheralCallback)
            }
            if (pairedDevice != null && hasManufacturerData && verifyManufacturerData(
                    scanResult,
                    pairedDevice
                )
            ) {
                // we have paired device and the camera is also looking for us
                central?.stopScan()
//            central?.connectPeripheral(peripheral, peripheralCallback)
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
