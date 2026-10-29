import Foundation
import Testing
@testable import PRPulseCore

private let now = Date(timeIntervalSince1970: 1_793_000_000)

private func client(_ transport: FakeTransport) -> GitHubClient {
    GitHubClient(transport: transport, clock: FixedClock(now: now))
}

private func emptySearch() -> Data {
    searchResponse(nodes: [])
}

@Test func viewerParsesLoginAndOrganizations() async throws {
    let transport = FakeTransport { _, _ in try fixtureData("viewer") }
    let info = try await client(transport).viewer()

    #expect(info.login == "me")
    #expect(info.organizations == ["acme", "other-org"])
}

@Test func samlEnforcementMapsToSsoRequired() async throws {
    let transport = FakeTransport { _, _ in try fixtureData("saml-error") }

    await #expect(throws: GitHubError.ssoRequired(org: nil)) {
        try await client(transport).minePullRequests(org: "acme", viewer: "me")
    }
}

@Test func rateLimitedGraphqlErrorMaps() async throws {
    let body = json(["data": NSNull(), "errors": [["type": "RATE_LIMITED", "message": "API rate limit exceeded"]]])
    let transport = FakeTransport { _, _ in body }

    await #expect(throws: GitHubError.rateLimited(retryAfter: nil)) {
        try await client(transport).viewer()
    }
}

@Test func partialErrorsWithDataAreTolerated() async throws {
    let body = json([
        "data": ["viewer": ["login": "me", "organizations": ["nodes": []]]],
        "errors": [["type": "NOT_FOUND", "message": "Could not resolve to a Repository"]],
    ])
    let transport = FakeTransport { _, _ in body }

    #expect(try await client(transport).viewer().login == "me")
}

@Test func mineSearchBuildsExpectedQueryAndMapsFixture() async throws {
    let transport = FakeTransport { query, _ in
        query.contains("pr0:") ? json(["data": [:]]) : try fixtureData("mine-page")
    }
    let prs = try await client(transport).minePullRequests(org: "acme", viewer: "me")

    #expect(prs.map(\.ref.number) == [348])
    #expect(transport.searchQueries.first?.hasPrefix("org:acme is:pr is:open author:me archived:false sort:created-asc created:") == true)
}

@Test func searchPaginatesWithCursor() async throws {
    let transport = FakeTransport { query, variables in
        if query.contains("pr0:") { return json(["data": [:]]) }
        switch variables["after"] as? String {
        case nil: return searchResponse(nodes: [minimalPR(number: 1)], issueCount: 2, hasNextPage: true, endCursor: "A")
        default: return searchResponse(nodes: [minimalPR(number: 2)], issueCount: 2)
        }
    }
    let prs = try await client(transport).minePullRequests(org: "org", viewer: "me")

    #expect(prs.map(\.ref.number) == [1, 2])
}

@Test func mineAppliesRequiredChecksFromBatchedQuery() async throws {
    let rollup: [String: Any] = [
        "state": "FAILURE",
        "contexts": ["nodes": [["__typename": "CheckRun", "name": "pr-validated", "conclusion": "FAILURE", "status": "COMPLETED", "isRequired": true]]],
    ]
    let batch = json(["data": ["pr0": ["pullRequest": ["commits": ["nodes": [["commit": ["statusCheckRollup": rollup]]]]]]]])
    let transport = FakeTransport { query, _ in
        query.contains("pr0:") ? batch : searchResponse(nodes: [minimalPR(number: 5)])
    }
    let prs = try await client(transport).minePullRequests(org: "org", viewer: "me")

    #expect(prs.first?.checks == .failing)
}

@Test func draftPullRequestsAreNotSentToTheChecksQuery() async throws {
    var draft = minimalPR(number: 6)
    draft["isDraft"] = true
    let transport = FakeTransport { _, _ in searchResponse(nodes: [draft]) }
    _ = try await client(transport).minePullRequests(org: "org", viewer: "me")

    #expect(!transport.calls.contains { $0.query.contains("pr0:") })
}

