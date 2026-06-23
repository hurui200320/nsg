package info.skyblond.nsp.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.util.Log
import java.util.UUID

private const val TAG = "CameraBleManager"

@SuppressLint("MissingPermission")
class CameraBleManager(
    private val context: Context,
    private val listener: BleListener
) : BluetoothGattCallback() {

    interface BleListener {
        fun onEvent(event: BleEvent)
    }

    private var gatt: BluetoothGatt? = null
    private var pairCharacteristic: BluetoothGattCharacteristic? = null
    private var not1Characteristic: BluetoothGattCharacteristic? = null
    private var subscriptionStep = 0

    fun connect(device: BluetoothDevice) {
        Log.d(TAG, "Connecting to ${device.address} (${device.name ?: "no name"})")
        gatt = device.connectGatt(context, false, this, BluetoothDevice.TRANSPORT_LE)
    }

    fun disconnect() {
        Log.d(TAG, "Disconnecting")
        gatt?.disconnect()
    }

    fun close() {
        Log.d(TAG, "Closing GATT")
        gatt?.close()
        gatt = null
    }

    /**
     * Must be called after [BleEvent.ServicesDiscovered] to enable PAIR indications
     * and NOT1 notifications. The two descriptor writes are serialized because Android
     * GATT does not reliably support concurrent descriptor writes.
     */
    fun prepare() {
        Log.d(TAG, "Preparing: enabling PAIR indications and NOT1 notifications")
        val gatt = this.gatt ?: run {
            emitError("Cannot prepare: gatt is null")
            return
        }
        val service = gatt.getService(SERVICE_UUID)
        if (service == null) {
            emitError("Nikon service not found")
            return
        }
        val pair = service.getCharacteristic(PAIR_UUID)
        val not1 = service.getCharacteristic(NOT1_UUID)
        val id = service.getCharacteristic(ID_UUID)
        val geo = service.getCharacteristic(GEO_UUID)
        if (pair == null || not1 == null) {
            emitError("Missing PAIR or NOT1 characteristic")
            return
        }
        pairCharacteristic = pair
        not1Characteristic = not1
        Log.d(TAG, "PAIR properties=${pair.properties} NOT1 properties=${not1.properties} ID properties=${id?.properties} GEO properties=${geo?.properties}")
        subscriptionStep = 1
        enableIndication(pair)
    }

    fun writePairMessage(bytes: ByteArray) {
        Log.d(TAG, "Writing PAIR message (${bytes.size} bytes)")
        writeCharacteristic(PAIR_UUID, bytes)
    }

    fun writeId(nameBytes: ByteArray) {
        Log.d(TAG, "Writing ID: ${nameBytes.toString(Charsets.US_ASCII)}")
        writeCharacteristic(ID_UUID, nameBytes)
    }

    fun writeGeo(bytes: ByteArray) {
        Log.d(TAG, "Writing GEO payload (${bytes.size} bytes)")
        writeCharacteristic(GEO_UUID, bytes)
    }

    override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
        Log.d(TAG, "onConnectionStateChange status=$status newState=$newState")
        if (status != BluetoothGatt.GATT_SUCCESS) {
            emitError("Connection state change error: status=$status")
        }
        when (newState) {
            BluetoothProfile.STATE_CONNECTED -> {
                listener.onEvent(BleEvent.Connected)
                gatt.requestMtu(517)
            }
            BluetoothProfile.STATE_DISCONNECTED -> {
                listener.onEvent(BleEvent.Disconnected)
            }
        }
    }

    override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
        Log.d(TAG, "onMtuChanged mtu=$mtu status=$status")
        if (status == BluetoothGatt.GATT_SUCCESS) {
            listener.onEvent(BleEvent.MtuChanged(mtu))
        } else {
            emitError("MTU request failed: status=$status")
        }
        gatt.discoverServices()
    }

    override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
        Log.d(TAG, "onServicesDiscovered status=$status")
        if (status == BluetoothGatt.GATT_SUCCESS) {
            listener.onEvent(BleEvent.ServicesDiscovered)
        } else {
            emitError("Service discovery failed: status=$status")
        }
    }

    override fun onDescriptorWrite(
        gatt: BluetoothGatt,
        descriptor: BluetoothGattDescriptor,
        status: Int
    ) {
        Log.d(TAG, "onDescriptorWrite descriptor=${descriptor.uuid} status=$status step=$subscriptionStep")
        if (status != BluetoothGatt.GATT_SUCCESS) {
            emitError("Descriptor write failed: status=$status")
            return
        }
        when (subscriptionStep) {
            1 -> {
                subscriptionStep = 2
                not1Characteristic?.let { enableNotification(it) }
                    ?: emitError("Cannot enable NOT1: characteristic missing")
            }
            2 -> {
                subscriptionStep = 0
                listener.onEvent(BleEvent.SubscriptionsEnabled)
            }
            else -> {
                Log.d(TAG, "onDescriptorWrite ignored, step=$subscriptionStep")
            }
        }
    }

    override fun onCharacteristicChanged(
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
        value: ByteArray
    ) {
        Log.d(TAG, "onCharacteristicChanged (API33) ${characteristic.uuid} value=${value.size} bytes")
        handleCharacteristicChanged(characteristic.uuid, value)
    }

    @Suppress("OVERRIDE_DEPRECATION")
    @Deprecated("Deprecated in Java")
    override fun onCharacteristicChanged(
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic
    ) {
        Log.d(TAG, "onCharacteristicChanged ${characteristic.uuid}")
        handleCharacteristicChanged(characteristic.uuid, characteristic.value)
    }

    private fun handleCharacteristicChanged(uuid: UUID, value: ByteArray?) {
        when (uuid) {
            PAIR_UUID -> listener.onEvent(BleEvent.PairIndication(value ?: byteArrayOf()))
            NOT1_UUID -> listener.onEvent(BleEvent.Not1Notification(value ?: byteArrayOf()))
        }
    }

    override fun onCharacteristicWrite(
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
        status: Int
    ) {
        Log.d(TAG, "onCharacteristicWrite ${characteristic.uuid} status=$status")
        listener.onEvent(BleEvent.WriteDone(characteristic.uuid, status))
    }

    private fun enableIndication(characteristic: BluetoothGattCharacteristic) {
        val gatt = this.gatt ?: return
        Log.d(TAG, "Enabling indications on ${characteristic.uuid}")
        gatt.setCharacteristicNotification(characteristic, true)
        val descriptor = characteristic.getDescriptor(CCCD_UUID)
        if (descriptor != null) {
            gatt.writeDescriptor(descriptor, BluetoothGattDescriptor.ENABLE_INDICATION_VALUE)
        }
    }

    private fun enableNotification(characteristic: BluetoothGattCharacteristic) {
        val gatt = this.gatt ?: return
        Log.d(TAG, "Enabling notifications on ${characteristic.uuid}")
        gatt.setCharacteristicNotification(characteristic, true)
        val descriptor = characteristic.getDescriptor(CCCD_UUID)
        if (descriptor != null) {
            gatt.writeDescriptor(descriptor, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
        }
    }

    private fun writeCharacteristic(uuid: UUID, data: ByteArray) {
        val gatt = this.gatt ?: run {
            emitError("Cannot write $uuid: gatt is null")
            return
        }
        Log.d(TAG, "writeCharacteristic $uuid (${data.size} bytes)")
        val service = gatt.getService(SERVICE_UUID)
        if (service == null) {
            emitError("Cannot write $uuid: service not found")
            return
        }
        val characteristic = service.getCharacteristic(uuid)
        if (characteristic == null) {
            emitError("Characteristic not found: $uuid")
            return
        }
        gatt.writeCharacteristic(characteristic, data, BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT)
    }

    private fun emitError(message: String) {
        listener.onEvent(BleEvent.Error(message))
    }

    companion object {
        val SERVICE_UUID = UUID.fromString("0000de00-3dd4-4255-8d62-6dc7b9bd5561")
        val PAIR_UUID = UUID.fromString("00002000-3dd4-4255-8d62-6dc7b9bd5561")
        val NOT1_UUID = UUID.fromString("00002008-3dd4-4255-8d62-6dc7b9bd5561")
        val ID_UUID = UUID.fromString("00002002-3dd4-4255-8d62-6dc7b9bd5561")
        val GEO_UUID = UUID.fromString("00002007-3dd4-4255-8d62-6dc7b9bd5561")
        val CCCD_UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }
}
