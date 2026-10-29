public struct NotificationPlan: Equatable, Sendable {
    public let toNotify: [PendingKey]
    public let notified: Set<PendingKey>
}

public enum NotificationPlanner {
    public static func plan(current: Set<PendingKey>, notified: Set<PendingKey>) -> NotificationPlan {
        NotificationPlan(toNotify: current.subtracting(notified).sorted(by: order), notified: current)
    }

    public static func seed(current: Set<PendingKey>) -> Set<PendingKey> {
        current
    }

    private static func order(_ a: PendingKey, _ b: PendingKey) -> Bool {
        if a.ref.repo != b.ref.repo { return a.ref.repo < b.ref.repo }
        if a.ref.number != b.ref.number { return a.ref.number < b.ref.number }
        return a.reason < b.reason
    }
}
