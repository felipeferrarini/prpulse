import Testing
@testable import PRPulseCore

private func build(mine: [PullRequestSnapshot], review: [PullRequestSnapshot] = []) -> Summary {
    SummaryBuilder.build(
        minePRs: mine, reviewPRs: review, viewer: viewer, ignoredBots: [], ignoredRepos: []
    )
}

@Test func summaryTotalAndEmpty() {
    let withFeedback = PullRequestSnapshot.fixture(number: 1, reviewDecision: .changesRequested)
    let conflicting = PullRequestSnapshot.fixture(number: 2, mergeable: .conflicting)
    let toReview = PullRequestSnapshot.fixture(number: 3, author: otherHuman)

    #expect(build(mine: [withFeedback, conflicting], review: [toReview]).total == 3)

    let quiet = PullRequestSnapshot.fixture(number: 4)
    #expect(build(mine: [quiet]).total == 0)
}

@Test func everyPullRequestOfTheViewerIsListedEvenWhenItAsksNothing() {
    let quiet = PullRequestSnapshot.fixture(number: 1)
    let ready = PullRequestSnapshot.fixture(number: 2, mergeState: .clean)
    let summary = build(mine: [quiet, ready])

    #expect(summary.mine.map(\.pr.ref.number) == [2, 1])
    #expect(summary.mine.map(\.needsAction) == [true, false])
}

@Test func mineSortedByPrimaryReasonThenAge() {
    let ready = PullRequestSnapshot.fixture(number: 1, createdAt: at(1), mergeState: .clean)
    let conflictNew = PullRequestSnapshot.fixture(number: 2, createdAt: at(50), mergeable: .conflicting)
    let conflictOld = PullRequestSnapshot.fixture(number: 3, createdAt: at(5), mergeable: .conflicting)
    let changes = PullRequestSnapshot.fixture(number: 4, createdAt: at(99), reviewDecision: .changesRequested)

    let summary = build(mine: [ready, conflictNew, conflictOld, changes])
    #expect(summary.mine.map(\.pr.ref.number) == [3, 2, 4, 1])
}

@Test func theQuietOnesComeAfterTheOnesThatAskSomething() {
    let draft = PullRequestSnapshot.fixture(number: 1, isDraft: true)
    let reviewed = PullRequestSnapshot.fixture(number: 2, reviews: [ReviewSnapshot(authorLogin: "reviewer", state: .approved, submittedAt: at(5))])
    let noReview = PullRequestSnapshot.fixture(number: 3)
    let ready = PullRequestSnapshot.fixture(number: 4, mergeState: .clean)
    let conflict = PullRequestSnapshot.fixture(number: 5, mergeable: .conflicting)
    let answer = PullRequestSnapshot.fixture(number: 6, reviewDecision: .changesRequested)

    let summary = build(mine: [draft, reviewed, noReview, ready, conflict, answer])
    #expect(summary.mine.map(\.pr.ref.number) == [5, 6, 4, 3, 2, 1])
    #expect(summary.total == 3)
}

@Test func aReviewFromTheViewerOrAnIgnoredBotDoesNotCountAsAReview() {
    let own = PullRequestSnapshot.fixture(number: 1, reviews: [ReviewSnapshot(authorLogin: viewer, state: .commented, submittedAt: at(5))])
    let bot = PullRequestSnapshot.fixture(number: 2, reviews: [ReviewSnapshot(authorLogin: "Copilot", state: .commented, submittedAt: at(5))])
    let pending = PullRequestSnapshot.fixture(number: 3, reviews: [ReviewSnapshot(authorLogin: "reviewer", state: .pending, submittedAt: nil)])

    let summary = SummaryBuilder.build(minePRs: [own, bot, pending], reviewPRs: [], viewer: viewer, ignoredBots: ["copilot"], ignoredRepos: [])
    #expect(summary.mine.map(\.quiet) == [.noReview, .noReview, .noReview])
    #expect(summary.mine.allSatisfy { $0.isWaitingForReview })
}
