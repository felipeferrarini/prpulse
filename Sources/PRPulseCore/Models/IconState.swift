import Foundation

public enum IconState: Equatable, Sendable {
    case upToDate
    case pending(Int)
    case fresh(Int)
    case error

    public static func make(state: LoadState, summary: Summary?, freshUntil: Date?, now: Date) -> IconState {
        if case .failed = state { return .error }
        let total = summary?.total ?? 0
        guard total > 0 else { return .upToDate }
        if let freshUntil, freshUntil > now { return .fresh(total) }
        return .pending(total)
    }
}
