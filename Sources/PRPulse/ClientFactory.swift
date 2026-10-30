import Foundation
import PRPulseCore

enum ClientFactory {
    static let keychainService = Bundle.main.bundleIdentifier ?? "io.github.felipeferrarini.prpulse"

    static func tokenStore() -> TokenStore {
        KeychainTokenStore(service: keychainService)
    }

    static func tokenProvider(for source: AuthSource) -> TokenProvider {
        switch source {
        case .ghCli: GhCliTokenProvider()
        case .personalToken: StoredTokenProvider(store: tokenStore())
        }
    }

    /// Shared by every client the app builds, so the settings can show the latest budget.
    static let rateLimits = RateLimitMonitor()

    static func makeClientFactory(settings: SettingsStore) -> @Sendable () async throws -> GitHubClient {
        {
            let provider = tokenProvider(for: settings.settings.authSource)
            let transport = URLSessionTransport(token: { try await provider.token() }, rateLimits: rateLimits)
            return GitHubClient(transport: transport, clock: SystemClock())
        }
    }
}
