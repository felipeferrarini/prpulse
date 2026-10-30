import Foundation

public protocol GraphQLTransport: Sendable {
    func send(query: String, variables: [String: Any]) async throws -> Data
}

public protocol ScopeProbing: Sendable {
    func oauthScopes() async throws -> Set<String>?
}

public struct URLSessionTransport: GraphQLTransport, ScopeProbing {
    private static let endpoint = URL(string: "https://api.github.com/graphql")!
    private static let userEndpoint = URL(string: "https://api.github.com/user")!

    private let token: @Sendable () async throws -> String
    private let session: URLSession
    private let rateLimits: RateLimitMonitor?

    public init(
        token: @escaping @Sendable () async throws -> String,
        session: URLSession = .shared,
        rateLimits: RateLimitMonitor? = nil
    ) {
        self.token = token
        self.session = session
        self.rateLimits = rateLimits
    }

    public func send(query: String, variables: [String: Any]) async throws -> Data {
        let request = try await makeRequest(query: query, variables: variables)
        let (data, response) = try await load(request)
        return try validate(data, response)
    }

    public func oauthScopes() async throws -> Set<String>? {
        let request = try await authorizedRequest(Self.userEndpoint)
        let (data, response) = try await load(request)
        _ = try validate(data, response)
        guard let header = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-OAuth-Scopes") else { return nil }
        let scopes = header.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return Set(scopes)
    }

    private func authorizedRequest(_ url: URL) async throws -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        request.setValue("PRPulse", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func makeRequest(query: String, variables: [String: Any]) async throws -> URLRequest {
        var request = try await authorizedRequest(Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        return request
    }

    private func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw GitHubError.network(error.localizedDescription)
        }
    }

    private func validate(_ data: Data, _ response: URLResponse) throws -> Data {
        guard let http = response as? HTTPURLResponse else { throw GitHubError.network("invalid response") }
        if let rateLimit = RateLimit.parse({ http.value(forHTTPHeaderField: $0) }) { rateLimits?.record(rateLimit) }
        switch http.statusCode {
        case 200..<300: return data
        case 401: throw GitHubError.unauthorized
        case 403, 429: throw forbiddenError(http, body: data)
        default: throw GitHubError.network("HTTP \(http.statusCode)")
        }
    }

    private func forbiddenError(_ http: HTTPURLResponse, body: Data) -> GitHubError {
        let text = String(data: body, encoding: .utf8)?.lowercased() ?? ""
        let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
        if retryAfter != nil || text.contains("rate limit") { return .rateLimited(retryAfter: retryAfter) }
        if http.value(forHTTPHeaderField: "X-GitHub-SSO") != nil { return .ssoRequired(org: nil) }
        return .network("HTTP \(http.statusCode)")
    }
}
