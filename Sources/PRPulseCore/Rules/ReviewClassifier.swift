import Foundation

public enum ReviewClassifier {
    public static func items(
        from prs: [PullRequestSnapshot],
        viewer: String,
        ignoredRepos: Set<String>,
        ignoredBots: Set<String> = [],
        skipsBotAuthors: Bool = false
    ) -> [ReviewItem] {
        let ignored = Set(ignoredRepos.map { $0.lowercased() })
        let bots = Set(ignoredBots.map { $0.lowercased() })
        return prs
            .filter { !skipsBotAuthors || !isBotAuthored($0, bots: bots) }
            .filter { needsViewerReview($0, viewer: viewer, ignored: ignored) }
            .map { ReviewItem(pr: $0, isRequested: isRequested($0, viewer: viewer)) }
            .sorted(by: listOrder)
    }

    /// An account GitHub marks as a bot, or one the viewer listed as such.
    private static func isBotAuthored(_ pr: PullRequestSnapshot, bots: Set<String>) -> Bool {
        pr.author.isBot || bots.contains(pr.author.login.lowercased())
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
        let repo = pr.ref.repo.lowercased()
        guard ignored.contains(repo) || ignored.contains("\(pr.ref.owner.lowercased())/\(repo)") else { return false }
        return !isRequested(pr, viewer: viewer)
    }

    private static func isRequested(_ pr: PullRequestSnapshot, viewer: String) -> Bool {
        pr.requestedReviewers.contains { $0.caseInsensitiveCompare(viewer) == .orderedSame }
    }

    /// Requests to the viewer first, then ready PRs before drafts, then the one waiting longest.
    private static func listOrder(_ a: ReviewItem, _ b: ReviewItem) -> Bool {
        if a.isRequested != b.isRequested { return a.isRequested }
        if a.pr.isDraft != b.pr.isDraft { return !a.pr.isDraft }
        if a.pr.createdAt != b.pr.createdAt { return a.pr.createdAt < b.pr.createdAt }
        return a.pr.ref.number < b.pr.ref.number
    }
}
