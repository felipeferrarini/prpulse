import AppKit
import Combine
import PRPulseCore
import SwiftUI

@MainActor
final class AppRuntime: ObservableObject {
    private static let setupWindow = "setup"
    private static let settingsWindow = "settings"

    @Published private(set) var data = ViewData()
    @Published private(set) var iconState = IconState.upToDate
    @Published private(set) var pulsePhase = 0.0
    @Published private(set) var popoverLayout = PopoverLayout.single
    @Published private(set) var openCount = 0
    @Published private(set) var mascotConfig: MascotConfig
    @Published private(set) var mascotState = MascotState(mood: .calm, count: 0)
    @Published private(set) var mascotBubble: MascotBubble?
    /// Changes when the mascot should go back to its saved place.
    @Published private(set) var mascotPlacementToken = 0

    let settings = SettingsStore()
    private let model: AppModel?
    private let notifier = Notifier()
    private let updater: SoftwareUpdater
    private var shortcut: GlobalShortcut?
    /// Set by the popover controller, which owns the panel.
    var onShortcut: () -> Void = {}
    private let windows = WindowManager()
    private var observation: AnyCancellable?
    private var ticker: Timer?
    private var mascotTimer: Timer?
    private var upToDateSince: Date?
    private var lastArrival: Arrival?