@Test func searchOver1000SplitsDateWindowWithoutDuplicates() async throws {
    let full = DateWindow(start: GitHubClient.searchEpoch, end: now.addingTimeInterval(GitHubClient.searchEndMargin))
    let (first, second) = full.halves()
    let transport = FakeTransport { _, variables in
        let q = variables["q"] as? String ?? ""
        if q.contains("review-requested") { return searchResponse(nodes: []) }
        if q.contains(full.qualifier) { return searchResponse(nodes: [], issueCount: 1500) }
        if q.contains(first.qualifier) { return searchResponse(nodes: [minimalPR(number: 1), minimalPR(number: 2)], issueCount: 700) }
        if q.contains(second.qualifier) { return searchResponse(nodes: [minimalPR(number: 2), minimalPR(number: 3)], issueCount: 800) }
        return searchResponse(nodes: [])
    }
    let prs = try await client(transport).reviewPullRequests(org: "org", viewer: "me", ignoredRepos: [])

    #expect(prs.map(\.ref.number).sorted() == [1, 2, 3])
    let windowQueries = Set(transport.searchQueries.filter { $0.contains("created:") && !$0.contains("review-requested") })
    #expect(windowQueries.count == 3)
}

@Test func reviewQueryExcludesIgnoredReposAndAddsReviewRequestedQuery() async throws {
    let transport = FakeTransport { _, variables in
        let q = variables["q"] as? String ?? ""
        if q.contains("review-requested:me") { return searchResponse(nodes: [minimalPR(number: 7, repo: "docs")]) }
        return searchResponse(nodes: [minimalPR(number: 7, repo: "docs"), minimalPR(number: 8)])
    }
    let prs = try await client(transport).reviewPullRequests(org: "org", viewer: "me", ignoredRepos: ["docs", "infra"])

    let windowed = try #require(transport.searchQueries.first { $0.contains("created:") })
    for part in ["org:org", "is:pr", "is:open", "-author:me", "-reviewed-by:me", "-repo:org/docs", "-repo:org/infra"] {
        #expect(windowed.contains(part), "missing \(part)")
    }
    #expect(transport.searchQueries.contains { $0.contains("review-requested:me") && !$0.contains("-repo:") })
    #expect(prs.map(\.ref.number).sorted() == [7, 8])
}

@Test func searchSkipsNullNodesWithoutDroppingThePage() async throws {
    let rawPage = json(["data": ["search": ["issueCount": 3, "pageInfo": ["hasNextPage": false], "nodes": [minimalPR(number: 1), NSNull(), minimalPR(number: 3)]]]])
    let withNull = FakeTransport { query, _ in query.contains("pr0:") ? json(["data": [:]]) : rawPage }

    #expect(try await client(withNull).minePullRequests(org: "org", viewer: "me").map(\.ref.number) == [1, 3])
}

@Test func reviewThreadsBeyondTheFirstPageAreFetched() async throws {
    func threadNode(resolved: Bool) -> [String: Any] {
        ["isResolved": resolved, "comments": ["nodes": [["author": ["login": "sam", "__typename": "User"]]]]]
    }
    var first = minimalPR(number: 5, author: "me")
    first["id"] = "PR_5"
    first["reviewThreads"] = ["pageInfo": ["hasNextPage": true, "endCursor": "T1"], "nodes": [threadNode(resolved: true)]]
    let more = json(["data": ["node": ["reviewThreads": ["pageInfo": ["hasNextPage": false], "nodes": [threadNode(resolved: false), threadNode(resolved: false)]]]]])

    let transport = FakeTransport { query, _ in
        if query.contains("node(id") { return more }
        return query.contains("pr0:") ? json(["data": [:]]) : searchResponse(nodes: [first])
    }
    let prs = try await client(transport).minePullRequests(org: "org", viewer: "me")

    #expect(prs[0].threads.count == 3)
    #expect(prs[0].threads.filter { !$0.isResolved }.count == 2)
    let call = try #require(transport.calls.first { $0.query.contains("node(id") })
    #expect(call.variables["id"] as? String == "PR_5")
    #expect(call.variables["after"] as? String == "T1")
}

@Test func organizationCheckPassesWhenTheOrganizationIsVisible() async throws {
    let transport = FakeTransport { _, _ in json(["data": ["organization": ["login": "acme"]]]) }
    try await client(transport).verifyOrganization("acme")
}

