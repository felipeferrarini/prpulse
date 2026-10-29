public struct PendingKey: Hashable, Codable, Sendable {
    public static let needsReview = "needsReview"

    public let ref: PullRequestRef
    public let reason: String

    public init(ref: PullRequestRef, reason: String) {
        self.ref = ref
        self.reason = reason
    }
}

extension Summary {
    public var pendingKeys: Set<PendingKey> {
        let fromMine = mine.flatMap { item in
            item.reasons.map { PendingKey(ref: item.pr.ref, reason: $0.kind) }
        }
        let fromReview = review.map { PendingKey(ref: $0.pr.ref, reason: PendingKey.needsReview) }
        return Set(fromMine + fromReview)
    }
}
