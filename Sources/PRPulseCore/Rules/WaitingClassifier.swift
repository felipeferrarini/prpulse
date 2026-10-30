import Foundation

/// Finds the viewer's pull requests that sit without a review, so the viewer knows who to nudge.
public enum WaitingClassifier {
    public static let dayOptions = [0, 1, 2, 3, 5, 7]

    /// `minimumDays` of 0 turns the list off. Oldest first.
    public static func items(
        from prs: [PullRequestSnapshot],
        viewer: String,
        ignoredBots: Set<String>,
        minimumDays: Int,
        now: Date
    ) -> [WaitingItem] {
        guard minimumDays > 0 else { return [] }
        let ignored = Set(ignoredBots.map { $0.lowercased() })
        let threshold = TimeInterval(minimumDays) * 86_400
        return prs
            .filter { isWaiting($0, viewer: viewer, ignored: ignored, threshold: threshold, now: now) }
            .sorted { ($0.createdAt, $0.ref.number) < ($1.createdAt, $1.ref.number) }
            .map(WaitingItem.init)
    }

    private static func isWaiting(
        _ pr: PullRequestSnapshot,
        viewer: String,
        ignored: Set<String>,
        threshold: TimeInterval,
        now: Date
    ) -> Bool {
        guard !pr.isDraft, pr.reviewDecision != .changesRequested else { return false }
        guard now.timeIntervalSince(pr.createdAt) >= threshold else { return false }
        return !pr.reviews.contains { review in
            review.state != .pending
                && review.authorLogin.caseInsensitiveCompare(viewer) != .orderedSame
                && !ignored.contains(review.authorLogin.lowercased())
        }
    }
}
