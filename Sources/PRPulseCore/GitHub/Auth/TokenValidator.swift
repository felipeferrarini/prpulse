public struct TokenValidator: Sendable {
    public init() {}

    public func validate(provider: TokenProvider, client: any PullRequestProvider) async throws -> ViewerInfo {
        _ = try await provider.token()
        do {
            return try await client.viewer()
        } catch ProviderError.unauthorized {
            throw AuthError.tokenRejected
        }
    }
}
