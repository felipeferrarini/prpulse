import Foundation

public struct ViewerInfo: Equatable, Sendable {
    public let login: String
    public let organizations: [String]
    /// PRs the viewer was involved in over the last months, per organization, when that could be loaded.
    public let recentPullRequests: [String: Int]

    public init(login: String, organizations: [String], recentPullRequests: [String: Int] = [:]) {
        self.login = login
        self.organizations = organizations
        self.recentPullRequests = recentPullRequests
    }
}
