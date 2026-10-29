import Foundation

public struct PullRequestSnapshot: Equatable, Sendable {
    public let ref: PullRequestRef
    public let title: String
    public let url: URL
    public let author: Actor
    public let isDraft: Bool
    public let createdAt: Date
    public let reviewDecision: ReviewDecision?
    public let mergeable: Mergeable
    public let mergeState: MergeState
    public let checks: ChecksState
    public let threads: [ThreadSnapshot]
    public let comments: [CommentSnapshot]
    public let commits: [CommitSnapshot]
    public let reviews: [ReviewSnapshot]
    public let requestedReviewers: [String]

    public init(
        ref: PullRequestRef,
        title: String,
        url: URL,
        author: Actor,
        isDraft: Bool,
        createdAt: Date,
        reviewDecision: ReviewDecision?,
        mergeable: Mergeable,
        mergeState: MergeState,
        checks: ChecksState,
        threads: [ThreadSnapshot],
        comments: [CommentSnapshot],
        commits: [CommitSnapshot],
        reviews: [ReviewSnapshot],
        requestedReviewers: [String]
    ) {
        self.ref = ref
        self.title = title
        self.url = url
        self.author = author
        self.isDraft = isDraft
        self.createdAt = createdAt
        self.reviewDecision = reviewDecision
        self.mergeable = mergeable
        self.mergeState = mergeState
        self.checks = checks
        self.threads = threads
        self.comments = comments
        self.commits = commits
        self.reviews = reviews
        self.requestedReviewers = requestedReviewers
    }

    public func with(threads: [ThreadSnapshot]) -> PullRequestSnapshot {
        PullRequestSnapshot(
            ref: ref, title: title, url: url, author: author, isDraft: isDraft, createdAt: createdAt,
            reviewDecision: reviewDecision, mergeable: mergeable, mergeState: mergeState, checks: checks,
            threads: threads, comments: comments, commits: commits, reviews: reviews,
            requestedReviewers: requestedReviewers
        )
    }

    public func with(checks: ChecksState) -> PullRequestSnapshot {
        PullRequestSnapshot(
            ref: ref, title: title, url: url, author: author, isDraft: isDraft, createdAt: createdAt,
            reviewDecision: reviewDecision, mergeable: mergeable, mergeState: mergeState, checks: checks,
            threads: threads, comments: comments, commits: commits, reviews: reviews,
            requestedReviewers: requestedReviewers
        )
    }
}
