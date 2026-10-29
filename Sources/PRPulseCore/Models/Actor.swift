public struct Actor: Hashable, Sendable {
    public let login: String
    public let isBot: Bool

    public init(login: String, isBot: Bool) {
        self.login = login
        self.isBot = isBot
    }

    public static let ghost = Actor(login: "ghost", isBot: false)

    public func isSame(as other: String) -> Bool {
        login.caseInsensitiveCompare(other) == .orderedSame
    }
}
