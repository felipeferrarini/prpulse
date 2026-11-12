/// Where a pull request of someone else stands for the viewer. The raw value is the order of the list.
public enum ReviewStatus: Int, Sendable {
    /// The viewer was asked to review it.
    case requested
    /// Nobody asked the viewer, and the viewer has not reviewed it: it waits for someone on the team.
    case team
    /// The viewer reviewed it and it can be merged.
    case reviewedReady
    /// The viewer reviewed it and it cannot be merged yet.
    case reviewed
    case draft
}

/// A pull request of someone else. Every open one is listed; only the ones that wait for the viewer's review count.
public struct ReviewItem: Equatable, Sendable {
    public let pr: PullRequestSnapshot
    public let isRequested: Bool
    /// The viewer already sent a review.
    public let hasReviewed: Bool

    public init(pr: PullRequestSnapshot, isRequested: Bool = false, hasReviewed: Bool = false) {
        self.pr = pr
        self.isRequested = isRequested
        self.hasReviewed = hasReviewed
    }

    /// What asks the viewer for a review: a request, or a pull request the viewer has not reviewed.
    public var needsAction: Bool { isRequested || !hasReviewed }

    public var status: ReviewStatus {
        if pr.isDraft { return .draft }
        if isRequested { return .requested }
        if !hasReviewed { return .team }
        return pr.mergeState == .clean ? .reviewedReady : .reviewed
    }

    public var hasConflict: Bool { pr.mergeable == .conflicting }
}
