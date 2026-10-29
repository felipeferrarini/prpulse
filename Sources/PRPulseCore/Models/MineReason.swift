public enum MineReason: Hashable, Sendable {
    case changesRequested
    case openThreads(Int)
    case unansweredComment
    case ciFailed
    case conflict
    case readyToMerge

    public var urgencyRank: Int {
        switch self {
        case .changesRequested: 0
        case .openThreads: 1
        case .unansweredComment: 2
        case .ciFailed: 3
        case .conflict: 4
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
