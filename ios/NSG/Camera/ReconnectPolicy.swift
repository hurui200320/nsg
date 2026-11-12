import Foundation

enum ReconnectPolicy {
    /// Maximum wait for each target rediscovery attempt; used when arming the scan deadline.
    static let rediscoveryTimeout: TimeInterval = 30

    /// Delay after the given failure attempt; exponential backoff starts at five seconds and is capped at sixty
    /// seconds.
    static func delay(attempt: Int) -> TimeInterval {
        // Clamp before subtraction so corrupt or extreme input cannot overflow.
        let exponent = min(max(attempt, 1), 5) - 1
        return min(5 * pow(2, Double(exponent)), 60)
    }
}
