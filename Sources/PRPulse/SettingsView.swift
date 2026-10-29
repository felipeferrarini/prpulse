import PRPulseCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: SetupModel
    let onSave: (AppSettings) -> Void
    let onRedoSetup: () -> Void

    @LocalState private var didSave = false
    @LocalState private var isBusy = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section(tr("settings.section.connection")) { ConnectionSection(model: model) }
                    section(tr("settings.section.organization")) { OrganizationSection(model: model) }
                    section(tr("settings.section.exceptions")) { ExceptionsSection(model: model) }
                    section(tr("settings.section.general")) { GeneralSection(model: model) }
                }
                .padding(24)
            }
            Divider()
            footer
        }
        .frame(width: 540, height: 600)
        .task { _ = await model.validateConnection() }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }

    private var footer: some View {
        HStack {
            Button(tr("settings.redo"), action: onRedoSetup)
                .buttonStyle(.link)
                .help(tr("settings.redo.help"))
            if didSave { Label(tr("settings.saved"), systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            Spacer()
            if isBusy { ProgressView().controlSize(.small) }
            Button(tr("settings.save")) { Task { await save() } }
                .keyboardShortcut("s")
                .disabled(isBusy)
        }
        .padding(14)
    }

    private func save() async {
        isBusy = true
        didSave = false
        let valid = await model.validateConnection()
        isBusy = false
        guard valid else { return }
        guard !model.draft.org.isEmpty else { return model.reportFailure(tr("setup.org.required")) }
        onSave(model.draft)
        didSave = true
    }
}
