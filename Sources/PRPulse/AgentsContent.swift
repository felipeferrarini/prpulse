import PRPulseCore
import SwiftUI

/// The agents that can be asked to review a pull request, and how the request is made.
struct AgentsContent: View {
    @ObservedObject var model: SetupModel
    let availability: () -> AgentAvailability
    let cliStatus: () async -> CLIState
    let onTest: () -> Void
    /// The setup wizard asks only for what decides whether and how reviews run; the rest is in Settings.
    var isCompact = false

    @LocalState private var status = AgentAvailability.ready
    @LocalState private var cli = CLIState.unknown
    @LocalState private var skills: [ReviewSkill] = []

    private var automaticSkill: ReviewSkill? { ReviewSkillCatalog.automatic(from: skills) }

    private var resolvedSkill: ReviewSkill? {
        ReviewSkillCatalog.resolve(choice: model.draft.reviewSkill, from: skills)
    }

    private var defaultPrompt: String {
        resolvedSkill == nil ? tr("agents.prompt.generic") : tr("agents.prompt.skill")
    }

    var body: some View {
        VStack(spacing: 0) {
            enabledRow.staggered(2)
            statusRow.staggered(3)
            cliRow.staggered(4)
            approvalRow.staggered(5)
            if !isCompact {
                skillRow.staggered(6)
                projectRow.staggered(7)
                promptRow.staggered(8)
                foldersRow.staggered(9)
            }
        }
        .task {
            status = availability()
            cli = await cliStatus()
            let home = FileManager.default.homeDirectoryForCurrentUser
            skills = await Task.detached { ReviewSkillCatalog.discover(home: home) }.value
        }
    }

    // MARK: Rows

