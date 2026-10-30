import Foundation
import PRPulseCore

enum DemoMode: String {
    case pending, fresh, error, empty, unconfigured, many

    static var current: DemoMode? {
        guard let value = ProcessInfo.processInfo.environment["PRPULSE_DEMO"] else { return nil }
        return DemoMode(rawValue: value) ?? .pending
    }

    var viewData: ViewData {
        let now = Date()
        switch self {
        case .pending: return ViewData(state: .ready(DemoData.summary), summary: DemoData.summary, lastUpdated: now, orgs: ["acme"])
        case .fresh: return ViewData(state: .ready(DemoData.summary), summary: DemoData.summary, lastUpdated: now, freshUntil: now.addingTimeInterval(3600), orgs: ["acme"])
        case .empty:
            let empty = Summary(mine: [], review: [])
            return ViewData(state: .ready(empty), summary: empty, lastUpdated: now, orgs: ["acme"])
        case .many: return ViewData(state: .ready(DemoData.crowded), summary: DemoData.crowded, lastUpdated: now, orgs: ["acme"])
        case .error: return ViewData(state: .failed(.unauthenticated), summary: nil, lastUpdated: nil)
        case .unconfigured: return ViewData(state: .idle, summary: nil, lastUpdated: nil, isSetupComplete: false)
        }
    }
}

enum DemoData {
    static let summary = Summary(
        mine: [
            item(405, "web", "Rotate the refresh token", hoursAgo: 52, reasons: [.changesRequested, .openThreads(3)]),
            item(199, "api", "Retry with exponential backoff", hoursAgo: 30, reasons: [.unansweredComment]),
            item(201, "api", "Partial index on invoices", hoursAgo: 18, reasons: [.ciFailed]),
            item(398, "web", "Remove the legacy-checkout flag", hoursAgo: 90, reasons: [.conflict, .ciFailed]),
            item(51, "infra", "Update the runner base image", hoursAgo: 9, reasons: [.readyToMerge]),
            item(377, "web", "Adjust the filter tooltip", hoursAgo: 200, reasons: [.readyToMerge]),
        ],
        review: [
            review(412, "web", "Per-tenant session cache", author: "sam", hoursAgo: 76, requested: true),
            review(208, "api", "Fix pagination on /invoices", author: "mia", hoursAgo: 7, requested: true),
            review(133, "mobile", "Offline upload queue", author: "ivan", hoursAgo: 121),
            review(419, "web", "Swap the date library for Temporal", author: "leo", hoursAgo: 27),
            review(77, "docs", "Onboarding guide v2", author: "noor", hoursAgo: 4, draft: true),
        ],
        waiting: [
            waiting(402, "api", "Cache the exchange rates", hoursAgo: 134, reviewers: ["mia", "sam"]),
            waiting(407, "web", "Lazy load the settings page", hoursAgo: 71, reviewers: []),
        ]
    )

    /// Ninety pull requests, to see how the panel behaves with a long list.
    static let crowded = Summary(
        mine: (0 ..< 40).map { index in
            item(1000 + index, "api", "Change number \(index)", hoursAgo: Double(index) * 3 + 2, reasons: [[.ciFailed, .conflict, .readyToMerge, .unansweredComment][index % 4]])
        },
        review: (0 ..< 45).map { index in
            review(2000 + index, "web", "Review number \(index)", author: ["sam", "mia", "ivan", "leo"][index % 4], hoursAgo: Double(index) * 2 + 1, requested: index % 5 == 0)
        },
        waiting: (0 ..< 5).map { index in
            waiting(3000 + index, "infra", "Waiting number \(index)", hoursAgo: Double(index) * 20 + 60, reviewers: index % 2 == 0 ? ["mia"] : [])
        }
    )

    private static func snapshot(_ number: Int, _ repo: String, _ title: String, author: String, hoursAgo: Double, draft: Bool) -> PullRequestSnapshot {
        PullRequestSnapshot(
            ref: PullRequestRef(owner: "acme", repo: repo, number: number),
            title: title,
            url: URL(string: "https://github.com/acme/\(repo)/pull/\(number)")!,
            author: Actor(login: author, isBot: false),
            isDraft: draft,
            createdAt: Date().addingTimeInterval(-hoursAgo * 3600 - 60),
            reviewDecision: nil, mergeable: .mergeable, mergeState: .blocked, checks: .none,
            threads: [], comments: [], commits: [], reviews: [], requestedReviewers: []
        )
    }

    private static func item(_ number: Int, _ repo: String, _ title: String, hoursAgo: Double, reasons: [MineReason]) -> MineItem {
        MineItem(pr: snapshot(number, repo, title, author: "me", hoursAgo: hoursAgo, draft: false), reasons: reasons)
    }

    private static func waiting(_ number: Int, _ repo: String, _ title: String, hoursAgo: Double, reviewers: [String]) -> WaitingItem {
        WaitingItem(pr: snapshot(number, repo, title, author: "me", hoursAgo: hoursAgo, draft: false).with(requestedReviewers: reviewers))
    }

    private static func review(
        _ number: Int, _ repo: String, _ title: String, author: String, hoursAgo: Double, requested: Bool = false, draft: Bool = false
    ) -> ReviewItem {
        ReviewItem(pr: snapshot(number, repo, title, author: author, hoursAgo: hoursAgo, draft: draft), isRequested: requested)
    }
}

extension DiagnosticsReport {
    /// Fake numbers for the demo modes and the README pictures.
    static var sample: DiagnosticsReport {
        let now = Date()
        return DiagnosticsReport(
            appVersion: SoftwareUpdater.version, systemVersion: "15.1", authSource: .ghCli, organizationCount: 2,
            refreshMinutes: 5, lastSync: now.addingTimeInterval(-42), status: .ok, reviewCount: 7, mineCount: 3,
            rateLimit: RateLimit(limit: 5000, remaining: 4812, resetsAt: now.addingTimeInterval(37 * 60)),
            shortcutActive: true, automaticUpdates: true
        )
    }
}
