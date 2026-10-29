import PRPulseCore
import SwiftUI

private struct StepTitle: View {
    let title: String
    var lead: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 27, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(WizardPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .staggered(0)
            if let lead {
                Text(lead)
                    .font(.system(size: 14.5))
                    .foregroundStyle(WizardPalette.ink2)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .staggered(1)
            }
        }
    }
}

private struct StepFrame<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, 32)
            .padding(.top, 26)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SelectableCard<Content: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: action) {
            content
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? WizardPalette.soft : WizardPalette.card, in: RoundedRectangle(cornerRadius: 13))
                .overlay(
                    RoundedRectangle(cornerRadius: 13)
                        .strokeBorder(selected ? WizardPalette.accent : WizardPalette.line, lineWidth: selected ? 1.5 : 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct RadioMark: View {
    let selected: Bool

    var body: some View {
        Circle()
            .strokeBorder(selected ? WizardPalette.accent : WizardPalette.off, lineWidth: selected ? 6 : 2)
            .frame(width: 20, height: 20)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selected)
            .accessibilityHidden(true)
    }
}

// MARK: - Welcome

struct WelcomeBody: View {
    let slide: Int
    let onSkip: () -> Void

    var body: some View {
        StepFrame {
            StepTitle(title: copy.title, lead: copy.body)
            HStack(spacing: 7) {
                ForEach(0 ..< WizardView.slideCount, id: \.self) { index in
                    Capsule()
                        .fill(index == slide ? WizardPalette.accent : WizardPalette.card2)
                        .frame(width: index == slide ? 22 : 7, height: 7)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: slide)
            .padding(.top, 26)
            .staggered(2)
            Button(tr("setup.skip"), action: onSkip)
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(WizardPalette.ink3)
                .padding(.top, 22)
                .staggered(3)
        }
    }

    private var copy: (title: String, body: String) {
        switch slide {
        case 0: (tr("setup.welcome.1.title"), tr("setup.welcome.1.body"))
        case 1: (tr("setup.welcome.2.title"), tr("setup.welcome.2.body"))
        default: (tr("setup.welcome.3.title"), tr("setup.welcome.3.body"))
        }
    }
}

// MARK: - Connect

struct ConnectBody: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        StepFrame {
            StepTitle(title: tr("setup.connect.title"), lead: tr("wizard.connect.lead"))
            VStack(alignment: .leading, spacing: 10) {
                option(.ghCli, symbol: "terminal", title: tr("setup.connect.gh"), detail: tr("wizard.connect.gh.detail"), status: ghStatus)
                option(.personalToken, symbol: "key", title: tr("setup.connect.token"), detail: tr("wizard.connect.token.detail"), status: nil)
                if model.draft.authSource == .personalToken { tokenField.transition(.opacity.combined(with: .move(edge: .top))) }
                if case .failed(let message) = model.validation {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12.5))
                        .foregroundStyle(WizardPalette.danger)
                }
                Label(tr("setup.connect.privacy"), systemImage: "lock")
                    .font(.system(size: 12))
                    .foregroundStyle(WizardPalette.ink3)
                    .padding(.top, 6)
            }
            .padding(.top, 20)
            .staggered(2)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: model.draft.authSource)
            Spacer(minLength: 0)
        }
        .task { await model.checkGh() }
    }

    private var ghStatus: (text: String, color: Color)? {
        switch model.ghStatus {
        case .unknown: nil
        case .available: (tr("setup.connect.gh.ok"), WizardPalette.success)
        case .notInstalled: (tr("setup.connect.gh.notInstalled"), Palette.ci)
        case .notLoggedIn: (tr("setup.connect.gh.notLoggedIn"), Palette.ci)
        }
    }

    private func option(_ source: AuthSource, symbol: String, title: String, detail: String, status: (text: String, color: Color)?) -> some View {
        SelectableCard(selected: model.draft.authSource == source) { model.draft.authSource = source } content: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(WizardPalette.ink)
                    .frame(width: 38, height: 38)
                    .background(WizardPalette.card2, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(WizardPalette.ink)
                    Text(detail).font(.system(size: 12.5)).foregroundStyle(WizardPalette.ink2)
                    if let status {
                        HStack(spacing: 6) {
                            Circle().fill(status.color).frame(width: 7, height: 7)
                            Text(status.text).font(.system(size: 12, weight: .semibold)).foregroundStyle(status.color)
                        }
                        .padding(.top, 3)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var tokenField: some View {
        VStack(alignment: .leading, spacing: 6) {
            SecureField(tr("setup.connect.token.placeholder"), text: $model.personalToken)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(WizardPalette.card, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(WizardPalette.line))
            if model.hasStoredToken { Text(tr("setup.connect.token.stored")).font(.caption).foregroundStyle(WizardPalette.ink3) }
            Link(tr("setup.connect.token.link"), destination: URL(string: "https://github.com/settings/tokens/new?scopes=repo,read:org&description=PRPulse")!)
                .font(.caption)
        }
    }
}

// MARK: - Organization

struct OrganizationBody: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        StepFrame {
            StepTitle(title: tr("setup.org.title"), lead: tr("setup.org.caption"))
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(model.organizations.enumerated()), id: \.element) { index, org in
                        row(org).staggered(2 + index)
                    }
                }
                .padding(.vertical, 2)
            }
            .padding(.top, 14)
        }
    }

    private var mostActive: Int {
        max(model.organizationActivity.values.max() ?? 0, 1)
    }

    private func row(_ org: String) -> some View {
        let selected = model.draft.org == org
        let count = model.organizationActivity[org] ?? 0
        return SelectableCard(selected: selected) { model.draft.org = org } content: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(org).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(WizardPalette.ink)
                    if let detail = detail(org, count: count) {
                        Text(detail).font(.system(size: 12)).foregroundStyle(WizardPalette.ink2)
                    }
                }
                Spacer()
                if count > 0 {
                    Capsule().fill(WizardPalette.card2).frame(width: 90, height: 5)
                        .overlay(alignment: .leading) {
                            Capsule().fill(WizardPalette.accent).frame(width: 90 * CGFloat(count) / CGFloat(mostActive))
                        }
                }
                RadioMark(selected: selected)
            }
        }
    }

    private func detail(_ org: String, count: Int) -> String? {
        if model.isPersonal(org) { return tr("setup.org.personal") }
        return count > 0 ? tr("wizard.org.activity", count) : nil
    }
}

