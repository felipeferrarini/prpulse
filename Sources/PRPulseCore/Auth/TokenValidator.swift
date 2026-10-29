public struct TokenValidator: Sendable {
    public init() {}

    public func validate(provider: TokenProvider, client: GitHubClient) async throws -> ViewerInfo {
        _ = try await provider.token()
        do {
            return try await client.viewer()
        } catch GitHubError.unauthorized {
            throw AuthError.tokenRejected
        }
    }
}
