public struct PullRequestRef: Hashable, Codable, Sendable {
    public let owner: String
    public let repo: String
    public let number: Int

    public init(owner: String, repo: String, number: Int) {
        self.owner = owner
        self.repo = repo
        self.number = number
    }

    public var shortName: String { "\(repo)#\(number)" }
}
