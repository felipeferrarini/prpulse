public struct ReviewItem: Equatable, Sendable {
    public let pr: PullRequestSnapshot
    public let isRequested: Bool

    public init(pr: PullRequestSnapshot, isRequested: Bool = false) {
        self.pr = pr
        self.isRequested = isRequested
    }
}
