import AppKit
import PRPulseCore
import SwiftUI

extension ReviewDestination {
    var title: String {
        switch self {
        case .claudeDesktop: tr("agents.dest.claudeDesktop")
        case .claudeCode: tr("agents.dest.claudeCode")
        case .codexApp: tr("agents.dest.codexApp")
        case .codexCLI: tr("agents.dest.codexCLI")
        case .cursorApp: tr("agents.dest.cursorApp")
        case .cursorAgent: tr("agents.dest.cursorAgent")
        case .custom: tr("agents.dest.custom")
        }
    }

    /// What happens when the review is opened there, in a line.
    var detail: String {
        switch self {
        case .claudeDesktop, .codexApp: tr("agents.dest.detail.link")
        case .cursorApp: tr("agents.dest.detail.cursor")
        case .claudeCode, .codexCLI, .cursorAgent, .custom: tr("agents.dest.detail.terminal")
        }
    }

    /// The address that tells whether the app is installed: whatever app handles it is the one a link reaches.
    var appLink: URL? {
        switch self {
        case .claudeDesktop: URL(string: "claude://code/new")
        case .codexApp: URL(string: "codex://threads/new")
        case .cursorApp: URL(string: "cursor://anysphere.cursor-deeplink/prompt")
        case .claudeCode, .codexCLI, .cursorAgent, .custom: nil
        }
    }
}

/// What the rows and the lists need to send a pull request to a review destination, handed down once instead of through every view.
struct ReviewActions {
    /// The destination of the main action, and the others the menu offers. Nil when reviews are off or nothing is ready.
    var primary: ReviewDestination?
    var others: [ReviewDestination] = []
    var review: (PullRequestSnapshot, ReviewDestination) -> Void = { _, _ in }
    var reviewTogether: ([PullRequestSnapshot], ReviewRequest.Scope) -> Void = { _, _ in }
    var reviewEach: ([PullRequestSnapshot]) -> Void = { _ in }

    var isAvailable: Bool { primary != nil }
    /// A conversation for each pull request can be opened at once only where the agent starts by itself: a link only fills in a message.
    var canReviewEach: Bool { primary?.startsByItself == true }
    var canSelect: Bool { isAvailable }
}

private struct ReviewActionsKey: EnvironmentKey {
    static let defaultValue = ReviewActions()
}

extension EnvironmentValues {
    var reviewing: ReviewActions {
        get { self[ReviewActionsKey.self] }
        set { self[ReviewActionsKey.self] = newValue }
    }
}

enum ReviewLaunchFailure: Error {
    case couldNotOpen
    case script(String)
}

/// Carries out what `ReviewLauncher` decided.
enum ReviewRunner {
    /// A terminal that opens `.command` files: an app's bundle identifier, with its name.
    static let knownTerminals: [(id: String, name: String)] = [
        ("com.apple.Terminal", "Terminal"),
        ("com.googlecode.iterm2", "iTerm"),
        ("com.mitchellh.ghostty", "Ghostty"),
        ("dev.warp.Warp-Stable", "Warp"),
    ]

    /// The app a setting names: a bundle identifier or the path of an app. Nil for the system default.
    static func terminalApp(for setting: String) -> URL? {
        guard !setting.isEmpty else { return nil }
        if setting.hasPrefix("/") { return URL(fileURLWithPath: setting) }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: setting)
    }

    static func terminalName(for setting: String) -> String {
        if setting.isEmpty { return tr("agents.terminal.system") }
        if let known = knownTerminals.first(where: { $0.id == setting }) { return known.name }
        if setting.hasPrefix("/") { return URL(fileURLWithPath: setting).deletingPathExtension().lastPathComponent }
        return setting
    }

    static func installedTerminals() -> [(id: String, name: String)] {
        knownTerminals.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.id) != nil }
    }

    @MainActor static func run(_ launch: ReviewLaunch, terminal: String) throws {
        switch launch {
        case .open(let url):
            guard NSWorkspace.shared.open(url) else { throw ReviewLaunchFailure.couldNotOpen }
        case let .openFolderThenLink(folder, link):
            try openFolderThenLink(folder: folder, link: link)
        case .terminal(let script):
            try openTerminal(script: script, terminal: terminal)
        }
    }

    /// Cursor's link has no folder: its window is opened on the folder first, and the message goes to the window that has focus.
    @MainActor private static func openFolderThenLink(folder: URL, link: URL) throws {
        guard let app = NSWorkspace.shared.urlForApplication(toOpen: link) else { throw ReviewLaunchFailure.couldNotOpen }
        NSWorkspace.shared.open([folder], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { NSWorkspace.shared.open(link) }
        }
    }

    @MainActor private static func openTerminal(script: String, terminal: String) throws {
        let folder = FileManager.default.temporaryDirectory
        removeOldScripts(in: folder)
        let file = folder.appendingPathComponent("PRPulse-review-\(UUID().uuidString).command")
        do {
            try script.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        } catch {
            throw ReviewLaunchFailure.script(error.localizedDescription)
        }
        if let app = terminalApp(for: terminal) {
            NSWorkspace.shared.open([file], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        } else if !NSWorkspace.shared.open(file) {
            throw ReviewLaunchFailure.couldNotOpen
        }
    }

    /// The scripts hold only the address of a pull request, but there is no reason to keep them.
    private static func removeOldScripts(in folder: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files where file.lastPathComponent.hasPrefix("PRPulse-review-") && file.pathExtension == "command" {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if Date().timeIntervalSince(modified) > 3600 { try? FileManager.default.removeItem(at: file) }
        }
    }
}
