public struct Summary: Equatable, Sendable {
    /// Every pull request the viewer has open, the most urgent first. Only the ones with reasons ask something of the viewer.
    public let mine: [MineItem]
    public let review: [ReviewItem]

    public init(mine: [MineItem], review: [ReviewItem]) {
        self.mine = mine
        self.review = review
    }

    /// What asks something of the viewer: the number on the icon. Pull requests that wait on someone else are not in it.
    public var total: Int { mine.filter(\.needsAction).count + review.count }
}
