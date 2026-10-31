import PRPulseCore
import SwiftUI

/// The mascots to pick from, each one playing in its card once chosen.
struct MascotChooser: View {
    @Binding var selection: String
    @LocalState private var packs = MascotLibrary.loadPreviews()

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(packs, id: \.info.id) { pack in
                let selected = selection == pack.info.id
                SelectableCard(selected: selected) { selection = pack.info.id } content: {
                    VStack(spacing: 6) {
                        MascotSprite(pack: pack, mood: .calm, scale: 2, isAnimating: selected)
                        Text(pack.info.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WizardPalette.ink)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onDisappear { MascotLibrary.dropPreviews() }
    }
}

/// The mascot's options: shown in the wizard with the essentials, and in Settings with the rest.
struct MascotContent: View {
    @ObservedObject var model: SetupModel
    var onResetPosition: (() -> Void)?
    /// Keeps the toggle in place and scrolls only the grid, for a window that cannot grow with a long list.
    var scrollsChooser = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            showRow.staggered(2)
            chooser.staggered(3)
            if let onResetPosition {
                sizeRow.staggered(4)
                actionsRow(onResetPosition).staggered(5)
            }
        }
    }

    @ViewBuilder private var chooser: some View {
        let grid = MascotChooser(selection: $model.draft.mascotPack)
            .padding(.vertical, 14)
            .opacity(model.draft.mascotEnabled ? 1 : 0.45)
            .allowsHitTesting(model.draft.mascotEnabled)
        if scrollsChooser {
            ScrollView(.vertical, showsIndicators: false) { grid }
        } else {
            grid
        }
    }

    private var showRow: some View {
        HStack {
            label(tr("mascot.show"), detail: tr("mascot.show.detail"))
            Spacer()
            Toggle(tr("mascot.show"), isOn: $model.draft.mascotEnabled).toggleStyle(WizardSwitchStyle()).labelsHidden()
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(WizardPalette.line).frame(height: 1) }
    }

    private var sizeRow: some View {
        HStack {
            label(tr("mascot.size"), detail: tr("mascot.size.detail"))
            Spacer()
            HStack(spacing: 2) {
                ForEach([(tr("mascot.size.s"), 3), (tr("mascot.size.m"), 4), (tr("mascot.size.l"), 6)], id: \.1) { title, scale in
                    let selected = model.draft.mascotScale == scale
                    Button { withAnimation(.easeOut(duration: 0.2)) { model.draft.mascotScale = scale } } label: {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(selected ? WizardPalette.ink : WizardPalette.ink2)
                            .frame(minWidth: 34)
                            .frame(height: 32)
                            .padding(.horizontal, 4)
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

    private func actionsRow(_ reset: @escaping () -> Void) -> some View {
        HStack(alignment: .top) {
            label(tr("mascot.folder"), detail: tr("mascot.folder.detail"))
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                Button(action: openFolder) {
                    Label(tr("mascot.folder.open"), systemImage: "folder")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WizardPalette.accent)
                }
                .buttonStyle(.plain)
                Button(action: reset) {
                    Label(tr("mascot.reset"), systemImage: "arrow.down.right.square")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WizardPalette.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 14)
    }

    private func openFolder() {
        try? FileManager.default.createDirectory(at: MascotLibrary.userFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(MascotLibrary.userFolder)
    }

    private func label(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(WizardPalette.ink)
            Text(detail).font(.system(size: 12.5)).foregroundStyle(WizardPalette.ink2).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The wizard's last choice: the mascot, with a lead and the options.
struct MascotBody: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        StepFrame(scrolls: false) {
            StepTitle(title: tr("wizard.mascot.title"), lead: tr("wizard.mascot.lead"))
            MascotContent(model: model, scrollsChooser: true).padding(.top, 10)
        }
    }
}

/// The left half of the wizard while the mascot is chosen: the pick, going through its moods with a sample bubble.
struct MascotShowcase: View {
    let packID: String
    let isEnabled: Bool

    private var pack: MascotPack? { MascotLibrary.loadPreviews().first { $0.info.id == packID } }

    private static let moods: [MascotMood] = [.calm, .alert, .joy, .worried, .think, .sleep]

    var body: some View {
        VStack(spacing: 14) {
            if isEnabled, let pack {
                TimelineView(.periodic(from: .now, by: 3)) { context in
                    let index = Int(context.date.timeIntervalSinceReferenceDate / 3) % Self.moods.count
                    let mood = Self.moods[index]
                    VStack(spacing: 14) {
                        MascotBubbleView(title: tr("notification.title.other", 3), detail: "Per-tenant session cache")
                            .opacity(mood == .joy ? 1 : 0)
                            .scaleEffect(mood == .joy ? 1 : 0.9, anchor: .bottom)
                            .animation(.spring(duration: 0.4), value: mood)
                        MascotSprite(pack: pack, mood: mood, scale: 6)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(duration: 0.5), value: isEnabled)
    }
}
