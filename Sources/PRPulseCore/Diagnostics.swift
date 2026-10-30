import Foundation

public enum SyncStatus: Equatable, Sendable {
    case neverSynced
    case ok
    case offline
    case failed(String)
}

/// What a bug report needs to know about this install. It holds no token, organization name or pull request title.
public struct DiagnosticsReport: Equatable, Sendable {
    public let appVersion: String
    public let systemVersion: String
    public let authSource: AuthSource
    public let organizationCount: Int
    public let refreshMinutes: Int
    public let lastSync: Date?
    public let status: SyncStatus
    public let reviewCount: Int
    public let mineCount: Int
    public let rateLimit: RateLimit?
    public let shortcutActive: Bool
    public let automaticUpdates: Bool

    public init(
        appVersion: String,
        systemVersion: String,
        authSource: AuthSource,
        organizationCount: Int,
        refreshMinutes: Int,
        lastSync: Date?,
        status: SyncStatus,
        reviewCount: Int,
        mineCount: Int,
        rateLimit: RateLimit?,
        shortcutActive: Bool,
        automaticUpdates: Bool
    ) {
        self.appVersion = appVersion
        self.systemVersion = systemVersion
        self.authSource = authSource
        self.organizationCount = organizationCount
        self.refreshMinutes = refreshMinutes
        self.lastSync = lastSync
        self.status = status
        self.reviewCount = reviewCount
        self.mineCount = mineCount
        self.rateLimit = rateLimit
        self.shortcutActive = shortcutActive
        self.automaticUpdates = automaticUpdates
    }

    /// Plain English text to paste into an issue.
    public func text(now: Date) -> String {
        [
            "PRPulse \(appVersion)",
            "macOS \(systemVersion)",
            "Sign in: \(authSource == .ghCli ? "gh" : "personal token")",
            "Organizations: \(organizationCount)",
            "Refresh every: \(refreshMinutes) min",
            "Last sync: \(lastSyncText(now: now))",
            "Status: \(statusText)",
            "Review: \(reviewCount), mine: \(mineCount)",
            "Rate limit: \(rateLimitText(now: now))",
            "Global shortcut: \(shortcutActive ? "active" : "off")",
            "Automatic updates: \(automaticUpdates ? "on" : "off")",
        ].joined(separator: "\n")
    }

    private func lastSyncText(now: Date) -> String {
        guard let lastSync else { return "never" }
        let seconds = max(Int(now.timeIntervalSince(lastSync)), 0)
        return seconds < 60 ? "\(seconds) s ago" : "\(seconds / 60) min ago"
    }

    private var statusText: String {
        switch status {
        case .neverSynced: "not synced yet"
        case .ok: "ok"
        case .offline: "offline"
        case .failed(let reason): "failed (\(reason))"
        }
    }

    private func rateLimitText(now: Date) -> String {
        guard let rateLimit else { return "unknown" }
        let minutes = max(Int(rateLimit.resetsAt.timeIntervalSince(now)) / 60, 0)
        return "\(rateLimit.remaining) of \(rateLimit.limit) left, resets in \(minutes) min"
    }
}
