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
    /// On a pull request of someone else that waits for the viewer's review, a nudge counts when its author wrote it to the
    /// viewer. On the viewer's own pull request, when a person who reviewed it wrote that it can be merged. Either keeps to
    /// the rules the sender follows: at most `NudgeEligibility.maxNudges`, `NudgeEligibility.minimumInterval` apart. The
    /// sender's app checks the same, so a hand-made comment cannot make noise.
    public static func incoming(in summary: Summary, viewer: String, seen: Set<String>, now: Date) -> [IncomingNudge] {
        let toReview = summary.review.filter(\.needsAction).map(\.pr)
        let toMerge = summary.mine.map(\.pr)
        return (toReview + toMerge).compactMap { pr in
            guard let latest = latest(in: pr, viewer: viewer), !seen.contains(latest.id) else { return nil }
            return IncomingNudge(
                ref: pr.ref,
                title: pr.title,
                url: pr.url,
                nudge: latest,
                isFresh: now.timeIntervalSince(latest.createdAt) <= freshness
            )
        }
    }

    private static func latest(in pr: PullRequestSnapshot, viewer: String) -> NudgeSnapshot? {
        if pr.author.isSame(as: viewer) { return mergeNudges(in: pr, viewer: viewer).last }
        let fromAuthor = pr.nudges.filter {
            $0.kind == .review && $0.author.isSame(as: pr.author.login) && $0.recipient.caseInsensitiveCompare(viewer) == .orderedSame
        }
        return valid(fromAuthor).last
    }

    /// Each person who reviewed the pull request has a budget of their own.
    private static func mergeNudges(in pr: PullRequestSnapshot, viewer: String) -> [NudgeSnapshot] {
        let toViewer = pr.nudges.filter {
            $0.kind == .merge
                && $0.recipient.caseInsensitiveCompare(viewer) == .orderedSame
                && !$0.author.isSame(as: viewer)
                && !$0.author.isBot
                && MinimumReviews.latestState(of: $0.author.login, in: pr) != nil
        }
        let bySender = Dictionary(grouping: toViewer) { $0.author.login.lowercased() }
        return bySender.values.flatMap(valid).sorted { $0.createdAt < $1.createdAt }
    }

    private static func valid(_ nudges: [NudgeSnapshot]) -> [NudgeSnapshot] {
        var accepted: [NudgeSnapshot] = []
        for nudge in nudges.sorted(by: { $0.createdAt < $1.createdAt }) where accepted.count < NudgeEligibility.maxNudges {
            if let last = accepted.last, nudge.createdAt < last.createdAt.addingTimeInterval(NudgeEligibility.minimumInterval) { continue }
            accepted.append(nudge)
        }
        return accepted
    }
}
