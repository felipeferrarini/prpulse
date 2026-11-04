import Foundation

/// A nudge that arrived for the viewer.
public struct IncomingNudge: Equatable, Identifiable, Sendable {
    public let ref: PullRequestRef
    public let title: String
    public let url: URL
    public let nudge: NudgeSnapshot
    /// A nudge seen long after it was sent (the Mac was asleep) only shows a quiet notification.
    public let isFresh: Bool

    public var id: String { nudge.id }

    public init(ref: PullRequestRef, title: String, url: URL, nudge: NudgeSnapshot, isFresh: Bool) {
        self.ref = ref
        self.title = title
        self.url = url
        self.nudge = nudge
        self.isFresh = isFresh
    }
}

public enum NudgePlanner {
    public static let freshness: TimeInterval = 2 * 3600

    /// The nudges the viewer has not been told about, at most one per pull request (the latest).
    ///
    /// A nudge counts only when the author of the pull request wrote it to the viewer, and when it keeps to the rules the
    /// sender follows: at most `NudgeEligibility.maxNudges`, `NudgeEligibility.minimumInterval` apart. The sender's app
    /// checks the same, so a hand-made comment cannot make noise.
    public static func incoming(in summary: Summary, viewer: String, seen: Set<String>, now: Date) -> [IncomingNudge] {
        summary.review.compactMap { item in
            let pr = item.pr
            guard let latest = valid(pr.nudges, author: pr.author.login, viewer: viewer).last, !seen.contains(latest.id) else {
                return nil
            }
            return IncomingNudge(
                ref: pr.ref,
                title: pr.title,
                url: pr.url,
                nudge: latest,
                isFresh: now.timeIntervalSince(latest.createdAt) <= freshness
            )
        }
    }

    private static func valid(_ nudges: [NudgeSnapshot], author: String, viewer: String) -> [NudgeSnapshot] {
        var accepted: [NudgeSnapshot] = []
        let toViewer = nudges
            .filter { $0.author.isSame(as: author) && $0.recipient.caseInsensitiveCompare(viewer) == .orderedSame }
            .sorted { $0.createdAt < $1.createdAt }
        for nudge in toViewer where accepted.count < NudgeEligibility.maxNudges {
            if let last = accepted.last, nudge.createdAt < last.createdAt.addingTimeInterval(NudgeEligibility.minimumInterval) { continue }
            accepted.append(nudge)
        }
        return accepted
    }
}
