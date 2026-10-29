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

@Test func mineWithoutReasonsIsDropped() {
    let quiet = PullRequestSnapshot.fixture(number: 1)
    let ready = PullRequestSnapshot.fixture(number: 2, mergeState: .clean)
    #expect(build(mine: [quiet, ready]).mine.map(\.pr.ref.number) == [2])
}

@Test func mineSortedByPrimaryReasonThenAge() {
    let ready = PullRequestSnapshot.fixture(number: 1, createdAt: at(1), mergeState: .clean)
    let conflictNew = PullRequestSnapshot.fixture(number: 2, createdAt: at(50), mergeable: .conflicting)
    let conflictOld = PullRequestSnapshot.fixture(number: 3, createdAt: at(5), mergeable: .conflicting)
    let changes = PullRequestSnapshot.fixture(number: 4, createdAt: at(99), reviewDecision: .changesRequested)

    let summary = build(mine: [ready, conflictNew, conflictOld, changes])
    #expect(summary.mine.map(\.pr.ref.number) == [4, 3, 2, 1])
}
