package info.skyblond.nsp.data

import android.annotation.SuppressLint
import android.bluetooth.le.ScanResult

/**
 * A camera discovered during a BLE scan.
 */
@SuppressLint("MissingPermission")
data class DiscoveredCamera(
    val name: String,
    val address: String,
    val manufacturerData: ByteArray?,
    val isNew: Boolean
) {
    constructor(result: ScanResult, isNew: Boolean) : this(
        name = result.device.name ?: result.device.address ?: "Unknown",
        address = result.device.address ?: "",
        manufacturerData = result.scanRecord?.manufacturerSpecificData?.let { data ->
            // Copy all manufacturer data into a single byte array.
            val builder = mutableListOf<Byte>()
            for (i in 0 until data.size()) {
                val key = data.keyAt(i)
                builder.add((key and 0xFF).toByte())
                builder.add(((key shr 8) and 0xFF).toByte())
                data.get(key)?.forEach { builder.add(it) }
            }
            builder.toByteArray()
        },
        isNew = isNew
    )

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is DiscoveredCamera) return false
        return address == other.address && isNew == other.isNew
    }

    override fun hashCode(): Int {
        return 31 * address.hashCode() + isNew.hashCode()
    }
}
