import Foundation
import Testing
@testable import PRPulseCore

/// A provider that is not GitHub: it hands out ready-made pull requests, so `AppModel` is exercised with no GraphQL in sight.
private final class FakeProvider: PullRequestProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var failure: Error?
    private var minePRs: [PullRequestSnapshot] = []
    private var reviewPRs: [PullRequestSnapshot] = []
    private var recordedOrgs: [String] = []

    var mine: [PullRequestSnapshot] {
        get { lock.withLock { minePRs } }
        set { lock.withLock { minePRs = newValue } }
    }

    var review: [PullRequestSnapshot] {
        get { lock.withLock { reviewPRs } }
        set { lock.withLock { reviewPRs = newValue } }
    }

    var error: Error? {
        get { lock.withLock { failure } }
        set { lock.withLock { failure = newValue } }
    }

    var queriedOrgs: [String] { lock.withLock { recordedOrgs } }

    private func check() throws {
        if let error { throw error }
    }

    func viewer() async throws -> ViewerInfo {
        try check()
        return ViewerInfo(login: "me", organizations: ["org"])
    }

    func verifyOrganization(_ org: String) async throws { try check() }

    func minePullRequests(org: String, viewer: String) async throws -> [PullRequestSnapshot] {
        try check()
        lock.withLock { recordedOrgs.append(org) }
        return mine
    }

    func reviewPullRequests(org: String, viewer: String, ignoredRepos: Set<String>) async throws -> [PullRequestSnapshot] {
        try check()
        return review
    }

    func repositories(owner: String) async throws -> [String] { ["app"] }
    func organizationActivity(_ organizations: [String], viewer: String) async throws -> [OrganizationActivity] { [] }
}

private final class StillClock: Clock, @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_793_000_000)
}

private final class RecordingSink: NotificationSink, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedKeys: [PendingKey] = []
    private var recordedNudges: [IncomingNudge] = []

    var keys: [PendingKey] { lock.withLock { recordedKeys } }
    var nudges: [IncomingNudge] { lock.withLock { recordedNudges } }

    func deliver(_ items: [PendingKey], summary: Summary) async { lock.withLock { recordedKeys += items } }
    func deliver(nudge: IncomingNudge) async { lock.withLock { recordedNudges.append(nudge) } }
}

@MainActor
private struct Rig {
    let provider = FakeProvider()
    let clock = StillClock()
    let sink = RecordingSink()
    let settings: SettingsStore
    let model: AppModel

    init() {
        let store = SettingsStore(defaults: UserDefaults(suiteName: "prpulse-seam-\(UUID().uuidString)")!)
        store.settings.orgs = ["org"]
        settings = store
        let provider = provider
        model = AppModel(
            settings: store,
            notified: NotifiedStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("prpulse-\(UUID().uuidString)/n.json")),
            makeProvider: { provider },
            sink: sink,
            clock: clock
        )
    }
}

@MainActor @Test func theSummaryComesFromWhateverProviderIsGiven() async {
    let rig = Rig()
    rig.provider.mine = [.fixture(number: 1, reviewDecision: .changesRequested)]
    rig.provider.review = [.fixture(number: 2, author: Actor(login: "sam", isBot: false), requestedReviewers: [viewer])]

    await rig.model.refresh()

    guard case .ready(let summary) = rig.model.state else { Issue.record("expected ready"); return }
    #expect(summary.total == 2)
    #expect(rig.provider.queriedOrgs == ["org"])
}

@MainActor @Test func aProviderThatRefusesTheTokenShowsUnauthenticated() async {
    let rig = Rig()
    rig.provider.error = ProviderError.unauthorized

    await rig.model.refresh()

    #expect(rig.model.state == .failed(.unauthenticated))
}

@MainActor @Test func aProviderThatRateLimitsDelaysTheNextRefresh() async {
    let rig = Rig()
    rig.provider.error = ProviderError.rateLimited(retryAfter: 600)

    await rig.model.refresh()

    #expect(rig.model.isOffline)
    #expect(rig.model.nextDelay() == 600)
}

@MainActor @Test func aProviderThatCannotSeeTheOrganizationSaysSo() async {
    let rig = Rig()
    rig.provider.error = ProviderError.organizationNotAccessible("org")

    await rig.model.refresh()

    #expect(rig.model.state == .failed(.organizationNotAccessible("org")))
}

// MARK: Nudges

private let ana = Actor(login: "ana", isBot: false)

@MainActor private func nudged(_ rig: Rig, id: String = "n1", agoSeconds: Double = 60) -> PullRequestSnapshot {
    let sentAt = rig.clock.now.addingTimeInterval(-agoSeconds)
    let nudge = NudgeSnapshot(id: id, recipient: "me", tone: 1, message: "pushed the fix", author: ana, createdAt: sentAt)
    return .fixture(number: 5, author: ana, requestedReviewers: [viewer], nudges: [nudge])
}

@MainActor @Test func aNudgeIsPlayedOnceAndReplacesTheUsualNotification() async {
    let rig = Rig()
    rig.provider.review = [nudged(rig)]

    await rig.model.refresh()

    #expect(rig.sink.nudges.map(\.id) == ["n1"])
    #expect(rig.model.pendingNudges.map(\.id) == ["n1"])
    #expect(rig.sink.keys.isEmpty)

    await rig.model.refresh()
    #expect(rig.sink.nudges.count == 1)
    #expect(rig.model.pendingNudges.count == 1)
}

@MainActor @Test func openingThePullRequestEndsTheNudge() async {
    let rig = Rig()
    let pr = nudged(rig)
    rig.provider.review = [pr]
    await rig.model.refresh()

    rig.model.acknowledgeNudges(openedURL: pr.url)

    #expect(rig.model.pendingNudges.isEmpty)
}

@MainActor @Test func aNudgeEndsWhenThePullRequestLeavesTheList() async {
    let rig = Rig()
    rig.provider.review = [nudged(rig)]
    await rig.model.refresh()

    rig.provider.review = []
    await rig.model.refresh()

    #expect(rig.model.pendingNudges.isEmpty)
}

@MainActor @Test func withNudgesOffTheUsualNotificationStillComesAndNothingReplaysLater() async {
    let rig = Rig()
    rig.settings.settings.nudgesEnabled = false
    rig.provider.review = [nudged(rig)]

    await rig.model.refresh()

    #expect(rig.sink.nudges.isEmpty)
    #expect(rig.model.pendingNudges.isEmpty)
    #expect(rig.sink.keys.map(\.ref.number) == [5])

    rig.settings.settings.nudgesEnabled = true
    await rig.model.refresh()
    #expect(rig.sink.nudges.isEmpty)
}

@MainActor @Test func pausedNudgesAreSkippedUntilThePauseEnds() async {
    let rig = Rig()
    rig.settings.settings.nudgesPausedUntil = rig.clock.now.addingTimeInterval(3600)
    rig.provider.review = [nudged(rig)]

    await rig.model.refresh()

    #expect(rig.sink.nudges.isEmpty)
    #expect(rig.model.pendingNudges.isEmpty)
}

@MainActor @Test func aNudgeSeenLateIsDeliveredQuietlyAndLeavesTheMascotAlone() async {
    let rig = Rig()
    rig.provider.review = [nudged(rig, agoSeconds: 5 * 3600)]

    await rig.model.refresh()

    #expect(rig.sink.nudges.first?.isFresh == false)
    #expect(rig.model.pendingNudges.isEmpty)
}
