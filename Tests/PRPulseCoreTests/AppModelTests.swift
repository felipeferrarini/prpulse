import Foundation
import Testing
@testable import PRPulseCore

private final class ManualClock: Clock, @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_793_000_000)
}

private final class FakeSink: NotificationSink, @unchecked Sendable {
    private(set) var batches: [[PendingKey]] = []

    func deliver(_ items: [PendingKey], summary: Summary) async {
        batches.append(items)
    }
}

private final class World: @unchecked Sendable {
    var mine: [[String: Any]] = []
    var review: [[String: Any]] = []
    var failure: Error?
    var viewerLogin = "me"
    var orgAccessible = true
    var firstClientDelayMilliseconds = 0

    private let delayLock = NSLock()
    private var delayConsumed = false

    func takeFirstClientDelay() -> Int {
        delayLock.withLock {
            defer { delayConsumed = true }
            return delayConsumed ? 0 : firstClientDelayMilliseconds
        }
    }

    private let lock = NSLock()
    private var recordedQueries: [String] = []

    var seenQueries: [String] {
        lock.withLock { recordedQueries }
    }

    func respond(query: String, variables: [String: Any]) throws -> Data {
        if let failure { throw failure }
        if query.contains("organization(login") {
            let organization: Any = orgAccessible ? ["login": "org"] : NSNull()
            return json(["data": ["organization": organization]])
        }
        if query.contains("organizations(first") { return json(["data": ["viewer": ["login": viewerLogin, "organizations": ["nodes": []]]]]) }
        if query.contains("pr0:") { return json(["data": [:]]) }
        let q = variables["q"] as? String ?? ""
        lock.withLock { recordedQueries.append(q) }
        if q.contains("review-requested") { return searchResponse(nodes: []) }
        return searchResponse(nodes: q.contains("-author:") ? review : mine)
    }
}

private func changesRequestedPR(_ number: Int) -> [String: Any] {
    var node = minimalPR(number: number, author: "me")
    node["reviewDecision"] = "CHANGES_REQUESTED"
    return node
}

@MainActor
private struct Harness {
    let world = World()
    let clock = ManualClock()
    let sink = FakeSink()
    let settings: SettingsStore
    let notified: NotifiedStore
    let model: AppModel

    init(org: String = "org", makeClientError: Error? = nil) {
        let suite = UserDefaults(suiteName: "prpulse-model-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: suite)
        store.settings.org = org
        settings = store
        notified = NotifiedStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("prpulse-\(UUID().uuidString)/n.json"))

        let world = world
        let clock = clock
        model = AppModel(
            settings: store,
            notified: notified,
            makeClient: {
                if let makeClientError { throw makeClientError }
                let delay = world.takeFirstClientDelay()
                if delay > 0 { try await Task.sleep(for: .milliseconds(delay)) }
                return GitHubClient(transport: FakeTransport(world.respond), clock: clock)
            },
            sink: sink,
            clock: clock
        )
    }
}

@MainActor @Test func firstRefreshAfterSetupIsSilent() async {
    let h = Harness()
    h.world.mine = [changesRequestedPR(1)]
    h.world.review = [minimalPR(number: 2)]

    await h.model.completeSetup()

    #expect(h.sink.batches.isEmpty)
    #expect(h.notified.keys.count == 2)
    #expect(h.settings.settings.hasCompletedSetup)
    #expect(h.model.freshUntil == nil)
    guard case .ready(let summary) = h.model.state else { Issue.record("expected ready"); return }
    #expect(summary.total == 2)
}

@MainActor @Test func newPendingAfterSetupNotifiesOnce() async {
    let h = Harness()
    h.world.mine = [changesRequestedPR(1)]
    await h.model.completeSetup()

    h.world.mine = [changesRequestedPR(1), changesRequestedPR(2)]
    await h.model.refresh()

    #expect(h.sink.batches.count == 1)
    #expect(h.sink.batches[0].map(\.ref.number) == [2])
    #expect(h.model.freshUntil == h.clock.now.addingTimeInterval(10))
}

@MainActor @Test func sameSummaryTwiceNotifiesOnce() async {
    let h = Harness()
    h.world.mine = [changesRequestedPR(1)]

    await h.model.refresh()
    await h.model.refresh()

    #expect(h.sink.batches.count == 1)
}

@MainActor @Test func unauthorizedShowsFailedStateAndDoesNotNotify() async {
    let h = Harness()
    h.world.mine = [changesRequestedPR(1)]
    h.world.failure = GitHubError.unauthorized

    await h.model.refresh()

    #expect(h.model.state == .failed(.unauthenticated))
    #expect(h.sink.batches.isEmpty)
}

@MainActor @Test func tokenProblemsFromTheProviderShowUnauthenticated() async {
    let h = Harness(makeClientError: AuthError.ghNotLoggedIn)
    await h.model.refresh()
    #expect(h.model.state == .failed(.unauthenticated))
}

@MainActor @Test func ssoRequiredShowsFailedState() async {
    let h = Harness()
    h.world.failure = GitHubError.ssoRequired(org: "acme")

    await h.model.refresh()

    #expect(h.model.state == .failed(.ssoRequired(org: "acme")))
}

@MainActor @Test func missingOrgShowsNotConfigured() async {
    let h = Harness(org: "")
    await h.model.refresh()
    #expect(h.model.state == .failed(.notConfigured))
}

