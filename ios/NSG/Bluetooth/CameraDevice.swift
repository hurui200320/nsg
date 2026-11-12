import Foundation

/// Lightweight scan result for UI selection; id is the discovered peripheral UUID, not a stable camera record
/// ID.
struct CameraDevice: Equatable, Identifiable {
    let id: UUID
    let name: String?
}
