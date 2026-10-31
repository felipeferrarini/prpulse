import Foundation

/// The OAuth App a team registers on GitHub so its people can sign in from the browser. Its client id is public: the device
/// flow needs no secret, so one person registers the app and everyone else only gets the id.
public enum OAuthApp {
    /// The key a company can set in the app's preferences (`defaults write` or a configuration profile) to fill the id in.
    public static let managedKey = "OAuthClientID"
    /// How to register the app.
    public static let guideURL = URL(string: "https://github.com/felipeferrarini/prpulse#sign-in-with-your-teams-oauth-app")!

    /// A client id is one word of letters, digits, dots and underscores, such as `Iv1.0123456789abcdef` or 20 hex digits.
    public static func isValid(_ id: String) -> Bool {
        let value = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return (10 ... 40).contains(value.count)
            && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_") }
    }

    /// The id to sign in with: what the viewer typed, else what the company configured. Empty when there is none.
    public static func resolve(typed: String, managed: String?) -> String {
        for candidate in [typed, managed ?? ""] {
            let value = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if isValid(value) { return value }
        }
        return ""
    }
}

/// GitHub's OAuth device flow: the app asks for a code, the viewer enters it at github.com/login/device, and the app trades
/// it for a token. See https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow.
public struct DeviceFlow: Sendable {
    public typealias Send = @Sendable (URLRequest) async throws -> Data
    public typealias Sleep = @Sendable (TimeInterval) async throws -> Void

    private let clientID: String
    private let scopes: [String]
    private let send: Send
    private let sleep: Sleep

    public init(
        clientID: String,
        scopes: [String] = ["repo", "read:org"],
        send: @escaping Send = Self.urlSession,
        sleep: @escaping Sleep = { try await Task.sleep(for: .seconds($0)) }
    ) {
        self.clientID = clientID
        self.scopes = scopes
        self.send = send
        self.sleep = sleep
    }

    /// Returns the token once the viewer has approved the sign-in. `onCode` gets the code to enter.
    public func signIn(onCode: @escaping @Sendable (DeviceCode) -> Void) async throws -> String {
        let start = try await request("https://github.com/login/device/code", ["client_id": clientID, "scope": scopes.joined(separator: " ")])
        guard let deviceCode = start["device_code"] as? String,
              let userCode = start["user_code"] as? String,
              let address = start["verification_uri"] as? String, let url = URL(string: address) else {
            throw start["error"] == nil ? AuthError.signInUnavailable : AuthError.signInClientRejected
        }
        onCode(DeviceCode(userCode: userCode, verificationURL: url))
        var interval = (start["interval"] as? Double) ?? 5
        let lifetime = (start["expires_in"] as? Double) ?? 900
        var waited = 0.0
        while waited < lifetime {
            try await sleep(interval)
            waited += interval
            let reply = try await request("https://github.com/login/oauth/access_token", [
                "client_id": clientID,
                "device_code": deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ])
            if let token = reply["access_token"] as? String, !token.isEmpty { return token }
            switch reply["error"] as? String {
            case "authorization_pending": continue
            case "slow_down": interval = (reply["interval"] as? Double) ?? interval + 5
            case "access_denied": throw AuthError.signInDenied
            case "expired_token": throw AuthError.signInExpired
            default: throw AuthError.signInUnavailable
            }
        }
        throw AuthError.signInExpired
    }

    private func request(_ address: String, _ form: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: address)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(form.sorted { $0.key < $1.key }.map { "\($0.key)=\(Self.escape($0.value))" }.joined(separator: "&").utf8)
        let data: Data
        do { data = try await send(request) } catch is CancellationError { throw CancellationError() } catch { throw AuthError.signInUnavailable }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AuthError.signInUnavailable }
        return object
    }

    private static func escape(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    @Sendable
    public static func urlSession(_ request: URLRequest) async throws -> Data {
        try await URLSession.shared.data(for: request).0
    }
}
