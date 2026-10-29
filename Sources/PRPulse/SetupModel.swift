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

    private let tokens: TokenStore
    private let isSetup: Bool
    private var isPreview = false

    init(settings: AppSettings, isSetup: Bool = true, tokens: TokenStore = ClientFactory.tokenStore()) {
        draft = settings
        self.isSetup = isSetup
        self.tokens = tokens
        hasStoredToken = ((try? tokens.load()) ?? nil) != nil
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
            return resolveOrganization()
        } catch {
            validation = .failed(Self.message(for: error))
            return false
        }
    }

    private func resolveOrganization() -> Bool {
        switch OrganizationChoice.resolve(current: draft.org, available: organizations, isSetup: isSetup) {
        case .keep:
            break
        case .pick(let org):
            draft.org = org
        case .choose:
            draft.org = ""
        case .missing(let org):
            validation = .failed(tr("setup.error.orgMissing", org))
            return false
        }
        validation = .ok
        return true
    }

    func loadRepositories() async {
        let owner = draft.org
        guard !isPreview, !owner.isEmpty else { return }
        repositories = .loading
        do {
            let provider = repositoryTokenProvider()
            let client = GitHubClient(transport: URLSessionTransport(token: { try await provider.token() }), clock: SystemClock())
            let names = try await client.repositories(owner: owner)
            guard owner == draft.org else { return }
            repositories = .loaded(names)
        } catch is CancellationError {
            return
        } catch {
            guard owner == draft.org else { return }
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

    func loadPreview(organizations: [String], gh: GhStatus, repositories: [String] = []) {
        self.organizations = organizations
        ghStatus = gh
        self.repositories = .loaded(repositories)
        isPreview = true
    }

    func isPersonal(_ org: String) -> Bool {
        org == organizations.last
    }

    private static func message(for error: Error) -> String {
        switch error {
        case AuthError.ghNotInstalled: tr("setup.error.ghNotInstalled")
        case AuthError.ghNotLoggedIn: tr("setup.error.ghNotLoggedIn")
        case AuthError.tokenMissing: tr("setup.error.tokenMissing")
        case AuthError.tokenRejected: tr("setup.error.tokenRejected")
        case AuthError.missingRepoScope: tr("setup.error.missingScope")
        case GitHubError.ssoRequired: tr("error.sso.body")
        case GitHubError.network: tr("setup.error.network")
        default: tr("setup.error.generic", error.localizedDescription)
        }
    }
}
