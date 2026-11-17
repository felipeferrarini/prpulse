/// A group of pull requests the viewer can single out: what asks something of them (reasons that call for the same action
/// share a lane) and where the others stand. The order is the one the filters are shown in.
public enum ActionLane: CaseIterable, Hashable, Sendable {
    // Pull requests of others
    case review
    /// Reviewed by the viewer, and it can be merged.
    case ready
    /// Reviewed by the viewer, and it cannot be merged yet.
    case reviewed
    // Pull requests of the viewer
    case conflict, changes, respond, ci, merge
    /// Nobody has reviewed it yet.
    case waiting
    /// Reviewed, and it asks nothing of the viewer.
    case inReview
    // Both
    case draft
}

extension MineReason {
    public var lane: ActionLane {
        switch self {
        case .changesRequested: .changes
        case .openThreads, .unansweredComment: .respond
        case .ciFailed: .ci
        case .conflict: .conflict
        case .readyToMerge: .merge
        }
    }
}

extension MineItem {
    public func matches(_ lane: ActionLane) -> Bool {
        switch lane {
        case .waiting: isWaitingForReview
        case .inReview: reasons.isEmpty && quiet == .inReview
        case .draft: pr.isDraft
        case .review, .ready, .reviewed: false
        case .conflict, .changes, .respond, .ci, .merge: reasons.contains { $0.lane == lane }
        }
    }
}

extension ReviewItem {
    public func matches(_ lane: ActionLane) -> Bool {
        switch lane {
        case .review: needsAction
        case .ready: status == .reviewedReady
        case .reviewed: status == .reviewed
        case .draft: pr.isDraft
        case .conflict, .changes, .respond, .ci, .merge, .waiting, .inReview: false
        }
    }
}

extension Summary {
    /// How many pull requests are in the lane, of the viewer's and of others'.
    public func count(for lane: ActionLane) -> Int {
        mine.filter { $0.matches(lane) }.count + review.filter { $0.matches(lane) }.count
    }

    /// Lanes that have something in them, in the order they are shown.
    public var activeLanes: [ActionLane] {
        ActionLane.allCases.filter { count(for: $0) > 0 }
    }
}
