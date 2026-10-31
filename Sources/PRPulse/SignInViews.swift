import AppKit
import PRPulseCore
import SwiftUI

/// A small button for the steps that sit under a choice card.
struct SignInButton: View {
    let title: String
    var symbol: String?
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .semibold)) }
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(isEnabled ? WizardPalette.accent : WizardPalette.ink3)
            .padding(.horizontal, 13)
            .frame(height: 34)
            .background(WizardPalette.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(WizardPalette.line))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

/// The part of a sign-in method that shows what the sign-in is doing: the code to enter while it waits, and how it ended.
/// While it is idle, or when it is another method's sign-in, `idle` is shown instead.
struct SignInFlow<Idle: View>: View {
    @ObservedObject var signIn: BrowserSignIn
    let method: BrowserSignIn.Method
    @ViewBuilder let idle: Idle

    var body: some View {
        Group {
            switch signIn.state {
            case .starting(let current) where current == method:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(tr("setup.signin.starting")).font(.system(size: 13)).foregroundStyle(WizardPalette.ink2)
                    Spacer()
                    SignInButton(title: tr("setup.signin.cancel")) { signIn.cancel() }
                }
            case .waiting(let current, let code) where current == method:
                waiting(code)
            case .done(let current) where current == method:
                done
            default:
                VStack(alignment: .leading, spacing: 10) {
                    idle
                    if case .failed(let failed, let message) = signIn.state, failed == method {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12.5))
                            .foregroundStyle(WizardPalette.danger)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: signIn.state)
    }

    private var done: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(WizardPalette.onAccent)
                .frame(width: 30, height: 30)
                .background(WizardPalette.success, in: Circle())
            Text(tr("setup.signin.done")).font(.system(size: 14, weight: .semibold)).foregroundStyle(WizardPalette.ink)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WizardPalette.success.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WizardPalette.success.opacity(0.45)))
    }

    private func waiting(_ code: DeviceCode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(code.userCode)
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(WizardPalette.ink)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                SignInButton(title: tr("setup.signin.copy"), symbol: "doc.on.doc") { signIn.copy(code) }
                SignInButton(title: tr("setup.signin.open"), symbol: "safari") { signIn.open(code) }
            }
            Text(tr("setup.signin.code.help")).font(.system(size: 12.5)).foregroundStyle(WizardPalette.ink2).lineSpacing(2)
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(tr("setup.signin.waiting")).font(.system(size: 12.5)).foregroundStyle(WizardPalette.ink3)
                Spacer()
                SignInButton(title: tr("setup.signin.cancel")) { signIn.cancel() }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WizardPalette.card, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(WizardPalette.accent.opacity(0.6)))
    }
}

/// A command to copy, shown the way a terminal would.
struct CopyableCommand: View {
    let command: String

    var body: some View {
        HStack {
            Text(command).font(.system(size: 13, design: .monospaced)).foregroundStyle(WizardPalette.ink)
            Spacer()
            SignInButton(title: tr("setup.signin.copy")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 42)
        .background(WizardPalette.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(WizardPalette.line))
    }
}
