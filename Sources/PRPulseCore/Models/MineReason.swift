public enum MineReason: Hashable, Sendable {
    case changesRequested
    case openThreads(Int)
    case unansweredComment
    case ciFailed
    case conflict
    case readyToMerge

    /// The rank of the first pull request that asks nothing of the viewer comes right after the last reason.
    public static let quietRankBase = 6

    /// A conflict first, then what someone said that needs an answer, then CI, then a merge.
    public var urgencyRank: Int {
        switch self {
        case .conflict: 0
        case .changesRequested: 1
        case .openThreads: 2
        case .unansweredComment: 3
        case .ciFailed: 4
        case .readyToMerge: 5
        }
    }

    public var kind: String {
        switch self {
        case .changesRequested: "changesRequested"
        case .openThreads: "openThreads"
        case .unansweredComment: "unansweredComment"
        case .ciFailed: "ciFailed"
        case .conflict: "conflict"
        case .readyToMerge: "readyToMerge"
        }
    }
}