@Test func organizationCheckFailsWhenTheOrganizationIsNullForThisToken() async throws {
    let transport = FakeTransport { _, _ in json(["data": ["organization": NSNull()]]) }

    await #expect(throws: GitHubError.organizationNotAccessible("acme")) {
        try await client(transport).verifyOrganization("acme")
    }
}

@Test func organizationCheckSurfacesSamlEnforcement() async throws {
    let transport = FakeTransport { _, _ in try fixtureData("saml-error") }

    await #expect(throws: GitHubError.ssoRequired(org: nil)) {
        try await client(transport).verifyOrganization("acme")
    }
}

@Test func pullRequestsFoundByTheReviewRequestedSearchCountAsRequestedEvenForTeamRequests() async throws {
    var teamOnly = minimalPR(number: 7, repo: "docs")
    teamOnly["reviewRequests"] = ["nodes": [["requestedReviewer": [:]]]]
    let transport = FakeTransport { _, variables in
        let q = variables["q"] as? String ?? ""
        return searchResponse(nodes: q.contains("review-requested:me") ? [teamOnly] : [])
    }

    let prs = try await client(transport).reviewPullRequests(org: "org", viewer: "me", ignoredRepos: ["docs"])

    #expect(prs.first?.requestedReviewers.contains("me") == true)
    let shown = ReviewClassifier.items(from: prs, viewer: "me", ignoredRepos: ["docs"])
    #expect(shown.map(\.pr.ref.number) == [7])
}

@Test func theRequestedCopyWinsWhenAPullRequestIsInBothSearches() async throws {
    let transport = FakeTransport { _, variables in
        searchResponse(nodes: [minimalPR(number: 8)])
    }

    let prs = try await client(transport).reviewPullRequests(org: "org", viewer: "me", ignoredRepos: [])

    #expect(prs.count == 1)
    #expect(prs[0].requestedReviewers == ["me"])
}

@Test func viewerIsNotAddedTwiceWhenAlreadyRequestedDirectly() async throws {
    var direct = minimalPR(number: 9)
    direct["reviewRequests"] = ["nodes": [["requestedReviewer": ["login": "Me"]]]]
    let transport = FakeTransport { _, variables in
        let q = variables["q"] as? String ?? ""
        return searchResponse(nodes: q.contains("review-requested:me") ? [direct] : [])
    }

    let prs = try await client(transport).reviewPullRequests(org: "org", viewer: "me", ignoredRepos: [])

    #expect(prs[0].requestedReviewers == ["Me"])
}

@Test func searchWindowEndsAfterTheLocalClockToToleratesSkew() async throws {
    let transport = FakeTransport { _, _ in searchResponse(nodes: []) }
    _ = try await client(transport).reviewPullRequests(org: "org", viewer: "me", ignoredRepos: [])

    let expected = DateWindow(start: GitHubClient.searchEpoch, end: now.addingTimeInterval(GitHubClient.searchEndMargin)).qualifier
    #expect(GitHubClient.searchEndMargin >= 3600)
    #expect(transport.searchQueries.contains { $0.contains(expected) })
}

@Test func mineSearchOver1000SplitsTheWindowToo() async throws {
    let full = DateWindow(start: GitHubClient.searchEpoch, end: now.addingTimeInterval(GitHubClient.searchEndMargin))
    let (first, second) = full.halves()
    let transport = FakeTransport { query, variables in
        if query.contains("pr0:") { return json(["data": [:]]) }
        let q = variables["q"] as? String ?? ""
        if q.contains(full.qualifier) { return searchResponse(nodes: [], issueCount: 1200) }
        if q.contains(first.qualifier) { return searchResponse(nodes: [minimalPR(number: 1, author: "me")], issueCount: 500) }
        if q.contains(second.qualifier) { return searchResponse(nodes: [minimalPR(number: 2, author: "me")], issueCount: 700) }
        return searchResponse(nodes: [])
    }

    let prs = try await client(transport).minePullRequests(org: "org", viewer: "me")

    #expect(prs.map(\.ref.number).sorted() == [1, 2])
}

