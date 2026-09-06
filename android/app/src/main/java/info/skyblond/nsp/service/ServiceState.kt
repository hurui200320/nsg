package info.skyblond.nsp.service

import android.content.Context
import info.skyblond.nsp.R

sealed class ConnectionState {
    data object Idle : ConnectionState()
    data object Scanning : ConnectionState()
    data object Connecting : ConnectionState()
    data object Discovering : ConnectionState()
    data object Pairing : ConnectionState()
    data object Bonding : ConnectionState()
    data object Ready : ConnectionState()
    data object Busy : ConnectionState()
    data class Error(val reason: String) : ConnectionState()

    fun label(context: Context): String = when (this) {
        is Idle -> context.getString(R.string.state_idle)
        is Scanning -> context.getString(R.string.state_scanning)
        is Connecting -> context.getString(R.string.state_connecting)
        is Discovering -> context.getString(R.string.state_discovering)
        is Pairing -> context.getString(R.string.state_pairing)
        is Bonding -> context.getString(R.string.state_bonding)
        is Ready -> context.getString(R.string.state_ready)
        is Busy -> context.getString(R.string.state_busy)
        is Error -> context.getString(R.string.state_error_prefix) + reason
    }
}

data class GpsState(
    val enabled: Boolean = false,
    val hasFix: Boolean = false,
    val latitude: Double? = null,
    val longitude: Double? = null,
    val accuracyMeters: Float? = null,
    val lastFixTime: Long? = null,
    val lastSentTime: Long? = null
)
