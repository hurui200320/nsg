import Foundation

/// Identifies a saved target during reconnection discovery; names are not used for automatic selection.
enum NikonCameraMatcher {
    /// Matches the saved peripheral UUID first; if it changes, requires a unique local device value in Nikon
    /// manufacturer data.
    /// Pass the complete knownCameras list to reject conflicting identities rather than select another camera.
    static func matches(
        _ target: NikonCameraRecord,
        identifier: UUID,
        manufacturerData: Data?,
        knownCameras: [NikonCameraRecord]
    ) -> Bool {
        if identifier == target.peripheralIdentifier { return true }
        guard let manufacturerData else { return false }
        let bytes = Array(manufacturerData)
        guard bytes.count >= 7, bytes[0] == 0x99, bytes[1] == 0x03 else { return false }
        let device = (0..<4).reduce(UInt32(0)) {
            $0 | UInt32(bytes[$1 + 2]) << ($1 * 8)
        }
        // Advertisements contain only a 32-bit device value. Reject automatic selection if local records conflict.
        let matches = knownCameras.filter { $0.controllerDevice == device }
        return device == target.controllerDevice &&
            matches.count == 1 && matches.first?.id == target.id
    }
}
