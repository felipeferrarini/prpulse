import Foundation

/// Whether a pull request has the reviews it needs to be merged. Checks, conflicts and the other locks a repository can have
/// are not looked at: only the reviews.
public enum MinimumReviews {
    /// GitHub says so through the review decision when the repository asks for reviews. A repository that asks for none has
    /// nothing to count, so one approval is taken as enough: the one of `reviewer` when given, anyone's otherwise.
    public static func isMet(_ pr: PullRequestSnapshot, countingApprovalOf reviewer: String? = nil) -> Bool {
        switch pr.reviewDecision {
        case .approved: true
        case .changesRequested, .reviewRequired: false
        case nil: hasApproval(pr, from: reviewer)
        }
    }

    /// The reviewer's latest word on the pull request, setting aside what is still pending or was dismissed.
    public static func latestState(of reviewer: String, in pr: PullRequestSnapshot) -> ReviewState? {
        pr.reviews
            .filter { $0.authorLogin.caseInsensitiveCompare(reviewer) == .orderedSame && $0.state != .pending && $0.state != .dismissed }
            .max { ($0.submittedAt ?? .distantPast) < ($1.submittedAt ?? .distantPast) }?
            .state
    }

    private static func hasApproval(_ pr: PullRequestSnapshot, from reviewer: String?) -> Bool {
        if let reviewer { return latestState(of: reviewer, in: pr) == .approved }
        let reviewers = Set(pr.reviews.map { $0.authorLogin.lowercased() })
        return reviewers.contains { login in
            !pr.author.isSame(as: login) && latestState(of: login, in: pr) == .approved
        }
    }
}
