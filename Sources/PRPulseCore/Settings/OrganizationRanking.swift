import Foundation

struct OrganizationActivity: Equatable, Sendable {
    let login: String
    let recentPullRequests: Int
    let lastActivity: Date?
}

enum OrganizationRanking {
    /// Most active first (PRs the viewer is involved in), then the most recent one, then by name.
    static func order(_ activity: [OrganizationActivity]) -> [String] {
        activity.sorted(by: precedes).map(\.login)
    }

    static func alphabetical(_ logins: [String]) -> [String] {
        logins.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private static func precedes(_ lhs: OrganizationActivity, _ rhs: OrganizationActivity) -> Bool {
        if lhs.recentPullRequests != rhs.recentPullRequests { return lhs.recentPullRequests > rhs.recentPullRequests }
        if lhs.lastActivity != rhs.lastActivity { return (lhs.lastActivity ?? .distantPast) > (rhs.lastActivity ?? .distantPast) }
        return lhs.login.localizedCaseInsensitiveCompare(rhs.login) == .orderedAscending
    }
}
