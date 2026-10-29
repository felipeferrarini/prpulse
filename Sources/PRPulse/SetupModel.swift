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

    @Published var draft: AppSettings
    @Published var personalToken = ""
    @Published private(set) var organizations: [String] = []
    @Published private(set) var validation = Validation.idle
    @Published private(set) var ghStatus = GhStatus.unknown
    @Published private(set) var hasStoredToken = false

    private let tokens: TokenStore
    private let autoPickOrganization: Bool

    init(settings: AppSettings, autoPickOrganization: Bool = true, tokens: TokenStore = ClientFactory.tokenStore()) {
        draft = settings
        self.autoPickOrganization = autoPickOrganization
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
            return resolveOrganization(defaultChoice: info.organizations.first ?? info.login)
        } catch {
            validation = .failed(Self.message(for: error))
            return false
        }
    }

    private func resolveOrganization(defaultChoice: String) -> Bool {
        let choice = OrganizationChoice.resolve(
            current: draft.org, available: organizations, defaultChoice: defaultChoice, autoPick: autoPickOrganization
        )
        switch choice {
        case .keep:
            break
        case .pick(let org):
            draft.org = org
        case .missing(let org):
            validation = .failed(tr("setup.error.orgMissing", org))
            return false
        }
        validation = .ok
        return true
    }

    func reportFailure(_ message: String) {
        validation = .failed(message)
    }

    func loadPreview(organizations: [String], gh: GhStatus) {
        self.organizations = organizations
        ghStatus = gh
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
