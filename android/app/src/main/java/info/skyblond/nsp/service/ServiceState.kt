package info.skyblond.nsp.service

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

    val label: String
        get() = when (this) {
            is Idle -> "Idle"
            is Scanning -> "Scanning..."
            is Connecting -> "Connecting..."
            is Discovering -> "Discovering services..."
            is Pairing -> "Pairing..."
            is Bonding -> "Bluetooth Classic bonding..."
            is Ready -> "Ready"
            is Busy -> "Busy"
            is Error -> "Error: $reason"
        }
}
