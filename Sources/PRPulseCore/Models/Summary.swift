public struct Summary: Equatable, Sendable {
    public let mine: [MineItem]
    public let review: [ReviewItem]

    public init(mine: [MineItem], review: [ReviewItem]) {
        self.mine = mine
        self.review = review
    }

    public var total: Int { mine.count + review.count }
}
