import AppKit
import PRPulseCore
import SwiftUI

/// Renders the demo popover and icon states to PNG files, for screenshots and visual checks.
/// Triggered by `PRPULSE_SNAPSHOT_DIR`; the app quits when it is done.
@MainActor
enum DemoSnapshot {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["PRPULSE_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    static func writeAll(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for mode in [DemoMode.pending, .empty, .error, .unconfigured] {
            for scheme in [ColorScheme.light, .dark] {
                write(popover(mode.viewData, scheme), named: "popover-\(mode.rawValue)-\(scheme == .dark ? "dark" : "light")", to: directory)
            }
        }
        for scheme in [ColorScheme.light, .dark] {
            write(iconStrip(scheme), named: "icons-\(scheme == .dark ? "dark" : "light")", to: directory)
        }
        for step in SetupStep.allCases {
            write(wizard(step), named: "wizard-\(step.rawValue + 1)-\(step)", to: directory)
        }
    }

    private static func wizard(_ step: SetupStep) -> some View {
        var settings = AppSettings.defaults
        settings.org = "acme"
        settings.ignoredRepos = ["docs", "infra-legacy"]
        let model = SetupModel(settings: settings)
        model.loadPreview(organizations: ["acme", "acme-labs", "octocat"], gh: .available)
        return WizardView(model: model, initialStep: step) { nil }
            .background(Color(nsColor: .windowBackgroundColor))
    }

    private static func popover(_ data: ViewData, _ scheme: ColorScheme) -> some View {
        PopoverView(data: data, onRefresh: {}, onSettings: {})
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, scheme)
    }

    private static func iconStrip(_ scheme: ColorScheme) -> some View {
        let states: [(IconState, Double)] = [(.upToDate, 0), (.pending(4), 0), (.fresh(5), 0.15), (.fresh(5), 0.6), (.error, 0)]
        return HStack(spacing: 18) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, entry in
                Image(nsImage: StatusIconRenderer.image(for: entry.0, phase: entry.1))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.86))
        .foregroundStyle(scheme == .dark ? Color.white : Color.black)
        .environment(\.colorScheme, scheme)
    }

    private static func write(_ view: some View, named name: String, to directory: URL) {
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds),
              (host.cacheDisplay(in: host.bounds, to: rep), true).1,
              let png = rep.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: directory.appendingPathComponent("\(name).png"))
    }
}
