/// One of the viewer's own pull requests that has no review yet. It asks nothing of the viewer; it is someone else's turn.
public struct WaitingItem: Equatable, Sendable {
    public let pr: PullRequestSnapshot

    public init(pr: PullRequestSnapshot) {
        self.pr = pr
    }
}