@MainActor @Test func networkFailureKeepsLastSummaryAndMarksOffline() async {
    let h = Harness()
    h.world.mine = [changesRequestedPR(1)]
    await h.model.refresh()
    guard case .ready(let before) = h.model.state else { Issue.record("expected ready"); return }
    let notifiedBefore = h.sink.batches.count

    h.world.failure = GitHubError.network("offline")
    await h.model.refresh()

    #expect(h.model.state == .ready(before))
    #expect(h.model.isOffline)
    #expect(h.sink.batches.count == notifiedBefore)

    h.world.failure = nil
    await h.model.refresh()
    #expect(!h.model.isOffline)
}

@MainActor @Test func networkFailureWithoutSummaryIsOfflineNotUpToDate() async {
    let h = Harness()
    h.world.failure = GitHubError.network("offline")

    await h.model.refresh()

    #expect(h.model.isOffline)
    #expect(h.model.lastSummary == nil)
    #expect(h.model.state == .idle)
}

@MainActor @Test func recoveringAfterNetworkFailureDoesNotRenotifyKnownItems() async {
    let h = Harness()
    h.world.mine = [changesRequestedPR(1)]
    await h.model.refresh()
    h.world.failure = GitHubError.network("offline")
    await h.model.refresh()
    h.world.failure = nil
    await h.model.refresh()

    #expect(h.sink.batches.count == 1)
}

@MainActor @Test func notificationsDisabledStillAdvancesNotifiedKeys() async {
    let h = Harness()
    h.settings.settings.notificationsEnabled = false
    h.world.mine = [changesRequestedPR(1)]

    await h.model.refresh()

    #expect(h.sink.batches.isEmpty)
    #expect(h.notified.keys.count == 1)
    #expect(h.model.freshUntil == nil)
}

@MainActor @Test func rateLimitedKeepsSummaryAndDelaysNextRefresh() async {
    let h = Harness()
    h.world.failure = GitHubError.rateLimited(retryAfter: 900)

    await h.model.refresh()

    #expect(h.model.isOffline)
    #expect(h.model.nextDelay() == 900)
    h.world.failure = nil
    h.clock.now = h.clock.now.addingTimeInterval(901)
    #expect(h.model.nextDelay() == 60)
}

@MainActor @Test func failedSetupDoesNotMarkSetupComplete() async {
    let h = Harness()
    h.world.failure = GitHubError.unauthorized

    await h.model.completeSetup()

    #expect(!h.settings.settings.hasCompletedSetup)
    #expect(h.model.state == .failed(.unauthenticated))
}

@MainActor @Test func switchingAccountsIsPickedUpOnTheNextRefresh() async {
    let h = Harness()
    await h.model.refresh()
    #expect(h.world.seenQueries.contains { $0.contains("author:me ") })

    h.world.viewerLogin = "other"
    await h.model.refresh()
    #expect(h.world.seenQueries.contains { $0.contains("author:other ") })
}

@MainActor @Test func inaccessibleOrganizationShowsFailedStateInsteadOfAllClear() async {
    let h = Harness()
    h.world.mine = [changesRequestedPR(1)]
    h.world.orgAccessible = false

    await h.model.refresh()

    #expect(h.model.state == .failed(.organizationNotAccessible("org")))
    #expect(h.sink.batches.isEmpty)
}

@MainActor @Test func keychainReadErrorShowsUnauthenticatedNotOffline() async {
    let h = Harness(makeClientError: KeychainTokenStore.KeychainError(status: -128))

    await h.model.refresh()

    #expect(h.model.state == .failed(.unauthenticated))
    #expect(!h.model.isOffline)
}

@MainActor @Test func offlineWithoutAnySummaryRetriesSoon() async {
    let h = Harness()
    h.world.failure = GitHubError.network("offline")
    await h.model.refresh()
    #expect(h.model.nextDelay() == 60)

    h.world.failure = nil
    await h.model.refresh()
    #expect(h.model.nextDelay() == 300)
}

@MainActor @Test func refreshDuringSetupDoesNotNotifyTheBacklog() async {
    let h = Harness()
    h.world.mine = [changesRequestedPR(1)]
    h.world.firstClientDelayMilliseconds = 80

    let setup = Task { await h.model.completeSetup() }
    await Task.yield()
    await h.model.refresh()
    await setup.value

    #expect(h.sink.batches.isEmpty)
    #expect(h.notified.keys.count == 1)
}

@MainActor @Test func cancelledRequestDoesNotMarkOffline() async {
    let h = Harness()
    h.world.failure = CancellationError()

    await h.model.refresh()

    #expect(!h.model.isOffline)
    #expect(h.model.state == .idle)
}

@MainActor @Test func restartPicksUpNewSettingsWithoutWaitingForTheNextCycle() async throws {
    let h = Harness()
    await h.model.refresh()
    #expect(h.world.seenQueries.contains { $0.contains("org:org ") })

    h.settings.settings.org = "other"
    await h.model.restart()

    for _ in 0 ..< 200 where !h.world.seenQueries.contains(where: { $0.contains("org:other ") }) {
        try await Task.sleep(for: .milliseconds(10))
    }
    h.model.stop()
    #expect(h.world.seenQueries.contains { $0.contains("org:other ") })
}
