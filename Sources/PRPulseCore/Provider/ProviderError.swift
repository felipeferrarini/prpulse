import Foundation

public enum ProviderError: Error, Equatable {
    case unauthorized
    case ssoRequired(org: String?)
    case rateLimited(retryAfter: TimeInterval?)
    case network(String)
    case malformed(String)
    case organizationNotAccessible(String)
}