// MARK: - Exceptions

struct ExceptionsBody: View {
    @ObservedObject var model: SetupModel
    @LocalState private var filter = ""
    @LocalState private var botInput = ""
    @LocalState private var repoInput = ""

    var body: some View {
        StepFrame {
            StepTitle(title: tr("setup.exceptions.title"))
            section(tr("setup.exceptions.repos"), caption: tr("setup.exceptions.repos.caption")) { repositories }
                .padding(.top, 14)
                .staggered(1)
            section(tr("setup.exceptions.bots"), caption: tr("setup.exceptions.bots.caption")) {
                chips(items: $model.draft.ignoredBots, input: $botInput, kind: .account)
            }
            .padding(.top, 18)
            .staggered(2)
            Spacer(minLength: 0)
        }
        .task(id: model.draft.org) { await model.loadRepositories() }
    }

    private func section<Content: View>(_ title: String, caption: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(WizardPalette.ink)
            Text(caption).font(.system(size: 12.5)).foregroundStyle(WizardPalette.ink2).padding(.bottom, 6)
            content()
        }
    }

    @ViewBuilder private var repositories: some View {
        switch model.repositories {
        case .idle: EmptyView()
        case .loading:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text(tr("setup.exceptions.repos.loading")).font(.caption) }
        case .failed:
            VStack(alignment: .leading, spacing: 6) {
                chips(items: $model.draft.ignoredRepos, input: $repoInput, kind: .repository)
                Text(tr("setup.exceptions.repos.failed")).font(.caption).foregroundStyle(WizardPalette.ink3)
            }
        case .loaded(let names):
            if !names.isEmpty { repositoryList(names) }
        }
    }

    private func repositoryList(_ names: [String]) -> some View {
        let shown = filter.isEmpty ? names : names.filter { $0.localizedCaseInsensitiveContains(filter) }
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(WizardPalette.ink3)
                TextField(tr("setup.exceptions.repos.search", names.count), text: $filter).textFieldStyle(.plain)
            }
            .padding(.horizontal, 11)
            .frame(height: 36)
            .background(WizardPalette.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(WizardPalette.line))
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(shown, id: \.self) { name in repositoryRow(name) }
                }
            }
            .frame(height: 138)
            .background(WizardPalette.card, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(WizardPalette.line))
        }
    }

    private func repositoryRow(_ name: String) -> some View {
        let ignored = model.draft.ignoredRepos.contains(name)
        return Button {
            model.draft.ignoredRepos = ignored
                ? ListEditing.removing(name, from: model.draft.ignoredRepos)
                : ListEditing.adding(name, to: model.draft.ignoredRepos, kind: .repository)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: ignored ? "checkmark.square.fill" : "square")
                    .foregroundStyle(ignored ? WizardPalette.accent : WizardPalette.off)
                Text(name).strikethrough(ignored).foregroundStyle(ignored ? WizardPalette.ink3 : WizardPalette.ink)
                Spacer()
            }
            .font(.system(size: 13.5))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(ignored ? .isSelected : [])
    }

    private func chips(items: Binding<[String]>, input: Binding<String>, kind: ListEditing.Kind) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(items.wrappedValue, id: \.self) { item in
                HStack(spacing: 6) {
                    Text(item).font(.system(size: 12.5))
                    Button { items.wrappedValue = ListEditing.removing(item, from: items.wrappedValue) } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(WizardPalette.ink3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item)
                }
                .padding(.leading, 11)
                .padding(.trailing, 8)
                .frame(height: 28)
                .background(WizardPalette.card2, in: RoundedRectangle(cornerRadius: 8))
            }
            TextField(tr("setup.exceptions.add"), text: input)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .frame(width: 100, height: 28)
                .onSubmit {
                    items.wrappedValue = ListEditing.adding(input.wrappedValue, to: items.wrappedValue, kind: kind)
                    input.wrappedValue = ""
                }
        }
    }
}

