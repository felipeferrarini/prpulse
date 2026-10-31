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

/// Where a sign-in that waits for the browser shows its code, and how it ended.
struct SignInPanel: View {
    @ObservedObject var signIn: BrowserSignIn

    var body: some View {
        Group {
            switch signIn.state {
            case .idle:
                EmptyView()
            case .starting:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(tr("setup.signin.starting")).font(.system(size: 13)).foregroundStyle(WizardPalette.ink2)
                    Spacer()
                    SignInButton(title: tr("setup.signin.cancel")) { signIn.cancel() }
                }
            case .waiting(_, let code):
                waiting(code)
            case .done:
                Label(tr("setup.signin.done"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WizardPalette.success)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12.5))
                    .foregroundStyle(WizardPalette.danger)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: signIn.state)
    }

    private func waiting(_ code: DeviceCode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Text(code.userCode)
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(WizardPalette.ink)
                    .textSelection(.enabled)
                Spacer()
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
