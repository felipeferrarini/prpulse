import Foundation
import Testing
@testable import PRPulseCore

private func key(_ number: Int, _ reason: String, repo: String = "app") -> PendingKey {
    PendingKey(ref: PullRequestRef(owner: "org", repo: repo, number: number), reason: reason)
}

private func summary(mine: [PullRequestSnapshot], review: [PullRequestSnapshot] = []) -> Summary {
    SummaryBuilder.build(minePRs: mine, reviewPRs: review, viewer: viewer, ignoredBots: [], ignoredRepos: [])
}

@Test func pendingKeysUseReasonKindAndNeedsReview() {
    let pr = PullRequestSnapshot.fixture(number: 1, reviewDecision: .changesRequested, threads: [thread(resolved: false)])
    let toReview = PullRequestSnapshot.fixture(number: 2, author: otherHuman)

    #expect(summary(mine: [pr], review: [toReview]).pendingKeys == [
        key(1, "changesRequested"), key(1, "openThreads"), key(2, "needsReview"),
    ])
}

@Test func newKeyNotifies() {
    let plan = NotificationPlanner.plan(current: [key(1, "conflict")], notified: [])
    #expect(plan.toNotify == [key(1, "conflict")])
    #expect(plan.notified == [key(1, "conflict")])
}

@Test func unchangedKeyDoesNotNotifyAgain() {
    let current: Set = [key(1, "conflict")]
    let plan = NotificationPlanner.plan(current: current, notified: current)
    #expect(plan.toNotify.isEmpty)
}

@Test func reasonChangeNotifiesAgain() {
    let plan = NotificationPlanner.plan(current: [key(1, "changesRequested")], notified: [key(1, "openThreads")])
    #expect(plan.toNotify == [key(1, "changesRequested")])
}

@Test func clearedThenReturnedNotifiesAgain() {
    let first = NotificationPlanner.plan(current: [key(1, "ciFailed")], notified: [])
    let cleared = NotificationPlanner.plan(current: [], notified: first.notified)
    #expect(cleared.notified.isEmpty)

    let returned = NotificationPlanner.plan(current: [key(1, "ciFailed")], notified: cleared.notified)
    #expect(returned.toNotify == [key(1, "ciFailed")])
}

@Test func threadCountChangeDoesNotNotify() {
    let few = summary(mine: [.fixture(threads: [thread(resolved: false)])])
    let many = summary(mine: [.fixture(threads: [thread(resolved: false), thread(resolved: false), thread(resolved: false)])])

    let plan = NotificationPlanner.plan(current: many.pendingKeys, notified: few.pendingKeys)
    #expect(plan.toNotify.isEmpty)
}

@Test func toNotifyIsSortedDeterministically() {
    let plan = NotificationPlanner.plan(
        current: [key(9, "conflict", repo: "b"), key(2, "conflict", repo: "a"), key(1, "ciFailed", repo: "a")],
        notified: []
    )
    #expect(plan.toNotify == [key(1, "ciFailed", repo: "a"), key(2, "conflict", repo: "a"), key(9, "conflict", repo: "b")])
}

@Test func seedMarksEverythingAsNotified() {
    let current: Set = [key(1, "conflict"), key(2, "needsReview")]
    #expect(NotificationPlanner.seed(current: current) == current)
}

@Test func notifiedStorePersistsAcrossInstances() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("prpulse-\(UUID().uuidString)/notified.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let store = NotifiedStore(fileURL: url)
    #expect(store.keys.isEmpty)
    store.replace(with: [key(1, "conflict")])

    #expect(NotifiedStore(fileURL: url).keys == [key(1, "conflict")])
}

@Test func notifiedStoreIgnoresUnreadableFile() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("prpulse-\(UUID().uuidString)/notified.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("garbage".utf8).write(to: url)

    #expect(NotifiedStore(fileURL: url).keys.isEmpty)
}
