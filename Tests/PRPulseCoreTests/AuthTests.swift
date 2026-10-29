import Foundation
import Testing
@testable import PRPulseCore

private final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    var stored: String?

    func save(_ token: String) throws { stored = token }
    func load() throws -> String? { stored }
    func delete() throws { stored = nil }
}

private struct FailingProvider: TokenProvider {
    let error: AuthError
    func token() async throws -> String { throw error }
}

private struct FixedProvider: TokenProvider {
    func token() async throws -> String { "token" }
}

private func ghProvider(exists: Bool = true, status: Int32 = 0, output: String = "") -> GhCliTokenProvider {
    GhCliTokenProvider(
        candidatePaths: ["/opt/homebrew/bin/gh"],
        fileExists: { _ in exists },
        run: { _, _ in (status, output) }
    )
}

@Test func ghProviderTrimsOutput() async throws {
    #expect(try await ghProvider(output: "  gho_abc123\n").token() == "gho_abc123")
}

@Test func ghProviderThrowsNotInstalledWhenNoBinary() async {
    await #expect(throws: AuthError.ghNotInstalled) {
        try await ghProvider(exists: false).token()
    }
}

@Test func ghProviderThrowsNotLoggedInOnNonZeroExit() async {
    await #expect(throws: AuthError.ghNotLoggedIn) {
        try await ghProvider(status: 1, output: "").token()
    }
}

@Test func ghProviderThrowsNotLoggedInOnEmptyOutput() async {
    await #expect(throws: AuthError.ghNotLoggedIn) {
        try await ghProvider(output: "  \n").token()
    }
}

@Test func ghProviderRunsARealProcess() async throws {
    let provider = GhCliTokenProvider(candidatePaths: ["/bin/echo"])
    #expect(try await provider.token() == "auth token")
}

@Test func storedProviderThrowsWhenEmptyAndReturnsWhenSaved() async throws {
    let store = InMemoryTokenStore()
    await #expect(throws: AuthError.tokenMissing) {
        try await StoredTokenProvider(store: store).token()
    }
    try store.save("ghp_saved")
    #expect(try await StoredTokenProvider(store: store).token() == "ghp_saved")
}

@Test func validatorReturnsViewerInfo() async throws {
    let transport = FakeTransport { _, _ in try fixtureData("viewer") }
    let client = GitHubClient(transport: transport, clock: SystemClock())

    let info = try await TokenValidator().validate(provider: FixedProvider(), client: client)
    #expect(info == ViewerInfo(login: "me", organizations: ["acme", "other-org"]))
}

@Test func validatorMapsUnauthorizedToTokenRejected() async {
    let transport = FakeTransport { _, _ in throw GitHubError.unauthorized }
    let client = GitHubClient(transport: transport, clock: SystemClock())

    await #expect(throws: AuthError.tokenRejected) {
        try await TokenValidator().validate(provider: FixedProvider(), client: client)
    }
}

@Test func validatorSurfacesProviderErrorsWithoutCallingGithub() async {
    let transport = FakeTransport { _, _ in try fixtureData("viewer") }
    let client = GitHubClient(transport: transport, clock: SystemClock())

    await #expect(throws: AuthError.ghNotLoggedIn) {
        try await TokenValidator().validate(provider: FailingProvider(error: .ghNotLoggedIn), client: client)
    }
    #expect(transport.calls.isEmpty)
}

@Test func validatorKeepsSsoErrorsDistinct() async {
    let transport = FakeTransport { _, _ in try fixtureData("saml-error") }
    let client = GitHubClient(transport: transport, clock: SystemClock())

    await #expect(throws: GitHubError.ssoRequired(org: nil)) {
        try await TokenValidator().validate(provider: FixedProvider(), client: client)
    }
}

@Test func keychainRoundTrip() throws {
    let store = KeychainTokenStore(service: "prpulse-test-\(UUID().uuidString)", account: "github-token")
    defer { try? store.delete() }

    #expect(try store.load() == nil)
    try store.save("ghp_first")
    #expect(try store.load() == "ghp_first")
    try store.save("ghp_second")
    #expect(try store.load() == "ghp_second")
    try store.delete()
    #expect(try store.load() == nil)
}
