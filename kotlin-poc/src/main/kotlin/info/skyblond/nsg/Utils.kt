package info.skyblond.nsg

import com.welie.blessed.ScanResult
import kotlin.collections.joinToString

fun ByteArray.toHex(separator: String = "") = this.joinToString(separator) { "%02x".format(it) }

fun formatManufacturerData(record: ScanResult): String {
    val data = record.manufacturerData
    if (data.isEmpty()) return "none"
    return data.keys.map { key ->
        val bytes = data[key] ?: byteArrayOf()
        val keyString = "company=0x%04X".format(key)
        val valueString = bytes.toHex(" ")
        listOf(keyString, valueString).joinToString(" ")
    }.joinToString(separator = "; ")
}

fun verifyManufacturerData(record: ScanResult, expectedDevice: Long): Boolean {
    // TODO: decode manufacturer id and test if the device matches
    return true
}