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

    let settings = SettingsStore()
    private let model: AppModel?
    private let notifier = Notifier()
    private let windows = WindowManager()
    private var observation: AnyCancellable?
    private var ticker: Timer?

    init() {
        if let demo = DemoMode.current {
            model = nil
            data = demo.viewData
            refreshIcon()
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
            if settings.settings.hasCompletedSetup {
                model.start()
            } else {
                DispatchQueue.main.async { [weak self] in self?.showSetup() }
            }
        }
    }

    func refresh() {
        guard let model else { return }
        Task { await model.refresh() }
    }

    func openSettings() {
        guard settings.settings.hasCompletedSetup else { return showSetup() }
        let setup = SetupModel(settings: settings.settings)
        windows.show(id: Self.settingsWindow, title: tr("settings.title")) {
            SettingsView(model: setup) { [weak self] draft in self?.save(draft) }
        }
    }

    private func showSetup() {
        let setup = SetupModel(settings: settings.settings)
        windows.show(id: Self.setupWindow, title: "PRPulse") {
            WizardView(model: setup) { [weak self] in await self?.finishSetup(setup.draft) }
        }
    }

    private func finishSetup(_ draft: AppSettings) async -> String? {
        guard let model else { return nil }
        var chosen = draft
        chosen.hasCompletedSetup = false
        settings.settings = chosen
        LaunchAtLogin.apply(chosen.launchAtLogin)
        await model.completeSetup()
        guard settings.settings.hasCompletedSetup else { return Self.failureMessage(model) }
        model.start()
        windows.close(id: Self.setupWindow)
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
        chosen.hasCompletedSetup = true
        settings.settings = chosen
        LaunchAtLogin.apply(chosen.launchAtLogin)
        refresh()
    }

    private func writeSnapshotsIfRequested() {
        guard let directory = DemoSnapshot.directory else { return }
        DispatchQueue.main.async {
            DemoSnapshot.writeAll(to: directory)
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
            freshUntil: model.freshUntil
        )
        refreshIcon()
    }

    private func refreshIcon() {
        iconState = IconState.make(state: data.state, summary: data.summary, freshUntil: data.freshUntil, now: Date())
        if case .fresh = iconState { startTicker() } else { stopTicker() }
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
