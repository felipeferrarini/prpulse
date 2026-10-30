import AppKit
import Sparkle

/// Sparkle behind a small seam. It only runs from a real bundle that carries a feed, so `swift run`, the tests and
/// the demo modes never reach the network.
@MainActor
final class SoftwareUpdater {
    nonisolated static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private let controller: SPUStandardUpdaterController?
    private let reminders = UpdateReminders()

    init(enabled: Bool) {
        let hasFeed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        guard enabled, hasFeed else {
            controller = nil
            return
        }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: reminders)
    }

    var isAvailable: Bool { controller != nil }

    func apply(automatic: Bool) {
        guard let updater = controller?.updater else { return }
        updater.automaticallyChecksForUpdates = automatic
        updater.automaticallyDownloadsUpdates = automatic
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}

/// A menu bar app is never frontmost, so a scheduled update would open its window behind everything else.
private final class UpdateReminders: NSObject, SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard handleShowingUpdate else { return }
        NSApp.activate(ignoringOtherApps: true)
    }
}
