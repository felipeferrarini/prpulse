import Testing
@testable import PRPulseCore

private let ignoredBots: Set<String> = ["coderabbitai", "sonarqubecloud"]

private func reasons(_ pr: PullRequestSnapshot) -> [MineReason] {
    MineClassifier.reasons(for: pr, viewer: viewer, ignoredBots: ignoredBots)
}

@Test func changesRequestedComesFirst() {
    let pr = PullRequestSnapshot.fixture(reviewDecision: .changesRequested, mergeable: .conflicting)
    #expect(reasons(pr) == [.changesRequested, .conflict])
}

@Test func openThreadsCountsOnlyUnresolvedHumanThreads() {
    let pr = PullRequestSnapshot.fixture(threads: [
        thread(resolved: false),
        thread(resolved: false),
        thread(resolved: true),
        thread(resolved: false, startedBy: botActor),
    ])
    #expect(reasons(pr) == [.openThreads(2)])
}

@Test func outdatedUnresolvedThreadStillCounts() {
    let pr = PullRequestSnapshot.fixture(threads: [thread(resolved: false)])
    #expect(reasons(pr) == [.openThreads(1)])
}

@Test func botAndIgnoredLoginCommentsAreIgnored() {
    let ignored = Actor(login: "coderabbitai", isBot: false)
    let pr = PullRequestSnapshot.fixture(comments: [
        comment(by: ignored, at: 10),
        comment(by: botActor, at: 11),
    ])
    #expect(reasons(pr).isEmpty)
}

@Test func unansweredCommentUntilViewerCommitsOrReplies() {
    let others = comment(by: human, at: 10)

    #expect(reasons(.fixture(comments: [others], commits: [commit(by: viewer, at: 5)])) == [.unansweredComment])
    #expect(reasons(.fixture(comments: [others], commits: [commit(by: viewer, at: 11)])).isEmpty)
    #expect(reasons(.fixture(comments: [others, comment(by: Actor(login: viewer, isBot: false), at: 12)])).isEmpty)
    #expect(reasons(.fixture(comments: [others], commits: [commit(by: "someone", at: 11)])) == [.unansweredComment])
    #expect(reasons(.fixture(comments: [others], commits: [commit(by: nil, at: 11)])) == [.unansweredComment])
}

@Test func reviewBodyCountsAsLooseComment() {
    let pr = PullRequestSnapshot.fixture(comments: [comment(by: human, at: 10, isReviewBody: true)])
    #expect(reasons(pr) == [.unansweredComment])
}

@Test func ghostAuthorCommentDoesNotCrashAndCounts() {
    let ghost = Actor(login: "ghost", isBot: false)
    let pr = PullRequestSnapshot.fixture(comments: [comment(by: ghost, at: 10)])
    #expect(reasons(pr) == [.unansweredComment])
}

@Test func ciFailedConflictReadyToMerge() {
    #expect(reasons(.fixture(checks: .failing)) == [.ciFailed])
    #expect(reasons(.fixture(checks: .pending)).isEmpty)
    #expect(reasons(.fixture(mergeable: .conflicting)) == [.conflict])
    #expect(reasons(.fixture(mergeState: .clean)) == [.readyToMerge])
    #expect(reasons(.fixture(mergeState: .blocked)).isEmpty)
}

@Test func ownDraftOnlyShowsFeedbackReasons() {
    let draft = PullRequestSnapshot.fixture(
        isDraft: true, mergeable: .conflicting, mergeState: .clean, checks: .failing
    )
    #expect(reasons(draft).isEmpty)

    let withFeedback = PullRequestSnapshot.fixture(isDraft: true, reviewDecision: .changesRequested)
    #expect(reasons(withFeedback) == [.changesRequested])
}

@Test func reasonsAreOrderedByUrgency() {
    let pr = PullRequestSnapshot.fixture(
        reviewDecision: .changesRequested,
        mergeable: .conflicting,
        mergeState: .clean,
        checks: .failing,
        threads: [thread(resolved: false)],
        comments: [comment(by: human, at: 10)]
    )
    #expect(reasons(pr) == [
        .changesRequested, .openThreads(1), .unansweredComment, .ciFailed, .conflict, .readyToMerge,
    ])
}

@Test func mineItemPrimaryIsFirstReason() {
    let pr = PullRequestSnapshot.fixture(mergeable: .conflicting, mergeState: .clean)
    let item = MineItem(pr: pr, reasons: reasons(pr))
    #expect(item.primary == .conflict)
}
