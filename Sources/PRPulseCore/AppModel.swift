import Foundation

public enum AppFailure: Equatable, Sendable {
    case unauthenticated
    case ssoRequired(org: String?)
    case notConfigured
    case organizationNotAccessible(String)
}

public enum LoadState: Equatable, Sendable {
    case idle
    case loading
    case ready(Summary)
    case failed(AppFailure)
}

public protocol NotificationSink: Sendable {
    func deliver(_ items: [PendingKey], summary: Summary) async
    /// A reviewer asked again: the nudge's own notification, quiet when `isFresh` is false.
    func deliver(nudge: IncomingNudge) async
}

extension NotificationSink {
    public func deliver(nudge: IncomingNudge) async {}
}

@MainActor
public final class AppModel: ObservableObject {
    private static let freshDuration: TimeInterval = 10
    private static let defaultRetryAfter: TimeInterval = 600
    private static let offlineRetry: TimeInterval = 60

    @Published public private(set) var state: LoadState = .idle
    @Published public private(set) var lastSummary: Summary?
    @Published public private(set) var lastUpdated: Date?
    @Published public private(set) var isOffline = false
    @Published public private(set) var freshUntil: Date?
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var arrival: Arrival?
    /// Nudges the viewer has not looked at yet, newest last.
    @Published public private(set) var pendingNudges: [IncomingNudge] = []
    /// The login the lists were built for, known after the first refresh.
    public private(set) var viewerLogin: String?

    private let settings: SettingsStore
    private let notified: NotifiedStore
    private let nudges: NudgeStore
    private let makeProvider: @Sendable () async throws -> any PullRequestProvider
    private let sink: NotificationSink
    private let clock: Clock

    private var retryNotBefore: Date?
    private var isSettingUp = false
    private var loop: Task<Void, Never>?

    public init(
        settings: SettingsStore,
        notified: NotifiedStore,
        nudges: NudgeStore = NudgeStore(),
        makeProvider: @escaping @Sendable () async throws -> any PullRequestProvider,
        sink: NotificationSink,
        clock: Clock
    ) {
        self.settings = settings
        self.notified = notified
        self.nudges = nudges
        self.makeProvider = makeProvider
        self.sink = sink
        self.clock = clock
    }

    public func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                guard let delay = self?.nextDelay() else { return }
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    public func restart() async {
        stop()
        while isRefreshing { try? await Task.sleep(for: .milliseconds(20)) }
        start()
    }

    public func nextDelay() -> TimeInterval {
        let interval = TimeInterval(max(settings.settings.refreshMinutes, 1) * 60)
        let base = isOffline && lastSummary == nil ? min(interval, Self.offlineRetry) : interval
        let remaining = retryNotBefore.map { $0.timeIntervalSince(clock.now) } ?? 0
        return max(base, remaining)
    }

    public func refresh() async {
        guard !isRefreshing, !isSettingUp else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        guard let summary = await loadSummary() else { return }
        await apply(summary)
    }

    public func completeSetup() async {
        isSettingUp = true
        defer { isSettingUp = false }
        guard let summary = await loadSummary() else { return }
        notified.replace(with: NotificationPlanner.seed(current: summary.pendingKeys))
        settings.settings.hasCompletedSetup = true
        show(summary)
    }

    private func loadSummary() async -> Summary? {
        let current = settings.settings
        guard !current.orgs.isEmpty else {
            state = .failed(.notConfigured)
            return nil
        }
        if lastSummary == nil { state = .loading }
        do {
            return try await fetchSummary(current)
        } catch {
            handle(error)
            return nil
        }
    }

    private func fetchSummary(_ current: AppSettings) async throws -> Summary {
        let client = try await makeProvider()
        for org in current.orgs { try await client.verifyOrganization(org) }
        let login = try await client.viewer().login
        viewerLogin = login
        var minePRs: [PullRequestSnapshot] = []
        var reviewPRs: [PullRequestSnapshot] = []
        for org in current.orgs {
            async let mine = client.minePullRequests(org: org, viewer: login)
            async let review = client.reviewPullRequests(org: org, viewer: login, ignoredRepos: current.ignoredRepositories(in: org))
            minePRs += try await mine
            reviewPRs += try await review
        }
        return SummaryBuilder.build(
            minePRs: minePRs,
            reviewPRs: reviewPRs,
            viewer: login,
            ignoredBots: Set(current.ignoredBots),
            ignoredRepos: Set(current.ignoredRepos),
            ignoresBotComments: current.ignoreBotComments,
            skipsBotPullRequests: current.ignoreBotPullRequests
        )
    }

    private func apply(_ summary: Summary) async {
        show(summary)
        let received = receiveNudges(in: summary)
        let plan = NotificationPlanner.plan(current: summary.pendingKeys, notified: notified.keys)
        notified.replace(with: plan.notified)
        for nudge in received { await sink.deliver(nudge: nudge) }
        let nudged = Set(received.map(\.ref))
        let toNotify = plan.toNotify.filter { !nudged.contains($0.ref) }
        guard settings.settings.notificationsEnabled, !toNotify.isEmpty else { return }
        await sink.deliver(toNotify, summary: summary)
        arrival = Arrival.make(from: toNotify, in: summary, at: clock.now)
        freshUntil = clock.now.addingTimeInterval(Self.freshDuration)
    }

    /// The nudges to tell the viewer about now. Every one that arrived is remembered, so it is never played twice, even when
    /// nudges are off or paused: then the pull request is still on the list, and the usual notification covers it.
    private func receiveNudges(in summary: Summary) -> [IncomingNudge] {
        pendingNudges = pendingNudges.filter { pending in summary.review.contains { $0.pr.ref == pending.ref } }
        guard let viewer = viewerLogin else { return [] }
        let arrived = NudgePlanner.incoming(in: summary, viewer: viewer, seen: nudges.seen, now: clock.now)
        nudges.remember(arrived.map(\.id), at: clock.now)
        let current = settings.settings
        guard current.nudgesEnabled, !current.areNudgesPaused(at: clock.now) else { return [] }
        let fresh = arrived.filter(\.isFresh)
        pendingNudges = pendingNudges.filter { old in !fresh.contains { $0.ref == old.ref } } + fresh
        return arrived
    }

    /// The viewer opened the pull request: its nudge has done its job.
    public func acknowledgeNudges(openedURL url: URL) {
        let remaining = pendingNudges.filter { $0.url != url }
        if remaining != pendingNudges { pendingNudges = remaining }
    }

    private func show(_ summary: Summary) {
        state = .ready(summary)
        lastSummary = summary
        lastUpdated = clock.now
        isOffline = false
        retryNotBefore = nil
    }

    private func handle(_ error: Error) {
        switch error {
        case is CancellationError:
            if lastSummary == nil, state == .loading { state = .idle }
        case ProviderError.unauthorized, is AuthError, is KeychainTokenStore.KeychainError:
            isOffline = false
            state = .failed(.unauthenticated)
        case ProviderError.organizationNotAccessible(let org):
            isOffline = false
            state = .failed(.organizationNotAccessible(org))
        case ProviderError.ssoRequired(let org):
            isOffline = false
            state = .failed(.ssoRequired(org: org))
        case ProviderError.rateLimited(let retryAfter):
            retryNotBefore = clock.now.addingTimeInterval(retryAfter ?? Self.defaultRetryAfter)
            markOffline()
        default:
            markOffline()
        }
    }

    private func markOffline() {
        isOffline = true
        if lastSummary == nil { state = .idle }
    }
}
