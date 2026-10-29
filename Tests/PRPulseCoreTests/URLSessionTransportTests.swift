import Foundation
import Testing
@testable import PRPulseCore

final class StubURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) -> (status: Int, headers: [String: String], body: Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var stored: Handler?

    static var handler: Handler? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let result = Self.handler!(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: result.status, httpVersion: nil, headerFields: result.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: result.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct URLSessionTransportTests {
    private func transport() -> URLSessionTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSessionTransport(token: { "tok" }, session: URLSession(configuration: configuration))
    }

    @Test func postsQueryWithBearerToken() async throws {
        var seen: URLRequest?
        StubURLProtocol.handler = { request in
            seen = request
            return (200, [:], Data("{\"data\":{}}".utf8))
        }
        let data = try await transport().send(query: "query { viewer { login } }", variables: [:])

        #expect(String(data: data, encoding: .utf8) == "{\"data\":{}}")
        #expect(seen?.httpMethod == "POST")
        #expect(seen?.url?.absoluteString == "https://api.github.com/graphql")
        #expect(seen?.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
    }

    @Test func unauthorizedMapsTo401Error() async {
        StubURLProtocol.handler = { _ in (401, [:], Data("{}".utf8)) }
        await #expect(throws: GitHubError.unauthorized) {
            try await transport().send(query: "q", variables: [:])
        }
    }

    @Test func secondaryRateLimitMapsWithRetryAfter() async {
        StubURLProtocol.handler = { _ in (403, ["Retry-After": "30"], Data("{\"message\":\"You have exceeded a secondary rate limit\"}".utf8)) }
        await #expect(throws: GitHubError.rateLimited(retryAfter: 30)) {
            try await transport().send(query: "q", variables: [:])
        }
    }

    @Test func serverErrorMapsToNetwork() async {
        StubURLProtocol.handler = { _ in (502, [:], Data()) }
        await #expect(throws: GitHubError.network("HTTP 502")) {
            try await transport().send(query: "q", variables: [:])
        }
    }

    @Test func scopeProbeReadsTheOauthScopesHeader() async throws {
        var seen: URLRequest?
        StubURLProtocol.handler = { request in
            seen = request
            return (200, ["X-OAuth-Scopes": "repo, read:org"], Data("{}".utf8))
        }
        let scopes = try await transport().oauthScopes()

        #expect(scopes == ["repo", "read:org"])
        #expect(seen?.url?.absoluteString == "https://api.github.com/user")
        #expect(seen?.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
    }

    @Test func scopeProbeReturnsNilWithoutTheHeader() async throws {
        StubURLProtocol.handler = { _ in (200, [:], Data("{}".utf8)) }
        #expect(try await transport().oauthScopes() == nil)
    }

    @Test func scopeProbeMapsUnauthorized() async {
        StubURLProtocol.handler = { _ in (401, [:], Data("{}".utf8)) }
        await #expect(throws: GitHubError.unauthorized) {
            try await transport().oauthScopes()
        }
    }
}
