import Foundation
@testable import PRPulseCore

let viewer = "me"

func at(_ seconds: Double) -> Date {
    Date(timeIntervalSince1970: seconds)
}

let human = Actor(login: "reviewer", isBot: false)
let otherHuman = Actor(login: "someone", isBot: false)
let botActor = Actor(login: "github-actions", isBot: true)

extension PullRequestSnapshot {
    static func fixture(
        number: Int = 1,
        repo: String = "app",
        author: Actor = Actor(login: viewer, isBot: false),
        isDraft: Bool = false,
        createdAt: Date = at(0),
        reviewDecision: ReviewDecision? = nil,
        mergeable: Mergeable = .mergeable,
        mergeState: MergeState = .blocked,
        checks: ChecksState = .none,
        threads: [ThreadSnapshot] = [],
        comments: [CommentSnapshot] = [],
        commits: [CommitSnapshot] = [],
        reviews: [ReviewSnapshot] = [],
        requestedReviewers: [String] = []
    ) -> PullRequestSnapshot {
        PullRequestSnapshot(
            ref: PullRequestRef(owner: "org", repo: repo, number: number),
            title: "PR \(number)",
            url: URL(string: "https://github.com/org/\(repo)/pull/\(number)")!,
            author: author,
            isDraft: isDraft,
            createdAt: createdAt,
            reviewDecision: reviewDecision,
            mergeable: mergeable,
            mergeState: mergeState,
            checks: checks,
            threads: threads,
            comments: comments,
            commits: commits,
            reviews: reviews,
            requestedReviewers: requestedReviewers
        )
    }
}

func comment(by author: Actor, at seconds: Double, isReviewBody: Bool = false) -> CommentSnapshot {
    CommentSnapshot(author: author, createdAt: at(seconds), isReviewBody: isReviewBody)
}

func commit(by login: String?, at seconds: Double) -> CommitSnapshot {
    CommitSnapshot(authorLogin: login, authoredDate: at(seconds))
}

func thread(resolved: Bool, startedBy author: Actor = human) -> ThreadSnapshot {
    ThreadSnapshot(isResolved: resolved, firstAuthor: author)
}
