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

    private static let failureLock = NSLock()
    nonisolated(unsafe) private static var storedFailure: Error?

    static var failure: Error? {
        get { failureLock.withLock { storedFailure } }
        set { failureLock.withLock { storedFailure = newValue } }
    }

    override func startLoading() {
        if let failure = Self.failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
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

    @Test func cancelledRequestSurfacesAsCancellationNotANetworkError() async {
        StubURLProtocol.failure = URLError(.cancelled)
        defer { StubURLProtocol.failure = nil }

        await #expect(throws: CancellationError.self) {
            try await transport().send(query: "q", variables: [:])
        }
    }

    @Test func otherConnectionFailuresStillMapToNetwork() async {
        StubURLProtocol.failure = URLError(.notConnectedToInternet)
        defer { StubURLProtocol.failure = nil }

        await #expect(throws: GitHubError.self) {
            try await transport().send(query: "q", variables: [:])
        }
    }
}

extension URLSessionTransportTests {
    @Test func transportRecordsTheBudgetFromTheResponseHeaders() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let monitor = RateLimitMonitor()
        StubURLProtocol.handler = { _ in
            (200, ["X-RateLimit-Limit": "5000", "X-RateLimit-Remaining": "4321", "X-RateLimit-Reset": "1800000000"], Data("{\"data\":{}}".utf8))
        }
        let transport = URLSessionTransport(token: { "tok" }, session: URLSession(configuration: configuration), rateLimits: monitor)
        _ = try await transport.send(query: "query { viewer { login } }", variables: [:])

        #expect(monitor.latest == RateLimit(limit: 5000, remaining: 4321, resetsAt: Date(timeIntervalSince1970: 1_800_000_000)))
    }

    @Test func missingHeadersLeaveTheBudgetUnknown() async {
        #expect(RateLimit.parse { _ in nil } == nil)
        #expect(RateLimit.parse { $0 == "X-RateLimit-Limit" ? "5000" : nil } == nil)
    }
}

struct DiagnosticsReportTests {
    private func report(status: SyncStatus = .ok, lastSync: Date? = Date(timeIntervalSince1970: 1000), rate: RateLimit? = nil) -> DiagnosticsReport {
        DiagnosticsReport(
            appVersion: "0.3.0", systemVersion: "15.1", authSource: .personalToken, organizationCount: 2, refreshMinutes: 5,
            lastSync: lastSync, status: status, reviewCount: 4, mineCount: 3, rateLimit: rate, shortcutActive: true, automaticUpdates: false
        )
    }

    @Test func textHasWhatABugReportNeeds() {
        let rate = RateLimit(limit: 5000, remaining: 4900, resetsAt: Date(timeIntervalSince1970: 1000 + 1800))
        let text = report(rate: rate).text(now: Date(timeIntervalSince1970: 1000 + 120))

        #expect(text.contains("PRPulse 0.3.0"))
        #expect(text.contains("Sign in: personal token"))
        #expect(text.contains("Last sync: 2 min ago"))
        #expect(text.contains("Review: 4, mine: 3"))
        #expect(text.contains("Rate limit: 4900 of 5000 left, resets in 28 min"))
        #expect(text.contains("Global shortcut: active"))
        #expect(text.contains("Automatic updates: off"))
    }

    @Test func textNamesNeitherOrganizationsNorTokens() {
        let text = report().text(now: Date(timeIntervalSince1970: 2000))
        #expect(text.contains("Organizations: 2"))
        #expect(!text.lowercased().contains("token:"))
    }

    @Test func unknownPartsReadPlainly() {
        let text = report(status: .failed("HTTP 502"), lastSync: nil).text(now: Date())
        #expect(text.contains("Last sync: never"))
        #expect(text.contains("Status: failed (HTTP 502)"))
        #expect(text.contains("Rate limit: unknown"))
    }
}