// MARK: - General

struct GeneralBody: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        StepFrame {
            StepTitle(title: tr("wizard.general.title"), lead: tr("wizard.general.lead"))
            VStack(spacing: 0) {
                intervalRow.staggered(2)
                switchRow(tr("setup.general.notifications"), detail: tr("wizard.general.notifications.detail"), isOn: $model.draft.notificationsEnabled)
                    .staggered(3)
                switchRow(tr("setup.general.launch"), detail: tr("wizard.general.launch.detail"), isOn: $model.draft.launchAtLogin)
                    .staggered(4)
            }
            .padding(.top, 14)
            Spacer(minLength: 0)
        }
    }

    private var intervalRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            label(tr("setup.general.interval"), detail: tr("wizard.general.interval.detail"))
            HStack(spacing: 2) {
                ForEach(AppSettings.refreshOptions, id: \.self) { minutes in
                    let selected = model.draft.refreshMinutes == minutes
                    Button { withAnimation(.easeOut(duration: 0.2)) { model.draft.refreshMinutes = minutes } } label: {
                        Text(tr("setup.general.minutes", minutes))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(selected ? WizardPalette.ink : WizardPalette.ink2)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(selected ? WizardPalette.card2 : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .shadow(color: .black.opacity(selected ? 0.18 : 0), radius: 1.5, y: 1)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(3)
            .background(WizardPalette.card, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(WizardPalette.line))
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(WizardPalette.line).frame(height: 1) }
    }

    private func switchRow(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack {
            label(title, detail: detail)
            Spacer()
            Toggle(title, isOn: isOn).toggleStyle(.switch).tint(WizardPalette.accent).labelsHidden()
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(WizardPalette.line).frame(height: 1) }
    }

    private func label(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(WizardPalette.ink)
            Text(detail).font(.system(size: 12.5)).foregroundStyle(WizardPalette.ink2)
        }
    }
}

// MARK: - Done

struct DoneBody: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        StepFrame {
            StepTitle(title: tr("wizard.done.title"), lead: tr("wizard.done.lead"))
            VStack(alignment: .leading, spacing: 12) {
                line("arrow.triangle.branch", tr("wizard.done.org", model.draft.org)).staggered(2)
                line("clock", tr("wizard.done.interval", model.draft.refreshMinutes)).staggered(3)
                line("eye", tr("wizard.done.ignored", model.draft.ignoredRepos.count, model.draft.ignoredBots.count)).staggered(4)
                line("bell", model.draft.notificationsEnabled ? tr("wizard.done.notifications.on") : tr("wizard.done.notifications.off")).staggered(5)
            }
            .padding(.top, 22)
            Spacer(minLength: 0)
        }
    }

    private func line(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(WizardPalette.accent)
                .frame(width: 28, height: 28)
                .background(WizardPalette.soft, in: RoundedRectangle(cornerRadius: 8))
            Text(text).font(.system(size: 14)).foregroundStyle(WizardPalette.ink)
        }
    }
}
