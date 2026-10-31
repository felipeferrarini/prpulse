import Foundation
import Testing
@testable import PRPulseCore

private final class Collected<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Value] = []
    func add(_ value: Value) { lock.withLock { values.append(value) } }
    var all: [Value] { lock.withLock { values } }
}

private struct FakeLoginProcess: LoginProcess {
    let output: [String]
    let status: Int32
    let ended: Collected<Bool>

    var lines: AsyncStream<String> {
        AsyncStream { continuation in
            output.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }

    func waitUntilExit() async -> Int32 { status }
    func terminate() { ended.add(true) }
}

private func login(_ output: [String], status: Int32 = 0, installed: Bool = true) -> GhLogin {
    GhLogin(
        candidatePaths: ["/fake/gh"],
        fileExists: { _ in installed },
        launch: { _, _ in FakeLoginProcess(output: output, status: status, ended: Collected()) }
    )
}

private let ghOutput = [
    "",
    "! First copy your one-time code: 2CAB-334F",
    "Open this URL to continue in your web browser: https://github.com/login/device",
]

@Test func ghLoginHandsOverTheCodeAndFinishesWhenTheCliDoes() async throws {
    let codes = Collected<DeviceCode>()
    try await login(ghOutput).signIn { codes.add($0) }
    #expect(codes.all == [DeviceCode(userCode: "2CAB-334F", verificationURL: GhLogin.verificationURL)])
}

@Test func ghLoginFailsWhenTheCliExitsWithAnError() async {
    await #expect(throws: AuthError.ghLoginFailed) {
        try await login(ghOutput, status: 1).signIn { _ in }
    }
}

@Test func ghLoginNeedsTheCli() async {
    await #expect(throws: AuthError.ghNotInstalled) {
        try await login(ghOutput, installed: false).signIn { _ in }
    }
}

@Test func ghLoginReadsTheCodeOnlyFromTheCodeLine() {
    #expect(GhLogin.code(in: "! First copy your one-time code: 2CAB-334F") == "2CAB-334F")
    #expect(GhLogin.code(in: "Open this URL to continue in your web browser: https://github.com/login/device") == nil)
}

// MARK: - Device flow

private final class Script: @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [String]
    private(set) var requests: [URLRequest] = []
    private(set) var waits: [TimeInterval] = []

    init(_ replies: [String]) { self.replies = replies }

    func send(_ request: URLRequest) -> Data {
        lock.withLock {
            requests.append(request)
            return Data(replies.removeFirst().utf8)
        }
    }

    func sleep(_ seconds: TimeInterval) { lock.withLock { waits.append(seconds) } }
}

private let started = #"{"device_code":"dc","user_code":"WDJB-MJHT","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}"#

private func flow(_ script: Script) -> DeviceFlow {
    DeviceFlow(clientID: "abc", send: { script.send($0) }, sleep: { script.sleep($0) })
}

@Test func deviceFlowWaitsForTheViewerAndReturnsTheToken() async throws {
    let script = Script([started, #"{"error":"authorization_pending"}"#, #"{"access_token":"gho_x","token_type":"bearer"}"#])
    let codes = Collected<DeviceCode>()
    let token = try await flow(script).signIn { codes.add($0) }
    #expect(token == "gho_x")
    #expect(codes.all.first?.userCode == "WDJB-MJHT")
    #expect(script.waits == [5, 5])
    let body = String(decoding: script.requests[0].httpBody ?? Data(), as: UTF8.self)
    #expect(body == "client_id=abc&scope=repo%20read%3Aorg")
    #expect(String(decoding: script.requests[2].httpBody ?? Data(), as: UTF8.self).contains("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code"))
}

@Test func deviceFlowSlowsDownWhenAsked() async throws {
    let script = Script([started, #"{"error":"slow_down","interval":10}"#, #"{"access_token":"t"}"#])
    _ = try await flow(script).signIn { _ in }
    #expect(script.waits == [5, 10])
}

@Test func deviceFlowReportsDenialAndExpiry() async {
    await #expect(throws: AuthError.signInDenied) {
        try await flow(Script([started, #"{"error":"access_denied"}"#])).signIn { _ in }
    }
    await #expect(throws: AuthError.signInExpired) {
        try await flow(Script([started, #"{"error":"expired_token"}"#])).signIn { _ in }
    }
}

@Test func deviceFlowGivesUpWhenTheCodeRunsOut() async {
    let short = #"{"device_code":"dc","user_code":"AAAA-BBBB","verification_uri":"https://github.com/login/device","expires_in":10,"interval":5}"#
    let pending = #"{"error":"authorization_pending"}"#
    await #expect(throws: AuthError.signInExpired) {
        try await flow(Script([short, pending, pending, pending])).signIn { _ in }
    }
}

@Test func deviceFlowIsUnavailableWhenGitHubRefuses() async {
    await #expect(throws: AuthError.signInUnavailable) {
        try await flow(Script([#"{"error":"device_flow_disabled"}"#])).signIn { _ in }
    }
}

// MARK: - Token format

@Test func pastedTextIsTakenForATokenOnlyWhenItLooksLikeOne() {
    #expect(TokenFormat.looksLikeToken("ghp_abcdefghijklmnopqrstuvwxyz0123456789\n"))
    #expect(TokenFormat.looksLikeToken("github_pat_11ABCDEFG0abcdefghijklmnop_qrstuvwxyz"))
    #expect(!TokenFormat.looksLikeToken("ghp_short"))
    #expect(!TokenFormat.looksLikeToken("hello world, this is not a token at all"))
    #expect(!TokenFormat.looksLikeToken("ghp_abcdefghijklmnop qrstuvwxyz"))
}
