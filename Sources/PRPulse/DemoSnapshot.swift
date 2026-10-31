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
            let suffix = scheme == .dark ? "dark" : "light"
            write(agents(open: nil, scheme), named: "popover-agents-\(suffix)", to: directory)
            write(agents(open: 1, scheme), named: "popover-agents-detail-\(suffix)", to: directory)
            write(agents(open: 0, scheme, scene: .approval), named: "popover-agents-approval-\(suffix)", to: directory)
            write(agents(open: 1, scheme, scene: .followUp), named: "popover-agents-followup-\(suffix)", to: directory)
            write(agents(open: nil, scheme, scene: .approval), named: "popover-agents-waiting-\(suffix)", to: directory)
        }
        for scheme in [ColorScheme.light, .dark] {
            write(iconStrip(scheme), named: "icons-\(scheme == .dark ? "dark" : "light")", to: directory)
        }
        for step in SetupStep.allCases {
            write(wizard(step), named: "wizard-\(step.rawValue + 1)-\(step)", to: directory)
        }
        write(wizard(.mascot, failure: tr("setup.error.network")), named: "wizard-7-mascot-error", to: directory)
        for page in SettingsPage.allCases {
            write(settings(page), named: "settings-\(page)", to: directory)
        }
        write(releaseNotes, named: "news-window", to: directory)
        for slide in 1 ..< WizardView.slideCount {
            write(wizard(.welcome, slide: slide), named: "wizard-1-welcome-\(slide + 1)", to: directory)
        }
    }

    /// The window an update opens, with the two latest releases of the changelog that ships with the app.
    static var releaseNotes: some View {
        ReleaseNotesView(releases: Array(NewsContent.bundledReleases().prefix(2)), showAfterUpdate: true)
    }

    static func settings(_ page: SettingsPage, login: String = "felipeferrarini") -> some View {
        var settings = AppSettings.defaults
        settings.orgs = ["acme", "orbit"]
        settings.ignoredRepos = ["docs", "infra-legacy"]
        let model = SetupModel(settings: settings, isSetup: false)
        model.loadPreview(
            organizations: ["acme", "acme-labs", "orbit", "octocat"],
            gh: .available,
            repositories: ["web", "api", "docs", "infra-legacy", "mobile", "design-system", "billing", "ops", "playground", "website"],
            activity: ["acme": 87, "acme-labs": 14, "orbit": 2],
            login: login
        )
        model.draft.refreshMinutes = page == .general ? 10 : 5
        return SettingsView(model: model, initialPage: page, onSave: { _ in }, onRedoSetup: {})
    }

    static func wizard(_ step: SetupStep, slide: Int = 0, failure: String? = nil) -> some View {
        var settings = AppSettings.defaults
        settings.orgs = step == .organization ? [] : ["acme"]
        settings.ignoredRepos = ["docs", "infra-legacy"]
        let model = SetupModel(settings: settings)
        model.loadPreview(
            organizations: ["acme", "acme-labs", "orbit", "octocat"],
            gh: .available,
            repositories: ["web", "api", "docs", "infra-legacy", "mobile", "design-system", "billing", "ops", "playground", "website"],
            activity: ["acme": 87, "acme-labs": 14, "orbit": 2]
        )
        return WizardView(model: model, initialStep: step, initialSlide: slide, initialFailure: failure, onFinish: { nil })
    }

    static func popover(
        _ data: ViewData, _ scheme: ColorScheme, layout: PopoverLayout, tab: PopoverTab = .review, filter: ActionLane? = nil
    ) -> some View {
        PopoverView(data: data, layout: .constant(layout), initialTab: tab, initialFilter: filter, onRefresh: {}, onSettings: {})
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, scheme)
    }

    /// The reviews of the agents: one going on, one ready and one that failed.
    enum AgentScene {
        case plain
        /// The review going on waits to be allowed to run a command.
        case approval
        /// A question about the review that is ready, with a command to allow.
        case followUp
    }

    static func sampleRuns(_ scene: AgentScene = .plain) -> AgentRunList {
        let now = Date()
        func make(_ number: Int, _ repo: String, _ title: String, minutes: Double) -> AgentRun {
            AgentRun(
                ref: PullRequestRef(owner: "acme", repo: repo, number: number), title: title,
                url: URL(string: "https://github.com/acme/\(repo)/pull/\(number)")!, folder: "/Users/you/Projects/acme", skill: "code-review",
                startedAt: now.addingTimeInterval(-minutes * 60), sessionID: "demo"
            )
        }
        var list = AgentRunList()
        let failed = make(133, "mobile", "Offline upload queue", minutes: 14)
        let ready = make(208, "api", "Fix pagination on /invoices", minutes: 6)
        let going = make(412, "web", "Per-tenant session cache", minutes: 2)
        for run in [failed, ready, going] { list.add(run) }
        list.fail(failed.id, message: "Not logged in. Please run /login.", at: now.addingTimeInterval(-13 * 60))
        list.finish(ready.id, output: """
        **Two things to fix before merging.**

        1. `src/invoices/list.ts:48` builds the cursor from `created_at`, which is not unique. Two invoices created in the same second can be skipped between pages. Use `(created_at, id)`.
        2. `src/invoices/list.ts:71` sends the page size to the database without a ceiling, so `?limit=100000` reads the whole table.

        What is fine: the tests cover the empty page and the last page, and the new index is used by the query (checked with EXPLAIN in the description).
        """, at: now.addingTimeInterval(-4 * 60))
        list.update(going.id) { $0.activity = "Reading session-cache.ts" }
        if scene == .approval {
            list.setApproval(going.id, ToolApproval(requestID: "demo", tool: "Bash", summary: "gh api repos/acme/web/pulls/412/comments --paginate"))
        }
        if scene == .followUp {
            list.ask(ready.id, question: "Would a unique index on (created_at, id) be enough?", at: now)
            list.setApproval(ready.id, ToolApproval(requestID: "demo", tool: "Bash", summary: "psql -c \"EXPLAIN SELECT * FROM invoices ORDER BY created_at, id LIMIT 50\""))
        }
        return list
    }

    static func agents(open: Int?, _ scheme: ColorScheme, scene: AgentScene = .plain) -> some View {
        let list = sampleRuns(scene)
        let opened = open.map { list.runs[$0].id }
        return AgentsPane(runs: list, actions: AgentActions(), openRun: .constant(opened))
            .frame(width: 560)
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
        let settle = ProcessInfo.processInfo.environment["PRPULSE_SNAPSHOT_SETTLE"].flatMap(TimeInterval.init) ?? 0.3
        RunLoop.current.run(until: Date().addingTimeInterval(settle))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds),
              (host.cacheDisplay(in: host.bounds, to: rep), true).1,
              let png = rep.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: directory.appendingPathComponent("\(name).png"))
    }
}
