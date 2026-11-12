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
        let items = prs
            .filter { !skipsBotAuthors || !isBotAuthored($0, bots: bots) }
            .filter { isListed($0, viewer: viewer, ignored: ignored) }
            .map { ReviewItem(pr: $0, isRequested: isRequested($0, viewer: viewer), hasReviewed: hasSubmittedReview($0, by: viewer)) }
        return ListOrder.sorted(items, by: .priority)
    }

    /// An account GitHub marks as a bot, or one the viewer listed as such.
    private static func isBotAuthored(_ pr: PullRequestSnapshot, bots: Set<String>) -> Bool {
        pr.author.isBot || bots.contains(pr.author.login.lowercased())
    }

    /// Every open pull request of someone else, the ones the viewer reviewed too, except those of a repository the viewer hid.
    private static func isListed(_ pr: PullRequestSnapshot, viewer: String, ignored: Set<String>) -> Bool {
        guard !pr.author.isSame(as: viewer) else { return false }
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
}
