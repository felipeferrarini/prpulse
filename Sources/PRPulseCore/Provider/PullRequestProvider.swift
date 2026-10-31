/// Where the pull requests come from. The app talks to this, so a forge other than GitHub only has to implement it.
public protocol PullRequestProvider: Sendable {
    func viewer() async throws -> ViewerInfo
    func verifyOrganization(_ org: String) async throws
    func minePullRequests(org: String, viewer: String) async throws -> [PullRequestSnapshot]
    func reviewPullRequests(org: String, viewer: String, ignoredRepos: Set<String>) async throws -> [PullRequestSnapshot]
    func repositories(owner: String) async throws -> [String]
    func organizationActivity(_ organizations: [String], viewer: String) async throws -> [OrganizationActivity]
}
