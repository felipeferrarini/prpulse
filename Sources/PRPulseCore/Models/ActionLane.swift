/// The kind of action a pull request asks of the viewer. Reasons that call for the same action share a lane.
public enum ActionLane: CaseIterable, Hashable, Sendable {
    case review, changes, respond, ci, conflict, merge
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
        reasons.contains { $0.lane == lane }
    }
}

extension ReviewItem {
    public func matches(_ lane: ActionLane) -> Bool {
        lane == .review
    }
}

extension Summary {
    public func count(for lane: ActionLane) -> Int {
        lane == .review ? review.count : mine.filter { $0.matches(lane) }.count
    }

    /// Lanes that have something to act on, in the order they are shown.
    public var activeLanes: [ActionLane] {
        ActionLane.allCases.filter { count(for: $0) > 0 }
    }
}
