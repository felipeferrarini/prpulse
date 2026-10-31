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

public struct GitHubClient: Sendable {
    static let searchEpoch = Date(timeIntervalSince1970: 1_420_070_400)
    static let searchEndMargin: TimeInterval = 86_400
    private static let activityLookback: TimeInterval = 90 * 86_400
    private static let searchCap = 1000
    private static let checksBatchSize = 25

    private struct Page {
        let issueCount: Int
        let pullRequests: [PullRequestSnapshot]
        let nextCursor: String?
    }

    private let transport: GraphQLTransport
    private let clock: Clock
    private let stackSupport = StackSupport()

    public init(transport: GraphQLTransport, clock: Clock) {
        self.transport = transport
        self.clock = clock
    }

    public func viewer() async throws -> ViewerInfo {
        let data = try await execute(Queries.viewer, [:])
        guard let viewer = data.object("viewer"), let login = viewer.string("login") else {
            throw GitHubError.malformed("viewer is missing")
        }
        return ViewerInfo(login: login, organizations: viewer.nodes("organizations").compactMap { $0.string("login") })
    }

    /// Orders the organizations by how much the viewer worked in them over the last months.
    public func rankedOrganizations(_ organizations: [String], viewer: String) async throws -> [String] {
        try await organizationActivity(organizations, viewer: viewer).map(\.login)
    }

    /// The organizations with how much the viewer worked in each, most active first.
    public func organizationActivity(_ organizations: [String], viewer: String) async throws -> [OrganizationActivity] {
        guard !organizations.isEmpty else { return [] }
        let since = clock.now.addingTimeInterval(-Self.activityLookback).formatted(.iso8601.year().month().day())
        let data = try await execute(Queries.activity(organizations: organizations, viewer: viewer, since: since), [:])
        let activity = organizations.enumerated().map { index, login in
            let search = data.object("o\(index)")
            return OrganizationActivity(
                login: login,
                recentPullRequests: search?.int("issueCount") ?? 0,
                lastActivity: parseDate(search?.nodes("nodes").first?.string("updatedAt"))
            )
        }
        return OrganizationRanking.sorted(activity)
    }

    /// Names of the owner's non-archived repositories, most recently pushed first.
    public func repositories(owner: String) async throws -> [String] {
        var names: [String] = []
        var cursor: String?
        repeat {
            var variables: [String: Any] = ["owner": owner]
            if let cursor { variables["after"] = cursor }
            let data = try await execute(Queries.repositories, variables)
            let connection = data.object("repositoryOwner")?.object("repositories")
            names += (connection?.array("nodes") ?? []).compactMap { $0.string("name") }
            let info = connection?.object("pageInfo")
            cursor = info?.bool("hasNextPage") == true ? info?.string("endCursor") : nil
        } while cursor != nil
        return names
    }

    public func verifyOrganization(_ org: String) async throws {
        let data = try await execute(Queries.organization, ["login": org])
        guard data.object("organization") != nil else { throw GitHubError.organizationNotAccessible(org) }
    }

    public func minePullRequests(org: String, viewer: String) async throws -> [PullRequestSnapshot] {
        let base = "org:\(org) is:pr is:open author:\(viewer) archived:false"
        let pullRequests = try await fetchWindow(base: base, fragment: .mine, size: 25, window: fullWindow)
        return try await applyChecks(to: unique(pullRequests))
    }

    public func reviewPullRequests(
        org: String,
        viewer: String,
        ignoredRepos: Set<String>
    ) async throws -> [PullRequestSnapshot] {
        let exclusions = ignoredRepos.sorted().map { " -repo:\(org)/\($0)" }.joined()
        let base = "org:\(org) is:pr is:open archived:false -author:\(viewer) -reviewed-by:\(viewer)\(exclusions)"
        let listed = try await fetchWindow(base: base, fragment: .review, size: 50, window: fullWindow)

        let requestedBase = "org:\(org) is:pr is:open archived:false -author:\(viewer) review-requested:\(viewer)"
        let requested = try await fetchWindow(base: requestedBase, fragment: .review, size: 50, window: fullWindow)
        return unique(requested.map { markingRequested($0, viewer: viewer) } + listed)
    }

    /// GitHub's `review-requested:` search also matches PRs where a team of the viewer was requested
    /// (for example through CODEOWNERS), so everything it returns is a request to the viewer.
    private func markingRequested(_ pr: PullRequestSnapshot, viewer: String) -> PullRequestSnapshot {
        let alreadyListed = pr.requestedReviewers.contains { $0.caseInsensitiveCompare(viewer) == .orderedSame }
        return alreadyListed ? pr : pr.with(requestedReviewers: pr.requestedReviewers + [viewer])
    }

    private var fullWindow: DateWindow {
        DateWindow(start: Self.searchEpoch, end: clock.now.addingTimeInterval(Self.searchEndMargin))
    }

