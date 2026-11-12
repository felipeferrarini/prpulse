/// Why one of the viewer's pull requests asks nothing of them: whose turn it is instead.
public enum QuietState: Int, Sendable {
    /// Nobody has reviewed it yet.
    case noReview
    /// Reviewed, and it needs nothing from the viewer right now.
    case inReview
    case draft
}

/// One of the viewer's own pull requests. Every one of them is listed; `reasons` holds what asks something of the viewer.
public struct MineItem: Equatable, Sendable {
    public let pr: PullRequestSnapshot
    public let reasons: [MineReason]
    /// Only meaningful while `reasons` is empty.
    public let quiet: QuietState

    public init(pr: PullRequestSnapshot, reasons: [MineReason], quiet: QuietState = .inReview) {
        self.pr = pr
        self.reasons = reasons
        self.quiet = quiet
    }

    public var needsAction: Bool { !reasons.isEmpty }
    public var primary: MineReason? { reasons.first }
    public var isWaitingForReview: Bool { reasons.isEmpty && quiet == .noReview }

    /// Smaller is more urgent: a conflict, something to answer, a failing check, a merge, then the ones that wait on others.
    public var priorityRank: Int {
        reasons.first?.urgencyRank ?? (MineReason.quietRankBase + (quiet == .noReview ? 0 : quiet == .inReview ? 1 : 2))
    }
}
