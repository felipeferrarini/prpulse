import Foundation

/// What the mascot is feeling. Every mascot pack animates these.
public enum MascotMood: String, CaseIterable, Codable, Sendable {
    case calm, sleep, alert, joy, worried, think, sad
}

/// Everything that decides the mascot's mood.
public struct MascotSituation: Sendable {
    public var state: LoadState
    public var isOffline: Bool
    public var summary: Summary?
    public var freshUntil: Date?
    public var isRefreshing: Bool
    /// Since when nothing has needed the viewer, if that is the case.
    public var upToDateSince: Date?

    public init(
        state: LoadState = .idle,
        isOffline: Bool = false,
        summary: Summary? = nil,
        freshUntil: Date? = nil,
        isRefreshing: Bool = false,
        upToDateSince: Date? = nil
    ) {
        self.state = state
        self.isOffline = isOffline
        self.summary = summary
        self.freshUntil = freshUntil
        self.isRefreshing = isRefreshing
        self.upToDateSince = upToDateSince
    }
}

public enum MascotMoodResolver {
    /// Quiet for this long and the mascot falls asleep.
    public static let sleepAfter: TimeInterval = 30 * 60
    /// A request, or one of the viewer's own PRs, that waits this long worries the mascot.
    public static let worriedAfterHours = 72.0

    /// The first that applies: trouble, something new, a refresh in flight, an old PR, something to do, sleep, calm.
    public static func mood(for situation: MascotSituation, now: Date) -> MascotMood {
        if case .failed = situation.state { return .sad }
        if situation.isOffline { return .sad }
        if let fresh = situation.freshUntil, fresh > now { return .joy }
        if situation.isRefreshing { return .think }
        guard let summary = situation.summary else { return .calm }
        if hasOldPullRequest(summary, now: now) { return .worried }
        if summary.total > 0 { return .alert }
        if let since = situation.upToDateSince, now.timeIntervalSince(since) >= sleepAfter { return .sleep }
        return .calm
    }

    private static func hasOldPullRequest(_ summary: Summary, now: Date) -> Bool {
        let requested = summary.review.filter(\.isRequested).map(\.pr.createdAt)
        let waiting = summary.waiting.map(\.pr.createdAt)
        return (requested + waiting).contains { Waiting(since: $0, now: now).hours >= worriedAfterHours }
    }
}

/// What just arrived, for the mascot's speech bubble.
public struct Arrival: Equatable, Sendable {
    public let count: Int
    public let firstTitle: String
    public let at: Date

    public init(count: Int, firstTitle: String, at: Date) {
        self.count = count
        self.firstTitle = firstTitle
        self.at = at
    }

    /// The distinct pull requests behind the new keys, in the order the summary lists them.
    public static func make(from keys: [PendingKey], in summary: Summary, at: Date) -> Arrival? {
        let wanted = Set(keys.map(\.ref))
        var seen = Set<PullRequestRef>()
        let titles = (summary.mine.map(\.pr) + summary.review.map(\.pr))
            .filter { wanted.contains($0.ref) && seen.insert($0.ref).inserted }
            .map(\.title)
        guard let first = titles.first else { return nil }
        return Arrival(count: titles.count, firstTitle: first, at: at)
    }
}
