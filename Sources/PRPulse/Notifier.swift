import AppKit
import PRPulseCore
import UserNotifications

final class Notifier: NSObject, NotificationSink, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private static let urlKey = "url"
    private static let maxLines = 3

    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    func activate() {
        center?.delegate = self
    }

    func deliver(_ items: [PendingKey], summary: Summary) async {
        guard let center, await isAuthorized(center) else { return }
        let pullRequests = uniquePullRequests(items, in: summary)
        let content = UNMutableNotificationContent()
        content.title = pullRequests.count == 1
            ? tr("notification.title.one")
            : tr("notification.title.other", pullRequests.count)
        content.body = pullRequests.prefix(Self.maxLines).map { "\($0.ref.shortName) \($0.title)" }.joined(separator: "\n")
        if pullRequests.count == 1 { content.userInfo = [Self.urlKey: pullRequests[0].url.absoluteString] }
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let text = response.notification.request.content.userInfo[Self.urlKey] as? String,
              let url = URL(string: text) else { return }
        await MainActor.run { _ = NSWorkspace.shared.open(url) }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    private func isAuthorized(_ center: UNUserNotificationCenter) async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    private func uniquePullRequests(_ items: [PendingKey], in summary: Summary) -> [PullRequestSnapshot] {
        let wanted = Set(items.map(\.ref))
        let all = summary.mine.map(\.pr) + summary.review.map(\.pr)
        var seen = Set<PullRequestRef>()
        return all.filter { wanted.contains($0.ref) && seen.insert($0.ref).inserted }
    }
}
