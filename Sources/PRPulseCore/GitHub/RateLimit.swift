import Foundation

/// GitHub's budget of API requests, as the last response reported it.
public struct RateLimit: Equatable, Sendable {
    public let limit: Int
    public let remaining: Int
    public let resetsAt: Date

    public init(limit: Int, remaining: Int, resetsAt: Date) {
        self.limit = limit
        self.remaining = remaining
        self.resetsAt = resetsAt
    }

    public static func parse(_ header: (String) -> String?) -> RateLimit? {
        guard
            let limit = header("X-RateLimit-Limit").flatMap(Int.init),
            let remaining = header("X-RateLimit-Remaining").flatMap(Int.init),
            let reset = header("X-RateLimit-Reset").flatMap(TimeInterval.init)
        else { return nil }
        return RateLimit(limit: limit, remaining: remaining, resetsAt: Date(timeIntervalSince1970: reset))
    }
}

/// Keeps the latest rate limit seen by any transport, so the settings can show it.
public final class RateLimitMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: RateLimit?

    public init() {}

    public var latest: RateLimit? { lock.withLock { stored } }

    public func record(_ rateLimit: RateLimit) {
        lock.withLock { stored = rateLimit }
    }
}
