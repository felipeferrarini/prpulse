import PRPulseCore
import SwiftUI

enum SettingsPage: CaseIterable, Hashable {
    case connection, organization, exceptions, general, mascot, agents, diagnostics

    var symbol: String {
        switch self {
        case .connection: "key"
        case .organization: "arrow.triangle.branch"
        case .exceptions: "eye"
        case .general: "slider.horizontal.3"
        case .mascot: "face.smiling"
        case .agents: "sparkles"
        case .diagnostics: "stethoscope"
        }
    }

    var title: String {
        switch self {
        case .connection: tr("settings.section.connection")
        case .organization: tr("settings.section.organization")
        case .exceptions: tr("settings.section.exceptions")
        case .general: tr("settings.section.general")
        case .mascot: tr("settings.section.mascot")
        case .agents: tr("settings.section.agents")
        case .diagnostics: tr("settings.section.diagnostics")
        }
    }

    var lead: String {
        switch self {
        case .connection: tr("settings.lead.connection")
        case .organization: tr("settings.lead.organization")
        case .exceptions: tr("settings.lead.exceptions")
        case .general: tr("settings.lead.general")
        case .mascot: tr("settings.lead.mascot")
        case .agents: tr("settings.lead.agents")
        case .diagnostics: tr("settings.lead.diagnostics")
        }
    }
}

/// What differs between the settings on disk and the draft, grouped by the page that holds it.
struct SettingsChanges {
    let pages: [SettingsPage]

    init(draft: AppSettings, saved: AppSettings, hasNewToken: Bool) {
        var pages: [SettingsPage] = []
        if draft.authSource != saved.authSource { pages.append(.connection) }
        if hasNewToken { pages.append(.connection) }
        if draft.orgs != saved.orgs { pages.append(.organization) }
        if draft.ignoredRepos.sorted() != saved.ignoredRepos.sorted() { pages.append(.exceptions) }
        if draft.ignoredBots != saved.ignoredBots { pages.append(.exceptions) }
        if draft.ignoreBotComments != saved.ignoreBotComments { pages.append(.exceptions) }
        if draft.ignoreBotPullRequests != saved.ignoreBotPullRequests { pages.append(.exceptions) }
        if draft.refreshMinutes != saved.refreshMinutes { pages.append(.general) }
        if draft.popoverLayout != saved.popoverLayout { pages.append(.general) }
        if draft.notificationsEnabled != saved.notificationsEnabled { pages.append(.general) }
        if draft.launchAtLogin != saved.launchAtLogin { pages.append(.general) }
        if draft.automaticUpdates != saved.automaticUpdates { pages.append(.general) }
        if draft.globalShortcut != saved.globalShortcut { pages.append(.general) }
        if draft.waitingReviewDays != saved.waitingReviewDays { pages.append(.general) }
        if draft.mascotEnabled != saved.mascotEnabled { pages.append(.mascot) }
        if draft.mascotPack != saved.mascotPack { pages.append(.mascot) }
        if draft.mascotScale != saved.mascotScale { pages.append(.mascot) }
        if draft.reviewAgentEnabled != saved.reviewAgentEnabled { pages.append(.agents) }
        if draft.reviewSkill != saved.reviewSkill { pages.append(.agents) }
        if draft.reviewPrompt != saved.reviewPrompt { pages.append(.agents) }
        if draft.reviewApproval != saved.reviewApproval { pages.append(.agents) }
        if draft.reviewFolders != saved.reviewFolders { pages.append(.agents) }
        if draft.reviewOrgFolders != saved.reviewOrgFolders { pages.append(.agents) }
        self.pages = pages
    }

    var count: Int { pages.count }
    var isEmpty: Bool { pages.isEmpty }
    func touches(_ page: SettingsPage) -> Bool { pages.contains(page) }
}

struct SettingsView: View {
    @ObservedObject var model: SetupModel
    let onSave: (AppSettings) -> Void
    let onRedoSetup: () -> Void
    let onCheckForUpdates: () -> Void
    let onResetMascotPosition: () -> Void
    let agentAvailability: () -> AgentAvailability
    let cliStatus: () async -> CLIState
    let onTestReviewAgent: () -> Void
    let diagnostics: () -> DiagnosticsReport
    let onClose: () -> Void