    init() {
        popoverLayout = settings.settings.popoverLayout
        mascotConfig = MascotConfig(settings.settings)
        updater = SoftwareUpdater(enabled: DemoMode.current == nil)
        updater.apply(automatic: settings.settings.automaticUpdates)
        if let demo = DemoMode.current {
            model = nil
            data = demo.viewData
            refreshIcon()
            if demo == .fresh && DemoSnapshot.directory == nil {
                showMascotBubble(title: tr("notification.title.other", 3), detail: "Per-tenant session cache", seconds: 120)
            }
            writeSnapshotsIfRequested()
        } else {
            let model = AppModel(
                settings: settings,
                notified: .standard(appName: "PRPulse"),
                makeClient: ClientFactory.makeClientFactory(settings: settings),
                sink: notifier,
                clock: SystemClock()
            )
            self.model = model
            notifier.activate()
            observation = model.objectWillChange.sink { [weak self] _ in
                DispatchQueue.main.async { self?.syncFromModel() }
            }
            data.isSetupComplete = settings.settings.hasCompletedSetup
            if settings.settings.hasCompletedSetup {
                model.start()
            } else {
                DispatchQueue.main.async { [weak self] in self?.showSetup() }
            }
        }
        if DemoSnapshot.directory == nil {
            shortcut = GlobalShortcut { [weak self] in self?.onShortcut() }
            shortcut?.setEnabled(settings.settings.globalShortcut)
        }
        mascotTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshMascot() }
        }
        refreshMascot()
    }

    var organizations: [String] { settings.settings.orgs }
    var notificationsEnabled: Bool { settings.settings.notificationsEnabled }

    func toggleNotifications() {
        settings.settings.notificationsEnabled.toggle()
    }

    /// Adds the repository to the ones left out of the review list and refreshes right away.
    func muteRepository(of ref: PullRequestRef) {
        let entry = "\(ref.owner)/\(ref.repo)"
        settings.settings.ignoredRepos = ListEditing.adding(entry, to: settings.settings.ignoredRepos, kind: .repository)
        refresh()
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }

    func diagnosticsReport() -> DiagnosticsReport {
        guard let model else { return .sample }
        let current = settings.settings
        return DiagnosticsReport(
            appVersion: SoftwareUpdater.version,
            systemVersion: ProcessInfo.processInfo.operatingSystemVersionString.replacingOccurrences(of: "Version ", with: ""),
            authSource: current.authSource,
            organizationCount: current.orgs.count,
            refreshMinutes: current.refreshMinutes,
            lastSync: model.lastUpdated,
            status: Self.syncStatus(model),
            reviewCount: model.lastSummary?.review.count ?? 0,
            mineCount: model.lastSummary?.mine.count ?? 0,
            rateLimit: ClientFactory.rateLimits.latest,
            shortcutActive: shortcut?.isRegistered ?? false,
            automaticUpdates: current.automaticUpdates
        )
    }

    private static func syncStatus(_ model: AppModel) -> SyncStatus {
        if model.isOffline { return .offline }
        switch model.state {
        case .idle, .loading: return model.lastUpdated == nil ? .neverSynced : .ok
        case .ready: return .ok
        case .failed(let failure):
            switch failure {
            case .unauthenticated: return .failed("unauthenticated")
            case .ssoRequired: return .failed("sso required")
            case .notConfigured: return .failed("not configured")
            case .organizationNotAccessible: return .failed("organization not accessible")
            }
        }
    }

    var mascotAnchor: MascotAnchor? { settings.settings.mascotAnchor }

    func setMascotEnabled(_ enabled: Bool) {
        settings.settings.mascotEnabled = enabled
        refreshMascotConfig()
    }

    func setMascotPack(_ id: String) {
        settings.settings.mascotPack = id
        refreshMascotConfig()
    }

    func setMascotScale(_ scale: Int) {
        settings.settings.mascotScale = scale
        refreshMascotConfig()
    }

    func setMascotAnchor(_ anchor: MascotAnchor?) {
        settings.settings.mascotAnchor = anchor
    }

    func resetMascotPosition() {
        settings.settings.mascotAnchor = nil
        mascotPlacementToken += 1
    }

    var mascotEnabled: Bool { mascotConfig.enabled }

    func popoverOpened() {
        openCount += 1
    }

    func setPopoverLayout(_ layout: PopoverLayout) {
        popoverLayout = layout
        settings.settings.popoverLayout = layout
    }

    func refresh() {
        guard let model else { return }
        Task { await model.refresh() }
    }

    func openSettings() {
        guard settings.settings.hasCompletedSetup else { return showSetup() }
        let setup = SetupModel(settings: settings.settings, isSetup: false)
        windows.show(id: Self.settingsWindow, title: tr("settings.title"), chrome: .borderless) {
            SettingsView(
                model: setup,
                onSave: { [weak self] draft in self?.save(draft) },
                onRedoSetup: { [weak self] in self?.redoSetup() },
                onCheckForUpdates: { [weak self] in self?.checkForUpdates() },
                onResetMascotPosition: { [weak self] in self?.resetMascotPosition() },
                diagnostics: { [weak self] in self?.diagnosticsReport() ?? .sample },
                onClose: { [weak self] in self?.windows.close(id: Self.settingsWindow) }
            )
        }
    }

    /// Opens the wizard from scratch. Nothing is replaced until the user finishes it.
    private func redoSetup() {
        windows.close(id: Self.settingsWindow)
        showSetup(settings: .defaults)
    }

    private func showSetup() {
        showSetup(settings: settings.settings)
    }

    private func showSetup(settings initial: AppSettings) {
        let setup = SetupModel(settings: initial)
        windows.show(id: Self.setupWindow, title: "PRPulse", chrome: .borderless) {
            WizardView(
                model: setup,
                onFinish: { [weak self] in await self?.finishSetup(setup.draft) },
                onClose: { [weak self] in self?.windows.close(id: Self.setupWindow) },
                onCancel: { [weak self] in self?.windows.close(id: Self.setupWindow) }
            )
        }
    }

    private func finishSetup(_ draft: AppSettings) async -> String? {
        guard let model else { return nil }
        var chosen = draft
        chosen.popoverLayout = popoverLayout
        chosen.mascotAnchor = settings.settings.mascotAnchor
        chosen.mascotIntroduced = true
        chosen.hasCompletedSetup = false
        settings.settings = chosen
        refreshMascotConfig()
        LaunchAtLogin.apply(chosen.launchAtLogin)
        await model.completeSetup()
        guard settings.settings.hasCompletedSetup else { return Self.failureMessage(model) }
        model.start()
        return nil
    }

    private static func failureMessage(_ model: AppModel) -> String {
        switch model.state {
        case .failed(.unauthenticated): tr("error.unauthenticated.body")
        case .failed(.ssoRequired): tr("error.sso.body")
        case .failed(.organizationNotAccessible(let org)): tr("error.org.body", org)
        case .failed(.notConfigured): tr("error.notConfigured.body")
        default: tr("setup.error.network")
        }
    }

    private func save(_ draft: AppSettings) {
        var chosen = draft
        popoverLayout = chosen.popoverLayout
        chosen.hasCompletedSetup = true
        chosen.mascotAnchor = settings.settings.mascotAnchor
        chosen.mascotIntroduced = settings.settings.mascotIntroduced
        settings.settings = chosen
        refreshMascotConfig()
        LaunchAtLogin.apply(chosen.launchAtLogin)
        updater.apply(automatic: chosen.automaticUpdates)
        shortcut?.setEnabled(chosen.globalShortcut)
        guard let model else { return }
        Task { await model.restart() }
    }

    private func writeSnapshotsIfRequested() {
        guard let directory = DemoSnapshot.directory else { return }
        DispatchQueue.main.async {
            if ProcessInfo.processInfo.environment["PRPULSE_SNAPSHOT_STYLE"] == "readme" {
                ReadmeShots.writeAll(to: directory)
            } else {
                DemoSnapshot.writeAll(to: directory)
            }
            NSApp.terminate(nil)
        }
    }

    private func syncFromModel() {
        guard let model else { return }
        data = ViewData(
            state: model.state,
            summary: model.lastSummary,
            lastUpdated: model.lastUpdated,
            isOffline: model.isOffline,
            freshUntil: model.freshUntil,
            isSetupComplete: settings.settings.hasCompletedSetup,
            orgs: settings.settings.orgs
        )
        if let arrival = model.arrival, arrival != lastArrival {
            lastArrival = arrival
            let title = arrival.count == 1 ? tr("notification.title.one") : tr("notification.title.other", arrival.count)
            showMascotBubble(title: title, detail: arrival.firstTitle, seconds: 6)
        }
        refreshIcon()
    }

    // MARK: Mascot

    private func refreshMascotConfig() {
        let next = MascotConfig(settings.settings)
        if next != mascotConfig { mascotConfig = next }
        refreshMascot()
    }

    private func refreshMascot() {
        let now = Date()
        let isQuiet = data.summary?.total == 0 && !data.isOffline && !isFailed(data.state)
        if isQuiet { upToDateSince = upToDateSince ?? now } else { upToDateSince = nil }
        let situation = MascotSituation(
            state: data.state,
            isOffline: data.isOffline,
            summary: data.summary,
            freshUntil: data.freshUntil,
            isRefreshing: model?.isRefreshing ?? false,
            upToDateSince: upToDateSince
        )
        let next = MascotState(mood: MascotMoodResolver.mood(for: situation, now: now), count: data.summary?.total ?? 0)
        if next != mascotState { mascotState = next }
        introduceMascotIfNeeded()
    }

    private func isFailed(_ state: LoadState) -> Bool {
        if case .failed = state { true } else { false }
    }

    /// Existing users get the mascot with an update: it says hello once.
    private func introduceMascotIfNeeded() {
        let current = settings.settings
        guard mascotConfig.enabled, current.hasCompletedSetup, !current.mascotIntroduced else { return }
        guard DemoSnapshot.directory == nil, DemoMode.current == nil else { return }
        settings.settings.mascotIntroduced = true
        let name = MascotLibrary.info(id: current.mascotPack)?.name ?? ""
        showMascotBubble(title: tr("mascot.intro.title", name), detail: tr("mascot.intro.detail"), seconds: 9)
    }

    private func showMascotBubble(title: String, detail: String?, seconds: Double) {
        let bubble = MascotBubble(title: title, detail: detail)
        mascotBubble = bubble
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            if self?.mascotBubble?.id == bubble.id { self?.mascotBubble = nil }
        }
    }

    private func refreshIcon() {
        iconState = IconState.make(state: data.state, summary: data.summary, freshUntil: data.freshUntil, now: Date())
        if case .fresh = iconState { startTicker() } else { stopTicker() }
        refreshMascot()
    }

    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
        pulsePhase = 0
    }

    private func tick() {
        pulsePhase = (Date().timeIntervalSince1970 * 0.9).truncatingRemainder(dividingBy: 1)
        refreshIcon()
    }
}
