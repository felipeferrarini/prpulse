import Foundation
import PRPulseCore

enum DemoMode: String {
    case pending, fresh, error, empty, unconfigured

    static var current: DemoMode? {
        guard let value = ProcessInfo.processInfo.environment["PRPULSE_DEMO"] else { return nil }
        return DemoMode(rawValue: value) ?? .pending
    }

    var viewData: ViewData {
        let now = Date()
        switch self {
        case .pending: return ViewData(state: .ready(DemoData.summary), summary: DemoData.summary, lastUpdated: now, org: "acme")
        case .fresh: return ViewData(state: .ready(DemoData.summary), summary: DemoData.summary, lastUpdated: now, freshUntil: now.addingTimeInterval(3600), org: "acme")
        case .empty:
            let empty = Summary(mine: [], review: [])
            return ViewData(state: .ready(empty), summary: empty, lastUpdated: now, org: "acme")
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
        ]
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

    private static func review(
        _ number: Int, _ repo: String, _ title: String, author: String, hoursAgo: Double, requested: Bool = false, draft: Bool = false
    ) -> ReviewItem {
        ReviewItem(pr: snapshot(number, repo, title, author: author, hoursAgo: hoursAgo, draft: draft), isRequested: requested)
    }
}
