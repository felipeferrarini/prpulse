import Foundation

/// A person who can be nudged on some of the pull requests that were picked, each with the nudge they would get.
public struct NudgeTarget: Equatable, Identifiable, Sendable {
    public struct Item: Equatable, Sendable {
        public let pr: PullRequestSnapshot
        public let candidate: NudgeCandidate
    }

    public let login: String
    public let items: [Item]

    public var id: String { login.lowercased() }
}

/// Who can be nudged about several of the viewer's pull requests at once, and on which of them.
public enum NudgeBatch {
    /// Everyone allowed on at least one of the pull requests, the one allowed on most first. On a pull request where somebody is
    /// blocked, or where they would only be told to merge, they are left out: the rest of their nudges still go.
    public static func targets(
        for pullRequests: [PullRequestSnapshot],
        candidates: (PullRequestSnapshot) -> [NudgeCandidate]
    ) -> [NudgeTarget] {
        var order: [String] = []
        var logins: [String: String] = [:]
        var items: [String: [NudgeTarget.Item]] = [:]
        for pr in pullRequests {
            for candidate in candidates(pr) where candidate.kind == .review && candidate.isAllowed {
                let key = candidate.login.lowercased()
                if logins[key] == nil {
                    logins[key] = candidate.login
                    order.append(key)
                }
                items[key, default: []].append(NudgeTarget.Item(pr: pr, candidate: candidate))
            }
        }
        return order
            .map { NudgeTarget(login: logins[$0] ?? $0, items: items[$0] ?? []) }
            .sorted { a, b in
                a.items.count != b.items.count ? a.items.count > b.items.count : a.login.localizedCaseInsensitiveCompare(b.login) == .orderedAscending
            }
    }
}
