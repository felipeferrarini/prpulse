import Foundation

public struct OrganizationActivity: Equatable, Sendable {
    public let login: String
    public let recentPullRequests: Int
    public let lastActivity: Date?

    public init(login: String, recentPullRequests: Int, lastActivity: Date?) {
        self.login = login
        self.recentPullRequests = recentPullRequests
        self.lastActivity = lastActivity
    }
}

enum OrganizationRanking {
    /// Most active first (PRs the viewer is involved in), then the most recent one, then by name.
    static func sorted(_ activity: [OrganizationActivity]) -> [OrganizationActivity] {
        activity.sorted(by: precedes)
    }

    static func order(_ activity: [OrganizationActivity]) -> [String] {
        sorted(activity).map(\.login)
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