    private func fetchWindow(
        base: String,
        fragment: PRFragment,
        size: Int,
        window: DateWindow
    ) async throws -> [PullRequestSnapshot] {
        let query = "\(base) sort:created-asc \(window.qualifier)"
        let first = try await fetchPage(query, fragment, size: size, after: nil)
        guard first.issueCount > Self.searchCap, window.canSplit else {
            return try await collect(query, fragment, size: size, startingWith: first)
        }
        let (older, newer) = window.halves()
        let olderPRs = try await fetchWindow(base: base, fragment: fragment, size: size, window: older)
        let newerPRs = try await fetchWindow(base: base, fragment: fragment, size: size, window: newer)
        return olderPRs + newerPRs
    }

    private func collect(
        _ query: String,
        _ fragment: PRFragment,
        size: Int,
        startingWith firstPage: Page? = nil
    ) async throws -> [PullRequestSnapshot] {
        var page: Page
        if let firstPage {
            page = firstPage
        } else {
            page = try await fetchPage(query, fragment, size: size, after: nil)
        }
        var all = page.pullRequests
        while let cursor = page.nextCursor {
            page = try await fetchPage(query, fragment, size: size, after: cursor)
            all += page.pullRequests
        }
        return all
    }

    private func fetchPage(_ query: String, _ fragment: PRFragment, size: Int, after: String?) async throws -> Page {
        var variables: [String: Any] = ["q": query, "first": size]
        if let after { variables["after"] = after }
        let search = try await searchData(fragment, variables).object("search")
        let nodes = (search?.array("nodes") ?? []).filter { $0.int("number") != nil }
        let pageInfo = search?.object("pageInfo")
        let hasNext = pageInfo?.bool("hasNextPage") ?? false
        return Page(
            issueCount: search?.int("issueCount") ?? 0,
            pullRequests: try await withAllThreads(nodes),
            nextCursor: hasNext ? pageInfo?.string("endCursor") : nil
        )
    }

    /// Asks for the stacks too. A host that does not have them (GitHub Enterprise Server, so far) refuses the whole query, so
    /// it is asked again without them, and without them from then on.
    private func searchData(_ fragment: PRFragment, _ variables: [String: Any]) async throws -> JSONObject {
        guard stackSupport.isSupported else { return try await execute(Queries.search(fragment, includesStacks: false), variables) }
        do {
            return try await execute(Queries.search(fragment), variables)
        } catch GitHubError.malformed(let message) where message.localizedCaseInsensitiveContains("stack") {
            stackSupport.isSupported = false
            return try await execute(Queries.search(fragment, includesStacks: false), variables)
        }
    }

    private func withAllThreads(_ nodes: [JSONObject]) async throws -> [PullRequestSnapshot] {
        var result: [PullRequestSnapshot] = []
        for node in nodes {
            let snapshot = try SnapshotMapper.snapshot(from: node)
            guard let continuation = SnapshotMapper.threadContinuation(from: node) else {
                result.append(snapshot)
                continue
            }
            result.append(snapshot.with(threads: snapshot.threads + (try await remainingThreads(continuation))))
        }
        return result
    }

    private func remainingThreads(_ start: (id: String, cursor: String)) async throws -> [ThreadSnapshot] {
        var threads: [ThreadSnapshot] = []
        var cursor: String? = start.cursor
        while let after = cursor {
            let data = try await execute(Queries.reviewThreadsPage, ["id": start.id, "after": after])
            let connection = data.object("node")?.object("reviewThreads")
            threads += SnapshotMapper.threads(connection?.array("nodes") ?? [])
            let info = connection?.object("pageInfo")
            cursor = info?.bool("hasNextPage") == true ? info?.string("endCursor") : nil
        }
        return threads
    }

    private func applyChecks(to pullRequests: [PullRequestSnapshot]) async throws -> [PullRequestSnapshot] {
        let targets = pullRequests.filter { !$0.isDraft }
        var states: [PullRequestRef: ChecksState] = [:]
        for batch in stride(from: 0, to: targets.count, by: Self.checksBatchSize) {
            let chunk = Array(targets[batch ..< min(batch + Self.checksBatchSize, targets.count)])
            let data = try await execute(Queries.checks(for: chunk.map(\.ref)), [:])
            for (index, pr) in chunk.enumerated() {
                states[pr.ref] = ChecksMapper.state(rollup: rollup(in: data.object("pr\(index)")))
            }
        }
        return pullRequests.map { $0.with(checks: states[$0.ref] ?? $0.checks) }
    }

    private func rollup(in repository: JSONObject?) -> JSONObject? {
        let commit = repository?.object("pullRequest")?.nodes("commits").first?.object("commit")
        return commit?.object("statusCheckRollup")
    }

    private func unique(_ pullRequests: [PullRequestSnapshot]) -> [PullRequestSnapshot] {
        var seen = Set<PullRequestRef>()
        return pullRequests.filter { seen.insert($0.ref).inserted }
    }

    private func execute(_ query: String, _ variables: [String: Any]) async throws -> JSONObject {
        try GraphQLResponse.data(from: try await transport.send(query: query, variables: variables))
    }
}

/// Whether the host knows GitHub's stacks, learned from the first answer.
private final class StackSupport: @unchecked Sendable {
    private let lock = NSLock()
    private var supported = true

    var isSupported: Bool {
        get { lock.withLock { supported } }
        set { lock.withLock { supported = newValue } }
    }
}
