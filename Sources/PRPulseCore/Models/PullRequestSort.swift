import Foundation

/// How a list of pull requests is ordered. `priority` is the order each list has on its own.
public enum PullRequestSort: String, CaseIterable, Codable, Sendable {
    case priority, oldest, newest, activity, repository, author

    /// The author of the viewer's own pull requests is always the viewer, so that list has nothing to sort by it.
    public static let mineOptions: [PullRequestSort] = [.priority, .oldest, .newest, .activity, .repository]
    public static let reviewOptions: [PullRequestSort] = allCases
}

extension PullRequestSnapshot {
    /// The latest thing that happened on the pull request: it was opened, a commit, a comment or a review.
    public var lastActivity: Date {
        let dates = commits.map(\.authoredDate) + comments.map(\.createdAt) + reviews.compactMap(\.submittedAt)
        return dates.reduce(createdAt) { max($0, $1) }
    }
}

public enum ListOrder {
    public static func sorted(_ items: [MineItem], by sort: PullRequestSort) -> [MineItem] {
        items.sorted { a, b in
            order(a.pr, b.pr, by: sort) ?? priority(a, b)
        }
    }

    public static func sorted(_ items: [ReviewItem], by sort: PullRequestSort) -> [ReviewItem] {
        items.sorted { a, b in
            order(a.pr, b.pr, by: sort) ?? priority(a, b)
        }
    }

    /// The urgent first, then the one that waited longest.
    private static func priority(_ a: MineItem, _ b: MineItem) -> Bool {
        if a.priorityRank != b.priorityRank { return a.priorityRank < b.priorityRank }
        return age(a.pr, b.pr)
    }

    /// Requests to the viewer, then the pull requests that wait for the team, then the ones the viewer reviewed (the mergeable
    /// first), then drafts; the one waiting longest first within each.
    private static func priority(_ a: ReviewItem, _ b: ReviewItem) -> Bool {
        if a.status != b.status { return a.status.rawValue < b.status.rawValue }
        return age(a.pr, b.pr)
    }

    private static func age(_ a: PullRequestSnapshot, _ b: PullRequestSnapshot) -> Bool {
        if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
        return a.ref.number < b.ref.number
    }

    /// The order by `sort` alone: nil when the two tie, so the caller breaks it with the priority.
    private static func order(_ a: PullRequestSnapshot, _ b: PullRequestSnapshot, by sort: PullRequestSort) -> Bool? {
        switch sort {
        case .priority: nil
        case .oldest: a.createdAt == b.createdAt ? nil : a.createdAt < b.createdAt
        case .newest: a.createdAt == b.createdAt ? nil : a.createdAt > b.createdAt
        case .activity: a.lastActivity == b.lastActivity ? nil : a.lastActivity > b.lastActivity
        case .repository: text(repository(a), repository(b))
        case .author: text(a.author.login, b.author.login)
        }
    }

    private static func repository(_ pr: PullRequestSnapshot) -> String {
        "\(pr.ref.owner)/\(pr.ref.repo)"
    }

    private static func text(_ a: String, _ b: String) -> Bool? {
        switch a.localizedCaseInsensitiveCompare(b) {
        case .orderedAscending: true
        case .orderedDescending: false
        case .orderedSame: nil
        }
    }
}
