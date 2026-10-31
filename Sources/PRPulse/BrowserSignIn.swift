import AppKit
import PRPulseCore

/// A sign-in that is approved in the browser: the app shows a code, opens GitHub, and waits.
@MainActor
final class BrowserSignIn: ObservableObject {
    enum Method: Equatable {
        /// `gh auth login --web`: the CLI keeps the token.
        case gh
        /// The OAuth app's device flow: the app keeps the token, in the Keychain.
        case github
    }

    enum State: Equatable {
        case idle
        case starting(Method)
        case waiting(Method, DeviceCode)
        case done(Method)
        case failed(String)
    }

    @Published private(set) var state = State.idle

    /// Called when GitHub approved the sign-in; the token is there for the browser sign-in only.
    var onSignedIn: (Method, String?) async throws -> Void = { _, _ in }

    private var task: Task<Void, Never>?

    deinit { task?.cancel() }

    var isBusy: Bool {
        switch state {
        case .starting, .waiting: true
        default: false
        }
    }

    /// The browser sign-in needs the OAuth app, which is left out until it is registered.
    static var isGitHubAppAvailable: Bool { !OAuthApp.clientID.isEmpty }

    func start(_ method: Method) {
        guard !isBusy else { return }
        state = .starting(method)
        task = Task { [weak self] in
            do {
                let token = try await Self.run(method) { code in
                    Task { @MainActor in self?.show(code, for: method) }
                }
                try await self?.onSignedIn(method, token)
                self?.state = .done(method)
            } catch is CancellationError {
                self?.state = .idle
            } catch {
                self?.state = .failed(SetupModel.message(for: error))
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        state = .idle
    }

    func open(_ code: DeviceCode) {
        NSWorkspace.shared.open(code.verificationURL)
    }

    func copy(_ code: DeviceCode) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code.userCode, forType: .string)
    }

    private func show(_ code: DeviceCode, for method: Method) {
        guard isBusy else { return }
        state = .waiting(method, code)
        copy(code)
        open(code)
    }

    private static func run(_ method: Method, onCode: @escaping @Sendable (DeviceCode) -> Void) async throws -> String? {
        switch method {
        case .gh:
            try await GhLogin().signIn(onCode: onCode)
            return nil
        case .github:
            return try await DeviceFlow(clientID: OAuthApp.clientID).signIn(onCode: onCode)
        }
    }
}
