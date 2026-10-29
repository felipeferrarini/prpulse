import Foundation

public struct FixedTokenProvider: TokenProvider {
    private let value: String

    public init(_ value: String) {
        self.value = value
    }

    public func token() async throws -> String { value }
}

public struct ConnectionChecker: Sendable {
    private let makeTransport: @Sendable (TokenProvider) -> GraphQLTransport
    private let store: TokenStore
    private let ghProvider: TokenProvider
    private let clock: Clock

    public init(
        makeTransport: @escaping @Sendable (TokenProvider) -> GraphQLTransport,
        store: TokenStore,
        ghProvider: TokenProvider = GhCliTokenProvider(),
        clock: Clock = SystemClock()
    ) {
        self.makeTransport = makeTransport
        self.store = store
        self.ghProvider = ghProvider
        self.clock = clock
    }

    public func check(source: AuthSource, typedToken: String?) async throws -> ViewerInfo {
        let typed = typedToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let provider = provider(for: source, typed: typed)
        let transport = makeTransport(provider)
        let client = GitHubClient(transport: transport, clock: clock)

        let info = try await TokenValidator().validate(provider: provider, client: client)
        try await requireRepoScope(transport)
        if source == .personalToken, !typed.isEmpty { try store.save(typed) }
        return info
    }

    private func provider(for source: AuthSource, typed: String) -> TokenProvider {
        switch source {
        case .ghCli: ghProvider
        case .personalToken: typed.isEmpty ? StoredTokenProvider(store: store) : FixedTokenProvider(typed)
        }
    }

    private func requireRepoScope(_ transport: GraphQLTransport) async throws {
        guard let probe = transport as? ScopeProbing, let scopes = try await probe.oauthScopes() else { return }
        guard scopes.contains("repo") else { throw AuthError.missingRepoScope }
    }
}
