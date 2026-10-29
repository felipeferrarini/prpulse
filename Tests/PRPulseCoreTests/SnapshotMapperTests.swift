import Foundation
import Testing
@testable import PRPulseCore

@Test func mapperBuildsSnapshotFromMineFixture() throws {
    let pr = try SnapshotMapper.snapshot(from: fixtureNode("mine-page"))

    #expect(pr.ref == PullRequestRef(owner: "acme", repo: "web", number: 348))
    #expect(pr.title == "Fix class filter")
    #expect(pr.reviewDecision == .changesRequested)
    #expect(pr.mergeable == .mergeable)
    #expect(pr.mergeState == .blocked)
    #expect(pr.checks == .none)
    #expect(pr.requestedReviewers == ["sam"])
    #expect(pr.createdAt == Date(timeIntervalSince1970: 1_792_490_400))
}

@Test func mapperMapsThreadsWithGhostFirstAuthor() throws {
    let pr = try SnapshotMapper.snapshot(from: fixtureNode("mine-page"))

    #expect(pr.threads.count == 2)
    #expect(pr.threads[0] == ThreadSnapshot(isResolved: false, firstAuthor: Actor(login: "sam", isBot: false)))
    #expect(pr.threads[1] == ThreadSnapshot(isResolved: true, firstAuthor: .ghost))
}

@Test func mapperFoldsSubmittedReviewBodiesIntoComments() throws {
    let pr = try SnapshotMapper.snapshot(from: fixtureNode("mine-page"))

    #expect(pr.comments.count == 3)
    let bodies = pr.comments.filter(\.isReviewBody)
    #expect(bodies.count == 1)
    #expect(bodies[0].author.login == "sam")
    #expect(pr.reviews.count == 3)
}

@Test func mapperMarksBotAndGhostActors() throws {
    let pr = try SnapshotMapper.snapshot(from: fixtureNode("mine-page"))
    let loose = pr.comments.filter { !$0.isReviewBody }

    #expect(loose[0].author == Actor(login: "coderabbitai", isBot: true))
    #expect(loose[1].author == .ghost)
}

@Test func mapperLeavesCommitAuthorNilWhenNotLinkedToAnAccount() throws {
    let pr = try SnapshotMapper.snapshot(from: fixtureNode("mine-page"))

    #expect(pr.commits.map(\.authorLogin) == ["me", nil])
}

@Test func mapperToleratesMissingOptionalBlocksAndNullAuthor() throws {
    var node = minimalPR(number: 9)
    node["author"] = NSNull()
    let pr = try SnapshotMapper.snapshot(from: node)

    #expect(pr.author == .ghost)
    #expect(pr.threads.isEmpty && pr.comments.isEmpty && pr.commits.isEmpty && pr.reviews.isEmpty)
    #expect(pr.mergeState == .unknown)
}

@Test func mapperThrowsMalformedWhenNumberIsMissing() {
    #expect(throws: GitHubError.self) {
        try SnapshotMapper.snapshot(from: ["title": "x"])
    }
}

@Test func mapperDropsNullEntriesInsteadOfTheWholeList() throws {
    var node = minimalPR(number: 9)
    node["comments"] = ["nodes": [
        ["createdAt": "2026-10-02T00:00:00Z", "author": ["login": "sam", "__typename": "User"]],
        NSNull(),
        ["createdAt": "2026-10-03T00:00:00Z", "author": ["login": "mia", "__typename": "User"]],
    ]]
    node["reviewThreads"] = ["nodes": [NSNull(), ["isResolved": false, "comments": ["nodes": [["author": ["login": "sam", "__typename": "User"]]]]]]]

    let pr = try SnapshotMapper.snapshot(from: node)

    #expect(pr.comments.count == 2)
    #expect(pr.threads.count == 1)
}

@Test func mapperDoesNotTurnApprovalBodiesIntoComments() throws {
    var node = minimalPR(number: 9)
    node["reviews"] = ["nodes": [
        ["state": "APPROVED", "body": "LGTM!", "submittedAt": "2026-10-02T00:00:00Z", "author": ["login": "sam", "__typename": "User"]],
        ["state": "COMMENTED", "body": "One question", "submittedAt": "2026-10-03T00:00:00Z", "author": ["login": "mia", "__typename": "User"]],
    ]]

    let pr = try SnapshotMapper.snapshot(from: node)

    #expect(pr.comments.map(\.author.login) == ["mia"])
    #expect(pr.reviews.count == 2)
}

@Test func mapperExposesThreadContinuationWhenThereAreMorePages() throws {
    var node = minimalPR(number: 9)
    node["id"] = "PR_node"
    node["reviewThreads"] = ["pageInfo": ["hasNextPage": true, "endCursor": "T1"], "nodes": []]

    let continuation = try #require(SnapshotMapper.threadContinuation(from: node))
    #expect(continuation.id == "PR_node")
    #expect(continuation.cursor == "T1")

    node["reviewThreads"] = ["pageInfo": ["hasNextPage": false, "endCursor": NSNull()], "nodes": []]
    #expect(SnapshotMapper.threadContinuation(from: node) == nil)
}
