import Testing

@testable import NSG

@MainActor
struct ReconnectPolicyTests {
    @Test("Retry delay starts at five seconds and is capped at one minute")
    func retryDelayDoublesUntilOneMinuteCap() {
        #expect((1...6).map { ReconnectPolicy.delay(attempt: $0) } == [5, 10, 20, 40, 60, 60])
    }
}
