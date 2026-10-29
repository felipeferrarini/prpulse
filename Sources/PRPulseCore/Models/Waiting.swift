import Foundation

/// How long a pull request has been open, in the terms the list shows it.
public struct Waiting: Equatable, Sendable {
    public enum Unit: Equatable, Sendable {
        case now, hours, days
    }

    public enum Tone: Equatable, Sendable {
        case normal, warm, hot
    }

    private static let warmAfterHours = 24.0
    private static let hotAfterHours = 72.0
    private static let fullBarHours = 96.0

    public let hours: Double

    public init(since start: Date, now: Date) {
        hours = max(0, now.timeIntervalSince(start) / 3600)
    }

    public var unit: Unit {
        if hours < 1 { return .now }
        return hours < Self.warmAfterHours ? .hours : .days
    }

    public var value: Int {
        switch unit {
        case .now: 0
        case .hours: Int(hours)
        case .days: Int(hours / 24)
        }
    }

    public var tone: Tone {
        if hours >= Self.hotAfterHours { return .hot }
        return hours >= Self.warmAfterHours ? .warm : .normal
    }

    /// 0 to 1, a full bar at four days.
    public var fraction: Double {
        min(1, hours / Self.fullBarHours)
    }
}
