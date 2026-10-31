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

    /// The one place that builds the client of the forge in use, which today is always GitHub.
    static func provider(token tokenProvider: TokenProvider, rateLimits: RateLimitMonitor? = nil) -> any PullRequestProvider {
        let transport = URLSessionTransport(token: { try await tokenProvider.token() }, rateLimits: rateLimits)
        return GitHubClient(transport: transport, clock: SystemClock())
    }

    static func makeProviderFactory(settings: SettingsStore) -> @Sendable () async throws -> any PullRequestProvider {
        {
            provider(token: tokenProvider(for: settings.settings.authSource), rateLimits: rateLimits)
        }
    }
}
