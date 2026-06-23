package info.skyblond.nsp.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothProfile
import android.content.Context
import java.util.UUID

@SuppressLint("MissingPermission")
class CameraBleManager(
    private val context: Context,
    private val listener: BleListener
) : BluetoothGattCallback() {

    interface BleListener {
        fun onEvent(event: BleEvent)
    }

    private var gatt: BluetoothGatt? = null
    private var pendingDescriptorWrites = 0

    fun connect(device: BluetoothDevice) {
        gatt = device.connectGatt(context, false, this, BluetoothDevice.TRANSPORT_LE)
    }

    fun disconnect() {
        gatt?.disconnect()
    }

    fun close() {
        gatt?.close()
        gatt = null
    }

    /**
     * Must be called after [BleEvent.ServicesDiscovered] to enable PAIR indications
     * and NOT1 notifications.
     */
    fun prepare() {
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
        if (pair == null || not1 == null) {
            emitError("Missing PAIR or NOT1 characteristic")
            return
        }
        pendingDescriptorWrites = 2
        enableIndication(pair)
        enableNotification(not1)
    }

    fun writePairMessage(bytes: ByteArray) {
        writeCharacteristic(PAIR_UUID, bytes)
    }

    fun writeId(nameBytes: ByteArray) {
        writeCharacteristic(ID_UUID, nameBytes)
    }

    fun writeGeo(bytes: ByteArray) {
        writeCharacteristic(GEO_UUID, bytes)
    }

    override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
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
        if (status == BluetoothGatt.GATT_SUCCESS) {
            listener.onEvent(BleEvent.MtuChanged(mtu))
        } else {
            emitError("MTU request failed: status=$status")
        }
        gatt.discoverServices()
    }

    override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
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
        if (status != BluetoothGatt.GATT_SUCCESS) {
            emitError("Descriptor write failed: status=$status")
            return
        }
        pendingDescriptorWrites--
        if (pendingDescriptorWrites <= 0) {
            listener.onEvent(BleEvent.SubscriptionsEnabled)
        }
    }

    override fun onCharacteristicChanged(
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
        value: ByteArray
    ) {
        handleCharacteristicChanged(characteristic.uuid, value)
    }

    @Suppress("OVERRIDE_DEPRECATION")
    @Deprecated("Deprecated in Java")
    override fun onCharacteristicChanged(
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic
    ) {
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
        listener.onEvent(BleEvent.WriteDone(characteristic.uuid, status))
    }

    private fun enableIndication(characteristic: BluetoothGattCharacteristic) {
        val gatt = this.gatt ?: return
        gatt.setCharacteristicNotification(characteristic, true)
        val descriptor = characteristic.getDescriptor(CCCD_UUID)
        if (descriptor != null) {
            gatt.writeDescriptor(descriptor, BluetoothGattDescriptor.ENABLE_INDICATION_VALUE)
        }
    }

    private fun enableNotification(characteristic: BluetoothGattCharacteristic) {
        val gatt = this.gatt ?: return
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