    @LocalState private var page: SettingsPage
    @LocalState private var saved: AppSettings
    @LocalState private var isSaving = false
    @LocalState private var didSave = false
    @Namespace private var navigation

    static let size = CGSize(width: 900, height: 730)
    private static let sidebarWidth: CGFloat = 250

    init(
        model: SetupModel,
        initialPage: SettingsPage = .connection,
        onSave: @escaping (AppSettings) -> Void,
        onRedoSetup: @escaping () -> Void,
        onCheckForUpdates: @escaping () -> Void = {},
        onResetMascotPosition: @escaping () -> Void = {},
        agentAvailability: @escaping () -> AgentAvailability = { .ready },
        cliStatus: @escaping () async -> CLIState = { .unknown },
        onTestReviewAgent: @escaping () -> Void = {},
        diagnostics: @escaping () -> DiagnosticsReport = { .sample },
        onClose: @escaping () -> Void = {}
    ) {
        self.model = model
        self.onSave = onSave
        self.onRedoSetup = onRedoSetup
        self.onCheckForUpdates = onCheckForUpdates
        self.onResetMascotPosition = onResetMascotPosition
        self.agentAvailability = agentAvailability
        self.cliStatus = cliStatus
        self.onTestReviewAgent = onTestReviewAgent
        self.diagnostics = diagnostics
        self.onClose = onClose
        _page = LocalState(initialValue: initialPage)
        _saved = LocalState(initialValue: model.draft)
    }

