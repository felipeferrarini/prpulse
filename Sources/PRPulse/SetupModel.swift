import Foundation
import PRPulseCore
import SwiftUI

enum GhStatus: Equatable {
    case unknown, available, notInstalled, notLoggedIn
}

@MainActor
final class SetupModel: ObservableObject {
    enum Validation: Equatable {
        case idle, checking, failed(String), ok
    }

    enum RepositoryList: Equatable {
        case idle, loading, loaded([String]), failed
    }

    @Published var draft: AppSettings
    @Published var personalToken = ""
    @Published private(set) var organizations: [String] = []
    @Published private(set) var validation = Validation.idle
    @Published private(set) var ghStatus = GhStatus.unknown
    @Published private(set) var hasStoredToken = false
    @Published private(set) var repositories = RepositoryList.idle
    @Published private(set) var organizationActivity: [String: Int] = [:]
    @Published private(set) var login: String?

    let signIn = BrowserSignIn()

    private let tokens: TokenStore
    private let isSetup: Bool
    private var isPreview = false

    init(settings: AppSettings, isSetup: Bool = true, tokens: TokenStore = ClientFactory.tokenStore()) {
        draft = settings
        self.isSetup = isSetup
        self.tokens = tokens
        hasStoredToken = ((try? tokens.load()) ?? nil) != nil
        signIn.onSignedIn = { [weak self] method, token in try await self?.signedIn(method, token: token) }
    }

    /// The viewer approved a sign-in in the browser: use what it gave.
    private func signedIn(_ method: BrowserSignIn.Method, token: String?) async throws {
        switch method {
        case .gh:
            await checkGh()
            draft.authSource = .ghCli
        case .github:
            guard let token else { return }
            try tokens.save(token)
            hasStoredToken = true
            personalToken = ""
            draft.authSource = .personalToken
        }
        if case .failed = validation { validation = .idle }
    }

    func checkGh() async {
        do {
            _ = try await GhCliTokenProvider().token()
            ghStatus = .available
        } catch AuthError.ghNotInstalled {
            ghStatus = .notInstalled
        } catch {
            ghStatus = .notLoggedIn
        }
    }

    func validateConnection() async -> Bool {
        if isPreview {
            validation = .ok
            return true
        }
        validation = .checking
        let checker = ConnectionChecker(
            makeTransport: { provider in URLSessionTransport(token: { try await provider.token() }) },
            store: tokens
        )
        do {
            let info = try await checker.check(source: draft.authSource, typedToken: personalToken)
            if draft.authSource == .personalToken, !personalToken.isEmpty { personalToken = "" }
            hasStoredToken = ((try? tokens.load()) ?? nil) != nil
            organizations = info.organizations + [info.login]
            organizationActivity = info.recentPullRequests
            login = info.login
            return resolveOrganization()
        } catch {
            validation = .failed(Self.message(for: error))
            return false
        }
    }

    private func resolveOrganization() -> Bool {
        switch OrganizationChoice.resolve(current: draft.orgs, available: organizations, isSetup: isSetup) {
        case .keep:
            break
        case .pick(let orgs):
            draft.orgs = orgs
        case .choose:
            draft.orgs = []
        case .missing(let org):
            validation = .failed(tr("setup.error.orgMissing", org))
            return false
        }
        validation = .ok
        return true
    }

    func toggleOrganization(_ org: String) {
        if draft.orgs.contains(org) {
            draft.orgs.removeAll { $0 == org }
        } else {
            draft.orgs.append(org)
        }
    }

    /// Loads the repositories of every chosen organization, as `owner/name`.
    func loadRepositories() async {
        let owners = draft.orgs
        guard !isPreview, !owners.isEmpty else { return }
        repositories = .loading
        do {
            let provider = repositoryTokenProvider()
            let client = GitHubClient(transport: URLSessionTransport(token: { try await provider.token() }), clock: SystemClock())
            var names: [String] = []
            for owner in owners {
                names += try await client.repositories(owner: owner).map { "\(owner)/\($0)" }
            }
            guard owners == draft.orgs else { return }
            repositories = .loaded(names)
        } catch is CancellationError {
            return
        } catch {
            guard owners == draft.orgs else { return }
            repositories = .failed
        }
    }

    private func repositoryTokenProvider() -> TokenProvider {
        switch draft.authSource {
        case .ghCli: GhCliTokenProvider()
        case .personalToken:
            personalToken.isEmpty ? StoredTokenProvider(store: tokens) : FixedTokenProvider(personalToken)
        }
    }

    func reportFailure(_ message: String) {
        validation = .failed(message)
    }

    /// `owner/name` of every repository that could be loaded.
    var repositoryNames: [String] {
        if case .loaded(let names) = repositories { names } else { [] }
    }

    /// Just the names, for places that have room for nothing else.
    var repositoryShortNames: [String] {
        repositoryNames.map { $0.split(separator: "/", maxSplits: 1).last.map(String.init) ?? $0 }
    }

    func loadPreview(organizations: [String], gh: GhStatus, repositories: [String] = [], activity: [String: Int] = [:], login: String? = nil) {
        self.organizations = organizations
        self.login = login
        organizationActivity = activity
        ghStatus = gh
        self.repositories = .loaded(repositories.map { $0.contains("/") ? $0 : "\(draft.orgs.first ?? "acme")/\($0)" })
        isPreview = true
        validation = .ok
    }

    func isPersonal(_ org: String) -> Bool {
        org == organizations.last
    }

    static func message(for error: Error) -> String {
        switch error {
        case AuthError.ghNotInstalled: tr("setup.error.ghNotInstalled")
        case AuthError.ghNotLoggedIn: tr("setup.error.ghNotLoggedIn")
        case AuthError.tokenMissing: tr("setup.error.tokenMissing")
        case AuthError.tokenRejected: tr("setup.error.tokenRejected")
        case AuthError.missingRepoScope: tr("setup.error.missingScope")
        case AuthError.ghLoginFailed: tr("setup.signin.error.gh")
        case AuthError.signInDenied: tr("setup.signin.error.denied")
        case AuthError.signInExpired: tr("setup.signin.error.expired")
        case AuthError.signInUnavailable: tr("setup.signin.error.unavailable")
        case GitHubError.ssoRequired: tr("error.sso.body")
        case GitHubError.network: tr("setup.error.network")
        default: tr("setup.error.generic", error.localizedDescription)
        }
    }
}
