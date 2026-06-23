package info.skyblond.nsp.ble

import java.util.UUID

sealed class BleEvent {
    data object Connected : BleEvent()
    data object Disconnected : BleEvent()
    data object ServicesDiscovered : BleEvent()
    data object SubscriptionsEnabled : BleEvent()
    data class MtuChanged(val mtu: Int) : BleEvent()
    data class PairIndication(val data: ByteArray) : BleEvent()
    data class Not1Notification(val data: ByteArray) : BleEvent()
    data class WriteDone(val uuid: UUID, val status: Int) : BleEvent()
    data class Error(val message: String) : BleEvent()
}
