package info.skyblond.nsp.data

import org.json.JSONObject

/**
 * A previously paired Nikon camera. [device] and [nonce] are stored as unsigned 32-bit values.
 * [address] is the last-known BLE address; because the camera uses a random BLE address that
 * can change between sessions, the app scans for the camera by [name] when reconnecting.
 */
data class PairedCamera(
    val name: String,
    val address: String,
    val addressType: Int,
    val device: Long,
    val nonce: Long,
    val controllerName: String
) {
    fun toJson(): String = JSONObject().apply {
        put("name", name)
        put("address", address)
        put("addressType", addressType)
        put("device", device)
        put("nonce", nonce)
        put("controllerName", controllerName)
    }.toString()

    companion object {
        fun fromJson(json: String): PairedCamera {
            val obj = JSONObject(json)
            return PairedCamera(
                name = obj.getString("name"),
                address = obj.getString("address"),
                addressType = obj.getInt("addressType"),
                device = obj.getLong("device"),
                nonce = obj.getLong("nonce"),
                controllerName = obj.getString("controllerName")
            )
        }
    }
}
