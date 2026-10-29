import Foundation

public enum ReviewDecision: Sendable {
    case approved, changesRequested, reviewRequired
}

public enum Mergeable: Sendable {
    case mergeable, conflicting, unknown
}

public enum MergeState: Sendable {
    case clean, blocked, behind, dirty, unstable, draft, hasHooks, unknown
}

public enum ChecksState: Sendable {
    case passing, pending, failing, none
}

public enum ReviewState: Sendable {
    case approved, commented, changesRequested, dismissed, pending
}

public struct ThreadSnapshot: Equatable, Sendable {
    public let isResolved: Bool
    public let firstAuthor: Actor

    public init(isResolved: Bool, firstAuthor: Actor) {
        self.isResolved = isResolved
        self.firstAuthor = firstAuthor
    }
}

public struct CommentSnapshot: Equatable, Sendable {
    public let author: Actor
    public let createdAt: Date
    public let isReviewBody: Bool

    public init(author: Actor, createdAt: Date, isReviewBody: Bool) {
        self.author = author
        self.createdAt = createdAt
        self.isReviewBody = isReviewBody
    }
}

public struct CommitSnapshot: Equatable, Sendable {
    public let authorLogin: String?
    public let authoredDate: Date

    public init(authorLogin: String?, authoredDate: Date) {
        self.authorLogin = authorLogin
        self.authoredDate = authoredDate
    }
}

public struct ReviewSnapshot: Equatable, Sendable {
    public let authorLogin: String
    public let state: ReviewState
    public let submittedAt: Date?

    public init(authorLogin: String, state: ReviewState, submittedAt: Date?) {
        self.authorLogin = authorLogin
        self.state = state
        self.submittedAt = submittedAt
    }
}