    private var enabledRow: some View {
        HStack {
            label(tr("agents.enabled.title"), detail: tr("agents.enabled.detail"))
            Spacer()
            Toggle(tr("agents.enabled.title"), isOn: $model.draft.reviewAgentEnabled).toggleStyle(WizardSwitchStyle()).labelsHidden()
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { divider }
    }

    private var statusRow: some View {
        HStack(spacing: 14) {
            label(tr("agents.status.title"), detail: status == .ready ? tr("agents.status.ready") : tr("agents.status.missing"))
            Spacer()
            Circle().fill(status == .ready ? WizardPalette.success : Palette.ci).frame(width: 8, height: 8)
            Button(action: onTest) {
                Text(tr("agents.test"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(status == .ready ? WizardPalette.accent : WizardPalette.ink3)
            }
            .buttonStyle(.plain)
            .disabled(status != .ready)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { divider }
    }

    private var cliRow: some View {
        HStack(spacing: 14) {
            label(tr("agents.cli.title"), detail: cliDetail)
            Spacer()
            Circle().fill(cli.isReady ? WizardPalette.success : (cli == .unknown ? WizardPalette.ink3 : Palette.ci)).frame(width: 8, height: 8)
            Button { Task { cli = .unknown; cli = await cliStatus() } } label: {
                Text(tr("agents.cli.check")).font(.system(size: 13, weight: .semibold)).foregroundStyle(WizardPalette.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { divider }
    }

    private var cliDetail: String {
        switch cli {
        case .unknown: tr("agents.cli.checking")
        case .missing: tr("agents.cli.missing")
        case .signedOut: tr("agents.cli.signedOut")
        case .ready(let account): account.map { tr("agents.cli.ready", $0) } ?? tr("agents.cli.readyNoAccount")
        }
    }

    private var approvalRow: some View {
        HStack(alignment: .top, spacing: 14) {
            label(tr("agents.approval.mode.title"), detail: tr(model.draft.reviewApproval == .automatic ? "agents.approval.mode.automaticDetail" : "agents.approval.mode.askDetail"))
            Spacer()
            Menu {
                approvalItem(.automatic, title: tr("agents.approval.mode.automatic"))
                approvalItem(.ask, title: tr("agents.approval.mode.ask"))
            } label: {
                HStack(spacing: 6) {
                    Text(tr(model.draft.reviewApproval == .automatic ? "agents.approval.mode.automatic" : "agents.approval.mode.ask"))
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(WizardPalette.ink)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(WizardPalette.card, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(WizardPalette.line))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { divider }
    }

    private func approvalItem(_ choice: ReviewApproval, title: String) -> some View {
        Button { model.draft.reviewApproval = choice } label: {
            if model.draft.reviewApproval == choice { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }

    private var skillRow: some View {
        HStack(alignment: .top, spacing: 14) {
            label(tr("agents.skill.title"), detail: tr("agents.skill.detail"))
            Spacer()
            Menu {
                skillItem(ReviewSkillCatalog.automaticChoice, title: automaticTitle)
                skillItem(ReviewSkillCatalog.noneChoice, title: tr("agents.skill.none"))
                if !skills.isEmpty { Divider() }
                ForEach(skills) { skill in skillItem(skill.name, title: title(of: skill)) }
            } label: {
                HStack(spacing: 6) {
                    Text(currentSkillTitle).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(WizardPalette.ink)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(WizardPalette.card, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(WizardPalette.line))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { divider }
    }

    /// The organizations being watched, plus any that has a default project but is no longer watched.
    private var projectOrganizations: [String] {
        let watched = model.draft.orgs
        let known = Set(watched.map { $0.lowercased() })
        return watched + model.draft.reviewOrgFolders.keys.filter { !known.contains($0) }.sorted()
    }

    private var projectRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            label(tr("agents.org.title"), detail: tr("agents.org.detail"))
            VStack(spacing: 8) { ForEach(projectOrganizations, id: \.self) { organization($0) } }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { divider }
    }

    private func organization(_ name: String) -> some View {
        let path = model.draft.reviewOrgFolders[name.lowercased()] ?? ""
        return HStack(spacing: 12) {
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WizardPalette.ink)
                .lineLimit(1)
                .frame(width: 130, alignment: .leading)
            Text(path.isEmpty ? tr("agents.org.none") : path)
                .font(.system(size: 12.5))
                .foregroundStyle(path.isEmpty ? WizardPalette.ink3 : WizardPalette.ink2)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if !path.isEmpty {
                Button { model.draft.reviewOrgFolders[name.lowercased()] = nil } label: {
                    Text(tr("agents.org.clear")).font(.system(size: 13, weight: .semibold)).foregroundStyle(WizardPalette.ink2)
                }
                .buttonStyle(.plain)
            }
            Button { chooseProject(for: name) } label: {
                Text(tr("agents.org.choose")).font(.system(size: 13, weight: .semibold)).foregroundStyle(WizardPalette.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(WizardPalette.card, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(WizardPalette.line))
    }

    private func chooseProject(for organization: String) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = tr("agents.org.panel", organization)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.draft.reviewOrgFolders[organization.lowercased()] = url.path
    }

    private var promptRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                label(tr("agents.prompt.title"), detail: tr("agents.prompt.detail", ReviewPrompt.placeholders.joined(separator: " ")))
                Spacer()
                if !model.draft.reviewPrompt.isEmpty {
                    Button { model.draft.reviewPrompt = "" } label: {
                        Text(tr("agents.prompt.reset")).font(.system(size: 13, weight: .semibold)).foregroundStyle(WizardPalette.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            TextEditor(text: promptBinding)
                .font(.system(size: 12.5))
                .foregroundStyle(WizardPalette.ink)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 118)
                .background(WizardPalette.card, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(WizardPalette.line))
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { divider }
    }

    private var foldersRow: some View {
        let folders = model.draft.reviewFolders.sorted { $0.key < $1.key }
        return VStack(alignment: .leading, spacing: 10) {
            label(tr("agents.folders.title"), detail: tr("agents.folders.detail"))
            if folders.isEmpty {
                Text(tr("agents.folders.empty")).font(.system(size: 12.5)).foregroundStyle(WizardPalette.ink3)
            } else {
                VStack(spacing: 8) { ForEach(folders, id: \.key) { folder($0.key, $0.value) } }
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func folder(_ key: String, _ path: String) -> some View {
        HStack(spacing: 12) {
            Text(key).font(.system(size: 13, weight: .semibold)).foregroundStyle(WizardPalette.ink)
            Text(path.isEmpty ? tr("agents.folders.noClone") : path)
                .font(.system(size: 12.5))
                .foregroundStyle(WizardPalette.ink2)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Button { model.draft.reviewFolders[key] = nil } label: {
                Text(tr("agents.folders.forget")).font(.system(size: 13, weight: .semibold)).foregroundStyle(WizardPalette.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(WizardPalette.card, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(WizardPalette.line))
    }

    // MARK: Skill choice

    private func skillItem(_ choice: String, title: String) -> some View {
        Button { model.draft.reviewSkill = choice } label: {
            if model.draft.reviewSkill == choice { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }

    private func title(of skill: ReviewSkill) -> String {
        switch skill.source {
        case .personal: skill.name
        case .plugin(let plugin): tr("agents.skill.fromPlugin", skill.name, plugin)
        }
    }

    private var automaticTitle: String {
        automaticSkill.map { tr("agents.skill.automatic.found", $0.name) } ?? tr("agents.skill.automatic")
    }

    private var currentSkillTitle: String {
        switch model.draft.reviewSkill {
        case ReviewSkillCatalog.automaticChoice: automaticTitle
        case ReviewSkillCatalog.noneChoice: tr("agents.skill.none")
        default: model.draft.reviewSkill
        }
    }

    // MARK: Prompt

    /// Shows the text that will be sent; typing anything else keeps it, and typing the default back clears it.
    private var promptBinding: Binding<String> {
        Binding(
            get: { model.draft.reviewPrompt.isEmpty ? defaultPrompt : model.draft.reviewPrompt },
            set: { model.draft.reviewPrompt = $0 == defaultPrompt ? "" : $0 }
        )
    }

    // MARK: Pieces

    private var divider: some View { Rectangle().fill(WizardPalette.line).frame(height: 1) }

    private func label(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(WizardPalette.ink)
            Text(detail).font(.system(size: 12.5)).foregroundStyle(WizardPalette.ink2).fixedSize(horizontal: false, vertical: true)
        }
    }
}
