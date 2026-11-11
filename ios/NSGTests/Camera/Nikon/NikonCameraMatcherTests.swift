import Foundation
import Testing

@testable import NSG

@MainActor
struct NikonCameraMatcherTests {
    @Test("Match Nikon advertisements after UUID changes and reject incorrect manufacturers and identities")
    func advertisementMatchesSavedUUIDOrVerifiedControllerIdentity() {
        let target = CameraTestContext.camera()
        let data = Data([0x99, 0x03, 0x01, 0x33, 0x22, 0x11, 0x1E])
        #expect(
            NikonCameraMatcher.matches(
                target,
                identifier: UUID(),
                manufacturerData: data,
                knownCameras: [target]
            )
        )
        #expect(
            !NikonCameraMatcher.matches(
                target,
                identifier: UUID(),
                manufacturerData: Data([0x98, 0x03, 0x01, 0x33, 0x22, 0x11, 0]),
                knownCameras: [target]
            )
        )
        #expect(
            !NikonCameraMatcher.matches(
                target,
                identifier: UUID(),
                manufacturerData: Data([0x99, 0x03, 0x02, 0x33, 0x22, 0x11, 0]),
                knownCameras: [target]
            )
        )
        #expect(
            !NikonCameraMatcher.matches(
                target,
                identifier: UUID(),
                manufacturerData: nil,
                knownCameras: [target]
            )
        )
        #expect(
            NikonCameraMatcher.matches(
                target,
                identifier: target.peripheralIdentifier,
                manufacturerData: nil,
                knownCameras: [target]
            )
        )
    }

    @Test("Reject automatic matching when controller advertisement identifiers conflict")
    func advertisementRejectsConflictingControllerIdentities() {
        let target = CameraTestContext.camera()
        let other = CameraTestContext.camera()
        #expect(
            !NikonCameraMatcher.matches(
                target,
                identifier: UUID(),
                manufacturerData: Data([0x99, 0x03, 0x01, 0x33, 0x22, 0x11, 0]),
                knownCameras: [target, other]
            )
        )
    }
}
