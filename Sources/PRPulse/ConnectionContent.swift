import AppKit
import PRPulseCore
import SwiftUI

/// The ways to sign in. Only the one that is picked shows what to do, so the step never shows all of them at once.
enum ConnectionMethod: Equatable {
    case gh, browser, token

    var signInMethod: BrowserSignIn.Method? {
        switch self {
        case .gh: .gh
        case .browser: .github
        case .token: nil
        }
    }
}

struct ConnectionContent: View {
    @ObservedObject var model: SetupModel
    @ObservedObject private var signIn: BrowserSignIn

    @LocalState private var method: ConnectionMethod
    @LocalState private var pasteNote: String?

    init(model: SetupModel) {
        self.model = model
        _signIn = ObservedObject(wrappedValue: model.signIn)
        _method = LocalState(initialValue: Self.initialMethod(model))
    }

    /// The one that was in use, or the one that is ready to be: the team's app when there is a Client ID and no token yet.
    static func initialMethod(_ model: SetupModel) -> ConnectionMethod {
        if model.draft.authSource == .ghCli { return .gh }
        if model.hasStoredToken { return .token }
        return model.clientID.isEmpty ? .token : .browser
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(.gh, title: tr("setup.connect.gh"), detail: tr("wizard.connect.gh.detail"), badge: ghBadge) { ghContent }
            row(.browser, title: tr("setup.signin.browser"), detail: tr("setup.method.browser.detail"), badge: nil) { browserContent }
            row(.token, title: tr("setup.connect.token"), detail: tr("wizard.connect.token.detail"), badge: nil) { tokenContent }
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
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: method)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: model.ghStatus)
        .task { await model.checkGh() }
    }

    private func select(_ chosen: ConnectionMethod) {
        guard chosen != method else { return }
        if signIn.isBusy { signIn.cancel() }
        method = chosen
        pasteNote = nil
        model.draft.authSource = chosen == .gh ? .ghCli : .personalToken
    }

    // MARK: Rows

    private func row<Content: View>(
        _ own: ConnectionMethod, title: String, detail: String, badge: (text: String, color: Color)?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let selected = method == own
        return VStack(alignment: .leading, spacing: 12) {
            Button { select(own) } label: {
                HStack(spacing: 12) {
                    RadioMark(selected: selected)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(WizardPalette.ink)
                        Text(detail).font(.system(size: 12.5)).foregroundStyle(WizardPalette.ink2)
                    }
                    Spacer(minLength: 0)
                    if let badge {
                        HStack(spacing: 6) {
                            Circle().fill(badge.color).frame(width: 7, height: 7)
                            Text(badge.text).font(.system(size: 12, weight: .semibold)).foregroundStyle(badge.color)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            if selected { content().transition(.opacity.combined(with: .move(edge: .top))) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? WizardPalette.soft : WizardPalette.card, in: RoundedRectangle(cornerRadius: 13))
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(selected ? WizardPalette.accent : WizardPalette.line, lineWidth: selected ? 1.5 : 1)
        )
    }

    // MARK: gh

    private var ghBadge: (text: String, color: Color)? {
        switch model.ghStatus {
        case .unknown: nil
        case .available: (tr("setup.badge.ready"), WizardPalette.success)
        case .notInstalled: (tr("setup.badge.notInstalled"), Palette.ci)
        case .notLoggedIn: (tr("setup.badge.noLogin"), Palette.ci)
        }
    }

    private var ghContent: some View {
        SignInFlow(signIn: signIn, method: .gh) {
            switch model.ghStatus {
            case .available:
                note(tr("setup.signin.gh.ready"))
            case .notLoggedIn:
                SignInButton(title: tr("setup.signin.gh"), symbol: "person.badge.key") { signIn.start(.gh) }
                note(tr("setup.signin.gh.help"))
            case .notInstalled:
                CopyableCommand(command: "brew install gh")
                note(tr("setup.signin.gh.install"))
            case .unknown:
                EmptyView()
            }
        }
    }

    // MARK: Browser

    private var browserContent: some View {
        SignInFlow(signIn: signIn, method: .github) {
            note(tr("setup.team.help"))
            TextField(model.managedClientID ?? tr("setup.team.placeholder"), text: $model.draft.oauthClientID)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(WizardPalette.card, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(clientFieldBorder))
            if model.managedClientID != nil, model.draft.oauthClientID.isEmpty {
                Text(tr("setup.team.managed")).font(.caption).foregroundStyle(WizardPalette.ink3)
            }
            HStack {
                SignInButton(title: tr("setup.signin.browser"), symbol: "safari") {
                    signIn.start(.github, clientID: model.clientID)
                }
                .disabled(model.clientID.isEmpty || signIn.isBusy)
                Spacer()
                Link(tr("setup.team.guide"), destination: OAuthApp.guideURL).font(.system(size: 12.5, weight: .semibold))
            }
        }
    }

    private var clientFieldBorder: Color {
        if case .failed(.github, _) = signIn.state { return WizardPalette.danger }
        return WizardPalette.line
    }

    // MARK: Token

    private var tokenContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SignInButton(title: tr("setup.connect.token.link"), symbol: "arrow.up.right.square") {
                    NSWorkspace.shared.open(TokenFormat.creationURL)
                }
                SignInButton(title: tr("setup.signin.paste"), symbol: "doc.on.clipboard", action: pasteToken)
            }
            SecureField(tr("setup.connect.token.placeholder"), text: $model.personalToken)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(WizardPalette.card, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(WizardPalette.line))
            if let pasteNote {
                Text(pasteNote).font(.caption).foregroundStyle(WizardPalette.ink3)
            } else if model.hasStoredToken {
                Text(tr("setup.connect.token.stored")).font(.caption).foregroundStyle(WizardPalette.ink3)
            }
        }
    }

    private func pasteToken() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        if TokenFormat.looksLikeToken(text) {
            model.personalToken = text.trimmingCharacters(in: .whitespacesAndNewlines)
            pasteNote = tr("setup.signin.pasted")
        } else {
            pasteNote = tr("setup.signin.pasteEmpty")
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 12.5)).foregroundStyle(WizardPalette.ink2).lineSpacing(2)
    }
}