@Test func reviewRequestedSearchOver1000SplitsTheWindowToo() async throws {
    let full = DateWindow(start: GitHubClient.searchEpoch, end: now.addingTimeInterval(GitHubClient.searchEndMargin))
    let (first, second) = full.halves()
    let transport = FakeTransport { _, variables in
        let q = variables["q"] as? String ?? ""
        guard q.contains("review-requested:me") else { return searchResponse(nodes: []) }
        if q.contains(full.qualifier) { return searchResponse(nodes: [], issueCount: 1500) }
        if q.contains(first.qualifier) { return searchResponse(nodes: [minimalPR(number: 3)], issueCount: 600) }
        if q.contains(second.qualifier) { return searchResponse(nodes: [minimalPR(number: 4)], issueCount: 900) }
        return searchResponse(nodes: [])
    }

    let prs = try await client(transport).reviewPullRequests(org: "org", viewer: "me", ignoredRepos: [])

    #expect(prs.map(\.ref.number).sorted() == [3, 4])
}

private func activityResponse(_ counts: [Int], updatedAt: String? = nil) -> Data {
    var data: [String: Any] = [:]
    for (index, count) in counts.enumerated() {
        let nodes: [[String: Any]] = count > 0 && updatedAt != nil ? [["updatedAt": updatedAt!]] : []
        data["o\(index)"] = ["issueCount": count, "nodes": nodes]
    }
    return json(["data": data])
}

@Test func organizationsAreRankedByRecentInvolvement() async throws {
    let transport = FakeTransport { _, _ in activityResponse([1, 30, 0], updatedAt: "2026-10-01T00:00:00Z") }
    let ranked = try await client(transport).rankedOrganizations(["a", "b", "c"], viewer: "me")

    #expect(ranked == ["b", "a", "c"])
}

@Test func rankingSearchesEachOrganizationInvolvingTheViewerSinceNinetyDaysAgo() async throws {
    let transport = FakeTransport { _, _ in activityResponse([0, 0]) }
    _ = try await client(transport).rankedOrganizations(["acme", "other-org"], viewer: "me")

    let query = try #require(transport.calls.first?.query)
    #expect(query.contains("org:acme is:pr involves:me updated:>=2026-07-28"))
    #expect(query.contains("org:other-org is:pr involves:me"))
    #expect(query.contains("o1: search"))
}

@Test func rankingWithoutOrganizationsSkipsTheRequest() async throws {
    let transport = FakeTransport { _, _ in Issue.record("no request expected"); return Data() }

    #expect(try await client(transport).rankedOrganizations([], viewer: "me").isEmpty)
    #expect(transport.calls.isEmpty)
}

private func repositoriesResponse(_ names: [String], next: String? = nil) -> Data {
    json(["data": ["repositoryOwner": ["repositories": [
        "pageInfo": ["hasNextPage": next != nil, "endCursor": next as Any],
        "nodes": names.map { ["name": $0] },
    ]]]])
}

@Test func repositoriesFollowPaginationAndKeepTheOrder() async throws {
    let transport = FakeTransport { _, variables in
        variables["after"] as? String == "c1" ? repositoriesResponse(["web"]) : repositoriesResponse(["api", "docs"], next: "c1")
    }
    let names = try await client(transport).repositories(owner: "acme")

    #expect(names == ["api", "docs", "web"])
    #expect(transport.calls.map { $0.variables["owner"] as? String } == ["acme", "acme"])
}

@Test func repositoriesOfAnUnknownOwnerAreEmpty() async throws {
    let transport = FakeTransport { _, _ in json(["data": ["repositoryOwner": NSNull()]]) }

    #expect(try await client(transport).repositories(owner: "ghost").isEmpty)
}

@Test func organizationActivityCarriesTheCountsInRankedOrder() async throws {
    let transport = FakeTransport { _, _ in activityResponse([2, 40, 0]) }
    let activity = try await client(transport).organizationActivity(["a", "b", "c"], viewer: "me")

    #expect(activity.map(\.login) == ["b", "a", "c"])
    #expect(activity.map(\.recentPullRequests) == [40, 2, 0])
}
