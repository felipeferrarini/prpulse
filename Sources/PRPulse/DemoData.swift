import Foundation
import PRPulseCore

enum DemoMode: String {
    case pending, fresh, error, empty

    static var current: DemoMode? {
        guard let value = ProcessInfo.processInfo.environment["PRPULSE_DEMO"] else { return nil }
        return DemoMode(rawValue: value) ?? .pending
    }

    var viewData: ViewData {
        let now = Date()
        switch self {
        case .pending: return ViewData(state: .ready(DemoData.summary), summary: DemoData.summary, lastUpdated: now)
        case .fresh: return ViewData(state: .ready(DemoData.summary), summary: DemoData.summary, lastUpdated: now, freshUntil: now.addingTimeInterval(3600))
        case .empty:
            let empty = Summary(mine: [], review: [])
            return ViewData(state: .ready(empty), summary: empty, lastUpdated: now)
        case .error: return ViewData(state: .failed(.unauthenticated), summary: nil, lastUpdated: nil)
        }
    }
}

enum DemoData {
    static let summary = Summary(
        mine: [
            item(348, "web", "Fix class filter on the roster", reasons: [.changesRequested, .openThreads(2)]),
            item(160, "api", "Paginate the question list", reasons: [.unansweredComment]),
            item(349, "web", "Add resume-lesson card", reasons: [.conflict]),
            item(412, "admin", "Question indicators dashboard", reasons: [.readyToMerge]),
        ],
        review: [
            review(51, "mobile", "Add integration tests", author: "mia", daysAgo: 3, draft: false),
            review(161, "api", "Create search index", author: "leo", daysAgo: 0, draft: false),
            review(77, "billing", "Refactor billing retries", author: "sam", daysAgo: 1, draft: true),
        ]
    )

    private static func snapshot(_ number: Int, _ repo: String, _ title: String, author: String, daysAgo: Int, draft: Bool) -> PullRequestSnapshot {
        PullRequestSnapshot(
            ref: PullRequestRef(owner: "acme", repo: repo, number: number),
            title: title,
            url: URL(string: "https://github.com/acme/\(repo)/pull/\(number)")!,
            author: Actor(login: author, isBot: false),
            isDraft: draft,
            createdAt: Date().addingTimeInterval(-Double(daysAgo) * 86_400 - 3_600),
            reviewDecision: nil, mergeable: .mergeable, mergeState: .blocked, checks: .none,
            threads: [], comments: [], commits: [], reviews: [], requestedReviewers: []
        )
    }

    private static func item(_ number: Int, _ repo: String, _ title: String, reasons: [MineReason]) -> MineItem {
        MineItem(pr: snapshot(number, repo, title, author: "me", daysAgo: 2, draft: false), reasons: reasons)
    }

    private static func review(_ number: Int, _ repo: String, _ title: String, author: String, daysAgo: Int, draft: Bool) -> ReviewItem {
        ReviewItem(pr: snapshot(number, repo, title, author: author, daysAgo: daysAgo, draft: draft))
    }
}
