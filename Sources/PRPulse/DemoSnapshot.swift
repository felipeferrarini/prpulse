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
                let name = "popover-\(mode.rawValue)-\(scheme == .dark ? "dark" : "light")"
                write(popover(mode.viewData, scheme, layout: .single), named: name, to: directory)
                if mode == .pending {
                    write(popover(mode.viewData, scheme, layout: .split), named: "\(name)-split", to: directory)
                    write(popover(mode.viewData, scheme, layout: .single, tab: .mine, filter: .ci), named: "\(name)-mine-filtered", to: directory)
                    write(popover(mode.viewData, scheme, layout: .split, filter: .merge), named: "\(name)-split-filtered", to: directory)
                }
            }
        }
        for scheme in [ColorScheme.light, .dark] {
            write(iconStrip(scheme), named: "icons-\(scheme == .dark ? "dark" : "light")", to: directory)
        }
        for step in SetupStep.allCases {
            write(wizard(step), named: "wizard-\(step.rawValue + 1)-\(step)", to: directory)
        }
        for page in SettingsPage.allCases {
            write(settings(page), named: "settings-\(page)", to: directory)
        }
        for slide in 1 ..< WizardView.slideCount {
            write(wizard(.welcome, slide: slide), named: "wizard-1-welcome-\(slide + 1)", to: directory)
        }
    }

    private static func settings(_ page: SettingsPage) -> some View {
        var settings = AppSettings.defaults
        settings.org = "acme"
        settings.ignoredRepos = ["docs", "infra-legacy"]
        let model = SetupModel(settings: settings, isSetup: false)
        model.loadPreview(
            organizations: ["acme", "acme-labs", "orbit", "octocat"],
            gh: .available,
            repositories: ["web", "api", "docs", "infra-legacy", "mobile", "design-system", "billing", "ops", "playground", "website"],
            activity: ["acme": 87, "acme-labs": 14, "orbit": 2],
            login: "felipeferrarini"
        )
        model.draft.refreshMinutes = page == .general ? 10 : 5
        return SettingsView(model: model, initialPage: page, onSave: { _ in }, onRedoSetup: {})
    }

    private static func wizard(_ step: SetupStep, slide: Int = 0) -> some View {
        var settings = AppSettings.defaults
        settings.org = step == .organization ? "" : "acme"
        settings.ignoredRepos = ["docs", "infra-legacy"]
        let model = SetupModel(settings: settings)
        model.loadPreview(
            organizations: ["acme", "acme-labs", "orbit", "octocat"],
            gh: .available,
            repositories: ["web", "api", "docs", "infra-legacy", "mobile", "design-system", "billing", "ops", "playground", "website"],
            activity: ["acme": 87, "acme-labs": 14, "orbit": 2]
        )
        return WizardView(model: model, initialStep: step, initialSlide: slide, onFinish: { nil })
    }

    private static func popover(
        _ data: ViewData, _ scheme: ColorScheme, layout: PopoverLayout, tab: PopoverTab = .review, filter: ActionLane? = nil
    ) -> some View {
        PopoverView(data: data, layout: .constant(layout), initialTab: tab, initialFilter: filter, onRefresh: {}, onSettings: {})
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, scheme)
    }

    private static func iconStrip(_ scheme: ColorScheme) -> some View {
        let states: [(IconState, Double)] = [
            (.upToDate, 0), (.pending(4), 0), (.pending(87), 0), (.pending(120), 0), (.fresh(5), 0.15), (.fresh(5), 0.6), (.error, 0),
        ]
        return HStack(spacing: 28) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, entry in
                let image = StatusIconRenderer.image(for: entry.0, phase: entry.1)
                Image(nsImage: image).resizable().frame(width: image.size.width * 4, height: image.size.height * 4)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
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
