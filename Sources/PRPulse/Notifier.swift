import AppKit
import PRPulseCore
import UserNotifications

final class Notifier: NSObject, NotificationSink, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private static let urlKey = "url"
    private static let maxLines = 3

    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    /// Called when a notification about a review is opened.
    /// Called when a notification that opens a pull request is clicked.
    var onOpenPullRequest: (@MainActor (URL) -> Void)?

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

    /// The author nudged the viewer. The sound and the mascot are the app's own; this is the banner.
    func deliver(nudge: IncomingNudge) async {
        let sender = nudge.nudge.author.login
        await post(nudge, title: nudge.nudge.kind == .merge ? tr("nudge.merge.notification.title", sender) : tr("nudge.notification.title", sender))
    }

    /// The nudge was not looked at for a while.
    func remind(_ nudge: IncomingNudge) async {
        let sender = nudge.nudge.author.login
        await post(nudge, title: nudge.nudge.kind == .merge ? tr("nudge.merge.reminder.title", sender) : tr("nudge.reminder.title", sender))
    }

    private func post(_ nudge: IncomingNudge, title: String) async {
        guard let center, await isAuthorized(center) else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        let line = "\(nudge.ref.shortName) \(nudge.title)"
        content.body = nudge.nudge.message.map { "\(line)\n\($0)" } ?? line
        content.userInfo = [Self.urlKey: nudge.url.absoluteString]
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let text = response.notification.request.content.userInfo[Self.urlKey] as? String,
              let url = URL(string: text) else { return }
        await MainActor.run {
            onOpenPullRequest?(url)
            _ = NSWorkspace.shared.open(url)
        }
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
