public enum AuthError: Error, Equatable {
    case ghNotInstalled
    case ghNotLoggedIn
    case tokenMissing
    case tokenRejected
    case missingRepoScope
    /// `gh auth login` ended without a login.
    case ghLoginFailed
    /// The viewer turned the sign-in down in the browser.
    case signInDenied
    /// The code was not entered before it expired.
    case signInExpired
    /// GitHub could not be reached, or does not allow this kind of sign-in.
    case signInUnavailable
}

public protocol TokenProvider: Sendable {
    func token() async throws -> String
}

public protocol TokenStore: Sendable {
    func save(_ token: String) throws
    func load() throws -> String?
    func delete() throws
}

public struct StoredTokenProvider: TokenProvider {
    private let store: TokenStore

    public init(store: TokenStore) {
        self.store = store
    }

    public func token() async throws -> String {
        guard let token = try store.load(), !token.isEmpty else { throw AuthError.tokenMissing }
        return token
    }
}
