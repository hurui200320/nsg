import Foundation
import CoreBluetooth

/// Events delivered to the camera service; connection UUIDs identify sessions, and connected means services and
/// characteristics were discovered.
enum CameraTransportEvent {
    case stateChanged(CBManagerState)
    case scanningChanged(Bool)
    case discovered(CameraDevice, Data?)
    case discovering(UUID)
    case connected(UUID, NikonCameraCapabilities)
    case subscriptionChanged(UUID, NikonCharacteristic, Bool, CameraFailure?)
    case valueReceived(UUID, NikonCharacteristic, Data)
    case writeCompleted(UUID, NikonCharacteristic, CameraFailure?)
    case disconnected(UUID, CameraFailure?)
    case failed(UUID, CameraFailure)
}
