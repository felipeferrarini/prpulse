import Foundation
import Testing
@testable import PRPulseCore

private final class MemoryStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    init(_ token: String? = nil) { self.token = token }

    func save(_ token: String) throws { lock.withLock { self.token = token } }
    func load() throws -> String? { lock.withLock { token } }
    func delete() throws { lock.withLock { token = nil } }
}

private struct StaticProvider: TokenProvider {
    let value: String
    func token() async throws -> String { value }
}

private final class ScopedTransport: GraphQLTransport, ScopeProbing, @unchecked Sendable {
    private let provider: TokenProvider
    private let lock = NSLock()
    private var tokens: [String] = []
    let outcome: Result<Data, Error>
    let scopes: Set<String>?

    init(provider: TokenProvider, outcome: Result<Data, Error>, scopes: Set<String>?) {
        self.provider = provider
        self.outcome = outcome
        self.scopes = scopes
    }

    var seenTokens: [String] { lock.withLock { tokens } }

    func send(query: String, variables: [String: Any]) async throws -> Data {
        let token = try await provider.token()
        lock.withLock { tokens.append(token) }
        return try outcome.get()
    }

    func oauthScopes() async throws -> Set<String>? { scopes }
}

private func checker(
    store: MemoryStore,
    outcome: Result<Data, Error>? = nil,
    scopes: Set<String>? = ["repo", "read:org"],
    gh: TokenProvider = StaticProvider(value: "gh_token"),
    capture: ((ScopedTransport) -> Void)? = nil
) throws -> ConnectionChecker {
    let result = try outcome ?? .success(fixtureData("viewer"))
    return ConnectionChecker(
        makeTransport: { provider in
            let transport = ScopedTransport(provider: provider, outcome: result, scopes: scopes)
            capture?(transport)
            return transport
        },
        store: store,
        ghProvider: gh
    )
}

@Test func failedValidationDoesNotOverwriteTheStoredToken() async throws {
    let store = MemoryStore("good_token")
    let checker = try checker(store: store, outcome: .failure(GitHubError.unauthorized))

    await #expect(throws: AuthError.tokenRejected) {
        try await checker.check(source: .personalToken, typedToken: "typo_token")
    }
    #expect(try store.load() == "good_token")
}

@Test func successfulValidationStoresTheTypedTokenTrimmed() async throws {
    let store = MemoryStore()
    let info = try await checker(store: store).check(source: .personalToken, typedToken: "  ghp_ok \n")

    #expect(info.login == "me")
    #expect(try store.load() == "ghp_ok")
}

@Test func emptyTypedTokenValidatesTheStoredOneAndKeepsIt() async throws {
    let store = MemoryStore("stored_token")
    var transport: ScopedTransport?
    let checker = try checker(store: store, capture: { transport = $0 })

    _ = try await checker.check(source: .personalToken, typedToken: "   ")

    #expect(Set(transport?.seenTokens ?? []) == ["stored_token"])
    #expect(try store.load() == "stored_token")
}

@Test func ghSourceUsesTheGhTokenAndLeavesTheStoreAlone() async throws {
    let store = MemoryStore("stored_token")
    var transport: ScopedTransport?
    let checker = try checker(store: store, capture: { transport = $0 })

    _ = try await checker.check(source: .ghCli, typedToken: "ignored_typed_token")

    #expect(Set(transport?.seenTokens ?? []) == ["gh_token"])
    #expect(try store.load() == "stored_token")
}

@Test func missingRepoScopeIsRejectedAndNothingIsStored() async throws {
    let store = MemoryStore()
    let checker = try checker(store: store, scopes: ["read:org"])

    await #expect(throws: AuthError.missingRepoScope) {
        try await checker.check(source: .personalToken, typedToken: "ghp_readonly")
    }
    #expect(try store.load() == nil)
}

@Test func emptyScopeListIsRejected() async throws {
    let checker = try checker(store: MemoryStore(), scopes: [])

    await #expect(throws: AuthError.missingRepoScope) {
        try await checker.check(source: .personalToken, typedToken: "ghp_none")
    }
}

@Test func tokenWithoutScopeHeaderIsAccepted() async throws {
    let store = MemoryStore()
    _ = try await checker(store: store, scopes: nil).check(source: .personalToken, typedToken: "github_pat_fine_grained")
    #expect(try store.load() == "github_pat_fine_grained")
}

@Test func organizationsComeBackRankedByActivity() async throws {
    let body = json(["data": [
        "viewer": ["login": "me", "organizations": ["nodes": [["login": "acme"], ["login": "other-org"]]]],
        "o0": ["issueCount": 1, "nodes": []],
        "o1": ["issueCount": 9, "nodes": []],
    ]])
    let info = try await checker(store: MemoryStore(), outcome: .success(body)).check(source: .ghCli, typedToken: nil)

    #expect(info.organizations == ["other-org", "acme"])
    #expect(info.recentPullRequests == ["acme": 1, "other-org": 9])
}

@Test func organizationsFallBackToAlphabeticalWhenRankingIsUnavailable() async throws {
    let body = json(["data": ["viewer": ["login": "me", "organizations": ["nodes": [["login": "zeta"], ["login": "alpha"]]]]]])
    let info = try await checker(store: MemoryStore(), outcome: .success(body)).check(source: .ghCli, typedToken: nil)

    #expect(info.organizations == ["alpha", "zeta"])
    #expect(info.recentPullRequests == ["alpha": 0, "zeta": 0])
}
