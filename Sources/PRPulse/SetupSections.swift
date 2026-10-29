import PRPulseCore
import ServiceManagement
import SwiftUI

struct ConnectionSection: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            choice(.ghCli, title: tr("setup.connect.gh"), detail: ghDetail)
            choice(.personalToken, title: tr("setup.connect.token"), detail: nil)
            if model.draft.authSource == .personalToken { tokenFields }
            ValidationBanner(validation: model.validation)
            Label(tr("setup.connect.privacy"), systemImage: "lock.fill")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task { await model.checkGh() }
    }

    private var ghDetail: (text: String, color: Color)? {
        switch model.ghStatus {
        case .unknown: nil
        case .available: (tr("setup.connect.gh.ok"), .green)
        case .notInstalled: (tr("setup.connect.gh.notInstalled"), .orange)
        case .notLoggedIn: (tr("setup.connect.gh.notLoggedIn"), .orange)
        }
    }

    private func choice(_ source: AuthSource, title: String, detail: (text: String, color: Color)?) -> some View {
        let selected = model.draft.authSource == source
        return Button { model.draft.authSource = source } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let detail { Text(detail.text).font(.caption).foregroundStyle(detail.color) }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var tokenFields: some View {
        VStack(alignment: .leading, spacing: 6) {
            SecureField(tr("setup.connect.token.placeholder"), text: $model.personalToken)
                .textFieldStyle(.roundedBorder)
            if model.hasStoredToken { Text(tr("setup.connect.token.stored")).font(.caption).foregroundStyle(.secondary) }
            Link(tr("setup.connect.token.link"), destination: URL(string: "https://github.com/settings/tokens/new?scopes=repo,read:org&description=PRPulse")!)
                .font(.caption)
        }
        .padding(.leading, 26)
    }
}

struct ValidationBanner: View {
    let validation: SetupModel.Validation

    var body: some View {
        switch validation {
        case .idle, .ok: EmptyView()
        case .checking:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text(tr("setup.checking")).font(.caption) }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.red)
        }
    }
}

struct OrganizationSection: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("setup.org.caption")).font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.organizations, id: \.self) { org in row(org) }
                }
            }
        }
    }

    private func row(_ org: String) -> some View {
        let selected = model.draft.org == org
        return Button { model.draft.org = org } label: {
            HStack {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                Text(org).fontWeight(.medium)
                if model.isPersonal(org) { Text(tr("setup.org.personal")).font(.caption).foregroundStyle(.secondary) }
                Spacer()
            }
            .padding(10)
            .background(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ExceptionsSection: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ChipEditor(title: tr("setup.exceptions.repos"), caption: tr("setup.exceptions.repos.caption"),
                       kind: .repository, items: $model.draft.ignoredRepos, allowsInput: model.repositories == .failed)
            RepositoryPicker(repositories: model.repositories, ignored: $model.draft.ignoredRepos)
            ChipEditor(title: tr("setup.exceptions.bots"), caption: tr("setup.exceptions.bots.caption"),
                       kind: .account, items: $model.draft.ignoredBots)
        }
        .task(id: model.draft.org) { await model.loadRepositories() }
    }
}

struct RepositoryPicker: View {
    let repositories: SetupModel.RepositoryList
    @Binding var ignored: [String]
    @LocalState private var filter = ""

    var body: some View {
        switch repositories {
        case .idle: EmptyView()
        case .loading:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text(tr("setup.exceptions.repos.loading")).font(.caption) }
        case .failed:
            Text(tr("setup.exceptions.repos.failed")).font(.caption).foregroundStyle(.secondary)
        case .loaded(let names):
            if !names.isEmpty { list(names) }
        }
    }

    private func list(_ names: [String]) -> some View {
        let shown = filter.isEmpty ? names : names.filter { $0.localizedCaseInsensitiveContains(filter) }
        return VStack(alignment: .leading, spacing: 4) {
            TextField(tr("setup.exceptions.repos.search", names.count), text: $filter)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(shown, id: \.self) { name in row(name) }
                }
            }
            .frame(height: 96)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func row(_ name: String) -> some View {
        let isIgnored = ignored.contains(name)
        return Button {
            ignored = isIgnored ? ListEditing.removing(name, from: ignored) : ListEditing.adding(name, to: ignored, kind: .repository)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isIgnored ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isIgnored ? Color.accentColor : .secondary)
                Text(name).font(.callout)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ChipEditor: View {
    let title: String
    let caption: String
    let kind: ListEditing.Kind
    @Binding var items: [String]
    var allowsInput = true
    @LocalState private var input = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(caption).font(.caption).foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(items, id: \.self) { item in chip(item) }
                if allowsInput {
                    TextField(tr("setup.exceptions.add"), text: $input)
                        .textFieldStyle(.plain)
                        .frame(width: 110)
                        .padding(.vertical, 3)
                        .onSubmit(commit)
                }
            }
        }
    }

    private func chip(_ item: String) -> some View {
        HStack(spacing: 4) {
            Text(item).font(.callout)
            Button { items = ListEditing.removing(item, from: items) } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.1), in: Capsule())
    }

    private func commit() {
        items = ListEditing.adding(input, to: items, kind: kind)
        input = ""
    }
}

struct GeneralSection: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker(tr("setup.general.interval"), selection: $model.draft.refreshMinutes) {
                ForEach(AppSettings.refreshOptions, id: \.self) { minutes in
                    Text(tr("setup.general.minutes", minutes)).tag(minutes)
                }
            }
            .frame(maxWidth: 260)
            Toggle(tr("setup.general.notifications"), isOn: $model.draft.notificationsEnabled)
            Toggle(tr("setup.general.launch"), isOn: $model.draft.launchAtLogin)
        }
    }
}

enum LaunchAtLogin {
    static func apply(_ enabled: Bool) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let service = SMAppService.mainApp
        if enabled { try? service.register() } else { try? service.unregister() }
    }
}
