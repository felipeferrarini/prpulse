import AppKit
import PRPulseCore
import SwiftUI

/// When PRPulse speaks up on this Mac: a new pull request that needs the viewer, and an author's nudge.
struct NotificationsContent: View {
    @ObservedObject var model: SetupModel
    @LocalState private var systemSounds: [NudgeSoundOption] = []
    @LocalState private var userSounds: [NudgeSoundOption] = []

    private var soundsOn: Bool { model.draft.nudgesEnabled && model.draft.nudgeSoundEnabled }

    var body: some View {
        VStack(spacing: 0) {
            switchRow(tr("setup.general.notifications"), detail: tr("wizard.general.notifications.detail"), isOn: $model.draft.notificationsEnabled)
                .staggered(1)
            groupTitle(tr("settings.notifications.nudges"))
                .staggered(2)
            switchRow(tr("settings.nudges.title"), detail: tr("settings.nudges.detail"), isOn: $model.draft.nudgesEnabled)
                .staggered(3)
            switchRow(tr("settings.nudges.sound.title"), detail: tr("settings.nudges.sound.detail"), isOn: $model.draft.nudgeSoundEnabled)
                .staggered(4)
                .opacity(model.draft.nudgesEnabled ? 1 : 0.45)
                .allowsHitTesting(model.draft.nudgesEnabled)
            nudgeSoundChoiceRow
                .staggered(5)
                .opacity(soundsOn ? 1 : 0.45)
                .allowsHitTesting(soundsOn)
        }
    }

    private var nudgeSoundChoiceRow: some View {
        HStack(alignment: .top, spacing: 14) {
            label(tr("settings.nudges.choice.title"), detail: tr("settings.nudges.choice.detail"))
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 10) {
                    soundMenu
                    Button { NudgeSound.play(tone: 1, id: model.draft.nudgeSound) } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(WizardPalette.accent)
                            .frame(width: 32, height: 32)
                            .background(WizardPalette.card, in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(WizardPalette.line))
                    }
                    .buttonStyle(.plain)
                    .help(tr("settings.nudges.choice.preview"))
                    .accessibilityLabel(tr("settings.nudges.choice.preview"))
                }
                Button(action: NudgeSoundLibrary.openFolder) {
                    Label(tr("settings.nudges.choice.folder"), systemImage: "folder")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WizardPalette.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(WizardPalette.line).frame(height: 1) }
        .onAppear(perform: reloadSounds)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in reloadSounds() }
    }

    private var soundMenu: some View {
        Menu {
            ForEach(systemSounds) { soundItem($0) }
            if !userSounds.isEmpty {
                Divider()
                ForEach(userSounds) { soundItem($0) }
            }
        } label: {
            HStack(spacing: 6) {
                Text((NudgeSoundChoice(id: model.draft.nudgeSound) ?? .fallback).name)
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

    private func soundItem(_ option: NudgeSoundOption) -> some View {
        Button {
            model.draft.nudgeSound = option.id
            NudgeSound.play(tone: 1, id: option.id)
        } label: {
            if model.draft.nudgeSound == option.id { Label(option.name, systemImage: "checkmark") } else { Text(option.name) }
        }
    }

    private func reloadSounds() {
        systemSounds = NudgeSoundLibrary.system()
        userSounds = NudgeSoundLibrary.user()
    }

    private func groupTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(WizardPalette.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 22)
            .padding(.bottom, 2)
    }

    private func switchRow(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack {
            label(title, detail: detail)
            Spacer()
            Toggle(title, isOn: isOn).toggleStyle(WizardSwitchStyle()).labelsHidden()
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
