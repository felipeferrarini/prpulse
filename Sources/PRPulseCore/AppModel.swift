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

    private let settings: SettingsStore
    private let notified: NotifiedStore
    private let makeClient: @Sendable () async throws -> GitHubClient
    private let sink: NotificationSink
    private let clock: Clock

    private var retryNotBefore: Date?
    private var isSettingUp = false
    private var loop: Task<Void, Never>?

    public init(
        settings: SettingsStore,
        notified: NotifiedStore,
        makeClient: @escaping @Sendable () async throws -> GitHubClient,
        sink: NotificationSink,
        clock: Clock
    ) {
        self.settings = settings
        self.notified = notified
        self.makeClient = makeClient
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
        let client = try await makeClient()
        for org in current.orgs { try await client.verifyOrganization(org) }
        let login = try await client.viewer().login
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
            waitingDays: current.waitingReviewDays,
            now: clock.now
        )
    }

    private func apply(_ summary: Summary) async {
        show(summary)
        let plan = NotificationPlanner.plan(current: summary.pendingKeys, notified: notified.keys)
        notified.replace(with: plan.notified)
        guard settings.settings.notificationsEnabled, !plan.toNotify.isEmpty else { return }
        await sink.deliver(plan.toNotify, summary: summary)
        arrival = Arrival.make(from: plan.toNotify, in: summary, at: clock.now)
        freshUntil = clock.now.addingTimeInterval(Self.freshDuration)
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
        case GitHubError.unauthorized, is AuthError, is KeychainTokenStore.KeychainError:
            isOffline = false
            state = .failed(.unauthenticated)
        case GitHubError.organizationNotAccessible(let org):
            isOffline = false
            state = .failed(.organizationNotAccessible(org))
        case GitHubError.ssoRequired(let org):
            isOffline = false
            state = .failed(.ssoRequired(org: org))
        case GitHubError.rateLimited(let retryAfter):
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
