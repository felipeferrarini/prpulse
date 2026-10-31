import Foundation

/// What the viewer types at github.com/login/device to approve a sign-in that was started in the app.
public struct DeviceCode: Equatable, Sendable {
    public let userCode: String
    public let verificationURL: URL

    public init(userCode: String, verificationURL: URL) {
        self.userCode = userCode
        self.verificationURL = verificationURL
    }
}