    private var changes: SettingsChanges {
        SettingsChanges(draft: model.draft, saved: saved, hasNewToken: !model.personalToken.isEmpty)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: Self.sidebarWidth)
            main
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .borderlessWindowChrome()
        .task { _ = await model.validateConnection() }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            AccountCard(model: model)
            VStack(spacing: 3) {
                ForEach(SettingsPage.allCases, id: \.self) { item in navigationRow(item) }
            }
            .padding(.top, 18)
            Spacer()
            Text(tr("settings.version", Self.version))
                .font(.system(size: 11.5))
                .foregroundStyle(WizardPalette.ink3)
                .padding(.horizontal, 6)
        }
        .padding(.horizontal, 14)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(WizardPalette.side)
        .overlay(alignment: .trailing) { Rectangle().fill(WizardPalette.line).frame(width: 1) }
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
    }

    private func navigationRow(_ item: SettingsPage) -> some View {
        let selected = page == item
        return Button { withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { page = item } } label: {
            HStack(spacing: 11) {
                Image(systemName: item.symbol).font(.system(size: 14, weight: .medium)).frame(width: 18)
                Text(item.title).font(.system(size: 13.5, weight: .semibold))
                Spacer()
                Circle().fill(WizardPalette.accent).frame(width: 7, height: 7)
                    .scaleEffect(changes.touches(item) ? 1 : 0.3)
                    .opacity(changes.touches(item) ? 1 : 0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: changes.touches(item))
            }
            .foregroundStyle(selected ? WizardPalette.ink : WizardPalette.ink2)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(WizardPalette.card)
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(WizardPalette.line))
                        .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
                        .matchedGeometryEffect(id: "highlight", in: navigation)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Main

    private var main: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    pageContent.id(page)
                }
                .padding(.horizontal, 40)
                .padding(.top, 34)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            bottomBar
        }
        .overlay(alignment: .topTrailing) {
            WindowCloseButton(action: onClose).padding(.top, 14).padding(.trailing, 14)
        }
    }

    @ViewBuilder private var pageContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepTitle(title: page.title, lead: page.lead)
            Group {
                switch page {
                case .connection: ConnectionContent(model: model)
                case .organization: OrganizationContent(model: model)
                case .exceptions: ExceptionsContent(model: model)
                case .general: GeneralContent(model: model, onRedoSetup: onRedoSetup, onCheckForUpdates: onCheckForUpdates)
                case .mascot: MascotContent(model: model, onResetPosition: onResetMascotPosition)
                case .agents: AgentsContent(model: model, availability: agentAvailability, cliStatus: cliStatus, onTest: onTestReviewAgent)
                case .diagnostics: DiagnosticsContent(report: diagnostics)
                }
            }
            .padding(.top, 26)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            status
            Spacer()
            Button(tr("settings.discard"), action: discard)
                .buttonStyle(.plain)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(WizardPalette.ink2)
                .foregroundStyle(changes.isEmpty || isSaving ? WizardPalette.ink3 : WizardPalette.ink2)
                .disabled(changes.isEmpty || isSaving)
            saveButton
        }
        .padding(.horizontal, 40)
        .padding(.top, 14)
        .padding(.bottom, 22)
        .overlay(alignment: .top) { Rectangle().fill(WizardPalette.line).frame(height: 1) }
    }

    @ViewBuilder private var status: some View {
        if case .failed(let message) = model.validation, !isSaving {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 13)).foregroundStyle(WizardPalette.danger).lineLimit(1)
        } else {
            HStack(spacing: 8) {
                Circle().fill(changes.isEmpty ? WizardPalette.success : WizardPalette.accent).frame(width: 8, height: 8)
                Text(statusText).font(.system(size: 13)).foregroundStyle(WizardPalette.ink2)
            }
        }
    }

    private var statusText: String {
        switch changes.count {
        case 0: didSave ? tr("settings.allSaved") : tr("settings.clean")
        case 1: tr("settings.dirty.one")
        default: tr("settings.dirty.other", changes.count)
        }
    }

    private var saveButton: some View {
        Button { Task { await save() } } label: {
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView().controlSize(.small)
                    Text(tr("setup.checking"))
                } else if didSave {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                    Text(tr("settings.saved"))
                } else {
                    Text(tr("settings.save"))
                }
            }
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(saveForeground)
            .frame(minWidth: 110)
            .frame(height: 38)
            .padding(.horizontal, 18)
            .background(saveBackground, in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .keyboardShortcut("s")
        .disabled(changes.isEmpty || isSaving)
        .animation(.easeOut(duration: 0.2), value: didSave)
        .animation(.easeOut(duration: 0.2), value: changes.isEmpty)
    }

    private var isSaveActive: Bool { !changes.isEmpty || isSaving }

    private var saveForeground: Color {
        if didSave { return WizardPalette.bg }
        return isSaveActive ? WizardPalette.onAccent : WizardPalette.ink3
    }

    private var saveBackground: Color {
        if didSave { return WizardPalette.success }
        return isSaveActive ? WizardPalette.accent : WizardPalette.card2
    }

    // MARK: Actions

    private func discard() {
        model.draft = saved
        model.personalToken = ""
        didSave = false
    }

    private func save() async {
        isSaving = true
        didSave = false
        let valid = await model.validateConnection()
        isSaving = false
        guard valid else { return }
        guard !model.draft.orgs.isEmpty else { return model.reportFailure(tr("setup.org.required")) }
        onSave(model.draft)
        saved = model.draft
        didSave = true
        try? await Task.sleep(for: .seconds(1.7))
        didSave = false
    }
}

private struct AccountCard: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        HStack(spacing: 11) {
            Text((model.login ?? "·").prefix(1).uppercased())
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(nsColor: NSColor(hex: 0x10131A)))
                .frame(width: 36, height: 36)
                .background(
                    LinearGradient(colors: [Color(nsColor: NSColor(hex: 0x8AA4FF)), Color(nsColor: NSColor(hex: 0xBB99FF))], startPoint: .top, endPoint: .bottom),
                    in: Circle()
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(model.login ?? "…").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(WizardPalette.ink).lineLimit(1)
                HStack(spacing: 6) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(statusText).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(statusColor)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(WizardPalette.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(WizardPalette.line))
    }

    private var statusText: String {
        switch model.validation {
        case .idle, .checking: tr("setup.checking")
        case .failed: tr("settings.account.problem")
        case .ok: model.draft.authSource == .ghCli ? tr("settings.account.gh") : tr("settings.account.token")
        }
    }

    private var statusColor: Color {
        switch model.validation {
        case .idle, .checking: WizardPalette.ink3
        case .failed: WizardPalette.danger
        case .ok: WizardPalette.success
        }
    }
}
