import Foundation

public enum GitHubError: Error, Equatable {
    case unauthorized
    case ssoRequired(org: String?)
    case rateLimited(retryAfter: TimeInterval?)
    case network(String)
    case malformed(String)
    case organizationNotAccessible(String)
}
