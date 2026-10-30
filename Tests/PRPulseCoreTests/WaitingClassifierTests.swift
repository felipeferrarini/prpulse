import Foundation
import Testing
@testable import PRPulseCore

private let day: Double = 86_400
private let now = at(10 * day)

private func waiting(_ prs: [PullRequestSnapshot], days: Int = 2, bots: Set<String> = []) -> [Int] {
    WaitingClassifier.items(from: prs, viewer: viewer, ignoredBots: bots, minimumDays: days, now: now).map(\.pr.ref.number)
}

private func review(by login: String, _ state: ReviewState = .commented) -> ReviewSnapshot {
    ReviewSnapshot(authorLogin: login, state: state, submittedAt: at(9 * day))
}

@Test func aPullRequestWithoutReviewsWaitsOnceItIsOldEnough() {
    let old = PullRequestSnapshot.fixture(number: 1, createdAt: at(7 * day))
    let fresh = PullRequestSnapshot.fixture(number: 2, createdAt: at(9.5 * day))
    #expect(waiting([old, fresh]) == [1])
}

@Test func theOldestWaitsFirst() {
    let older = PullRequestSnapshot.fixture(number: 1, createdAt: at(2 * day))
    let newer = PullRequestSnapshot.fixture(number: 2, createdAt: at(5 * day))
    #expect(waiting([newer, older]) == [1, 2])
}

@Test func anyReviewFromSomeoneElseEndsTheWait() {
    let reviewed = PullRequestSnapshot.fixture(number: 1, createdAt: at(0), reviews: [review(by: "reviewer")])
    let approved = PullRequestSnapshot.fixture(number: 2, createdAt: at(0), reviews: [review(by: "reviewer", .approved)])
    #expect(waiting([reviewed, approved]).isEmpty)
}

@Test func myOwnReviewsAndBotsAndPendingOnesDoNotCount() {
    let own = PullRequestSnapshot.fixture(number: 1, createdAt: at(0), reviews: [review(by: viewer)])
    let bot = PullRequestSnapshot.fixture(number: 2, createdAt: at(0), reviews: [review(by: "coderabbitai")])
    let pending = PullRequestSnapshot.fixture(number: 3, createdAt: at(0), reviews: [review(by: "reviewer", .pending)])
    #expect(waiting([own, bot, pending], bots: ["coderabbitai"]) == [1, 2, 3])
}

@Test func draftsAndPullRequestsWithRequestedChangesAreNotWaiting() {
    let draft = PullRequestSnapshot.fixture(number: 1, isDraft: true, createdAt: at(0))
    let changes = PullRequestSnapshot.fixture(number: 2, createdAt: at(0), reviewDecision: .changesRequested)
    #expect(waiting([draft, changes]).isEmpty)
}

@Test func zeroDaysTurnsTheListOff() {
    #expect(waiting([PullRequestSnapshot.fixture(number: 1, createdAt: at(0))], days: 0).isEmpty)
}

@Test func theSummaryKeepsWaitingOutOfTheCountAndOutOfActionableOnes() {
    let quiet = PullRequestSnapshot.fixture(number: 1, createdAt: at(0))
    let failing = PullRequestSnapshot.fixture(number: 2, createdAt: at(0), checks: .failing)
    let summary = SummaryBuilder.build(
        minePRs: [quiet, failing], reviewPRs: [], viewer: viewer, ignoredBots: [], ignoredRepos: [], waitingDays: 2, now: now
    )

    #expect(summary.waiting.map(\.pr.ref.number) == [1])
    #expect(summary.mine.map(\.pr.ref.number) == [2])
    #expect(summary.total == 1)
}

@Test func anIgnoredRepositoryMatchesByOwnerAndName() {
    let hidden = PullRequestSnapshot.fixture(number: 1, repo: "docs", author: otherHuman)
    let other = PullRequestSnapshot(
        ref: PullRequestRef(owner: "elsewhere", repo: "docs", number: 2), title: "t", url: URL(string: "https://x.test")!,
        author: otherHuman, isDraft: false, createdAt: at(0), reviewDecision: nil, mergeable: .mergeable, mergeState: .blocked,
        checks: .none, threads: [], comments: [], commits: [], reviews: [], requestedReviewers: []
    )
    let items = ReviewClassifier.items(from: [hidden, other], viewer: viewer, ignoredRepos: ["org/docs"])
    #expect(items.map(\.pr.ref.number) == [2])
}
