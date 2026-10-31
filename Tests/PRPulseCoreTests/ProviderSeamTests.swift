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

private final class Mute: NotificationSink, @unchecked Sendable {
    func deliver(_ items: [PendingKey], summary: Summary) async {}
}

@MainActor
private struct Rig {
    let provider = FakeProvider()
    let clock = StillClock()
    let model: AppModel

    init() {
        let store = SettingsStore(defaults: UserDefaults(suiteName: "prpulse-seam-\(UUID().uuidString)")!)
        store.settings.orgs = ["org"]
        let provider = provider
        model = AppModel(
            settings: store,
            notified: NotifiedStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("prpulse-\(UUID().uuidString)/n.json")),
            makeProvider: { provider },
            sink: Mute(),
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
