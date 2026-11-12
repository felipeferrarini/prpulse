import Foundation

/// What the author sends to nudge a reviewer.
public struct NudgeRequest: Equatable, Sendable {
    public let ref: PullRequestRef
    /// Who is nudged: a reviewer to review, or the author of the pull request to merge it.
    public let reviewer: String
    public let tone: Int
    public let message: String?
    /// The line people read in the comment, in the sender's language.
    public let text: String
    public let kind: NudgeKind

    public init(ref: PullRequestRef, reviewer: String, tone: Int, message: String?, text: String, kind: NudgeKind = .review) {
        self.ref = ref
        self.reviewer = reviewer
        self.tone = tone
        self.message = message
        self.text = text
        self.kind = kind
    }
}

public enum NudgeOutcome: Equatable, Sendable {
    /// The review was asked for again and the comment was left.
    case sent
    /// The comment was left, but the host would not ask for the review again.
    case commentOnly
}

/// The writing side of a provider: the only things PRPulse changes on a pull request are the ones a nudge does.
public protocol PullRequestNudger: Sendable {
    func nudge(_ request: NudgeRequest) async throws -> NudgeOutcome
}
