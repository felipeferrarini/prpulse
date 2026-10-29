public struct ReviewItem: Equatable, Sendable {
    public let pr: PullRequestSnapshot

    public init(pr: PullRequestSnapshot) {
        self.pr = pr
    }
}
