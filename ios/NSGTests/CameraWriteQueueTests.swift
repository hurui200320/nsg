import Foundation
import Testing
@testable import NSG

@MainActor
struct CameraWriteQueueTests {
    @Test("Stage indications may queue later writes before earlier acknowledgements")
    func serializedWrites() {
        var queue = CameraWriteQueue()
        queue.enqueue(Data([1]), to: .pairing)
        let stage1 = queue.next()
        #expect(stage1?.data == Data([1]))
        queue.enqueue(Data([3]), to: .pairing)
        queue.enqueue(Data([4]), to: .controllerName)
        let blockedStage3 = queue.next()
        #expect(blockedStage3 == nil)
        let wrongAcknowledgement = queue.acknowledge(.controllerName)
        #expect(!wrongAcknowledgement)
        let stillBlocked = queue.next()
        #expect(stillBlocked == nil)
        let stage1Acknowledged = queue.acknowledge(.pairing)
        #expect(stage1Acknowledged)
        let stage3 = queue.next()
        #expect(stage3?.data == Data([3]))
        let stage3Acknowledged = queue.acknowledge(.pairing)
        #expect(stage3Acknowledged)
        let name = queue.next()
        #expect(name?.characteristic == .controllerName)
    }

    @Test("Disconnect discards queued writes and cannot acknowledge the discarded request")
    func cancellation() {
        var queue = CameraWriteQueue()
        queue.enqueue(Data([1]), to: .pairing)
        _ = queue.next()
        queue.enqueue(Data([3]), to: .pairing)
        queue.removeAll()
        let next = queue.next()
        #expect(next == nil)
        let acknowledged = queue.acknowledge(.pairing)
        #expect(!acknowledged)
    }
}
