public struct Summary: Equatable, Sendable {
    public let mine: [MineItem]
    public let review: [ReviewItem]
    /// The viewer's PRs waiting for a review. They are not counted in `total`: nothing is asked of the viewer.
    public let waiting: [WaitingItem]

    public init(mine: [MineItem], review: [ReviewItem], waiting: [WaitingItem] = []) {
        self.mine = mine
        self.review = review
        self.waiting = waiting
    }

    public var total: Int { mine.count + review.count }
}
