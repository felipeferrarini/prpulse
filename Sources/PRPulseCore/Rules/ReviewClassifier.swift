import Foundation

public enum ReviewClassifier {
    public static func items(
        from prs: [PullRequestSnapshot],
        viewer: String,
        ignoredRepos: Set<String>
    ) -> [ReviewItem] {
        let ignored = Set(ignoredRepos.map { $0.lowercased() })
        return prs
            .filter { needsViewerReview($0, viewer: viewer, ignored: ignored) }
            .sorted(by: listOrder)
            .map(ReviewItem.init)
    }

    private static func needsViewerReview(_ pr: PullRequestSnapshot, viewer: String, ignored: Set<String>) -> Bool {
        guard !pr.author.isSame(as: viewer) else { return false }
        guard !hasSubmittedReview(pr, by: viewer) else { return false }
        return !isHiddenByRepo(pr, viewer: viewer, ignored: ignored)
    }

    private static func hasSubmittedReview(_ pr: PullRequestSnapshot, by viewer: String) -> Bool {
        pr.reviews.contains {
            $0.authorLogin.caseInsensitiveCompare(viewer) == .orderedSame && $0.state != .pending
        }
    }

    private static func isHiddenByRepo(_ pr: PullRequestSnapshot, viewer: String, ignored: Set<String>) -> Bool {
        guard ignored.contains(pr.ref.repo.lowercased()) else { return false }
        return !pr.requestedReviewers.contains { $0.caseInsensitiveCompare(viewer) == .orderedSame }
    }

    private static func listOrder(_ a: PullRequestSnapshot, _ b: PullRequestSnapshot) -> Bool {
        if a.isDraft != b.isDraft { return !a.isDraft }
        if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
        return a.ref.number < b.ref.number
    }
}
