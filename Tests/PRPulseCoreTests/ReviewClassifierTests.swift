import Testing
@testable import PRPulseCore

private func items(_ prs: [PullRequestSnapshot], ignoredRepos: Set<String> = []) -> [ReviewItem] {
    ReviewClassifier.items(from: prs, viewer: viewer, ignoredRepos: ignoredRepos)
}

private func review(_ state: ReviewState, by login: String = viewer) -> ReviewSnapshot {
    ReviewSnapshot(authorLogin: login, state: state, submittedAt: at(1))
}

@Test func excludesViewersOwnPullRequests() {
    let mine = PullRequestSnapshot.fixture(number: 1, author: Actor(login: viewer, isBot: false))
    let theirs = PullRequestSnapshot.fixture(number: 2, author: otherHuman)
    #expect(items([mine, theirs]).map(\.pr.ref.number) == [2])
}

@Test func submittedReviewOfAnyKindHidesThePullRequest() {
    for state in [ReviewState.approved, .commented, .changesRequested, .dismissed] {
        let pr = PullRequestSnapshot.fixture(author: otherHuman, reviews: [review(state)])
        #expect(items([pr]).isEmpty)
    }
}

@Test func pendingReviewAndOthersReviewsDoNotHideThePullRequest() {
    let pending = PullRequestSnapshot.fixture(number: 1, author: otherHuman, reviews: [review(.pending)])
    let byOther = PullRequestSnapshot.fixture(number: 2, author: otherHuman, reviews: [review(.approved, by: "someone")])
    #expect(items([pending, byOther]).count == 2)
}

@Test func ignoredRepoIsHiddenUnlessViewerIsRequestedReviewer() {
    let hidden = PullRequestSnapshot.fixture(number: 1, repo: "docs", author: otherHuman)
    let requested = PullRequestSnapshot.fixture(number: 2, repo: "docs", author: otherHuman, requestedReviewers: [viewer])
    let normal = PullRequestSnapshot.fixture(number: 3, repo: "app", author: otherHuman)
    #expect(items([hidden, requested, normal], ignoredRepos: ["docs"]).map(\.pr.ref.number) == [2, 3])
}

@Test func draftsGoLastOldestFirstWithinEachGroup() {
    let prs = [
        PullRequestSnapshot.fixture(number: 1, author: otherHuman, isDraft: true, createdAt: at(1)),
        PullRequestSnapshot.fixture(number: 2, author: otherHuman, createdAt: at(30)),
        PullRequestSnapshot.fixture(number: 3, author: otherHuman, isDraft: true, createdAt: at(0)),
        PullRequestSnapshot.fixture(number: 4, author: otherHuman, createdAt: at(10)),
    ]
    #expect(items(prs).map(\.pr.ref.number) == [4, 2, 3, 1])
}

@Test func botAuthoredPullRequestIsListed() {
    let dependabot = Actor(login: "dependabot", isBot: true)
    let pr = PullRequestSnapshot.fixture(author: dependabot)
    #expect(items([pr]).count == 1)
}

@Test func ghostAuthoredPullRequestIsListed() {
    let pr = PullRequestSnapshot.fixture(author: .ghost)
    #expect(items([pr]).count == 1)
}

@Test func requestsToTheViewerComeFirstAndAreFlagged() {
    let prs = [
        PullRequestSnapshot.fixture(number: 1, author: otherHuman, createdAt: at(0)),
        PullRequestSnapshot.fixture(number: 2, author: otherHuman, createdAt: at(50), requestedReviewers: [viewer]),
        PullRequestSnapshot.fixture(number: 3, author: otherHuman, isDraft: true, createdAt: at(10), requestedReviewers: [viewer.uppercased()]),
    ]
    let result = items(prs)

    #expect(result.map(\.pr.ref.number) == [2, 3, 1])
    #expect(result.map(\.isRequested) == [true, true, false])
}

// MARK: Pull requests opened by bots

private let dependabot = Actor(login: "dependabot", isBot: true)
private let renovateUser = Actor(login: "renovate-bot", isBot: false)

private func bots(_ prs: [PullRequestSnapshot], skip: Bool, listed: Set<String> = []) -> [Int] {
    ReviewClassifier.items(from: prs, viewer: viewer, ignoredRepos: [], ignoredBots: listed, skipsBotAuthors: skip).map(\.pr.ref.number)
}

@Test func botPullRequestsShowUnlessTheViewerAsksToSkipThem() {
    let human = PullRequestSnapshot.fixture(number: 1, author: otherHuman)
    let bot = PullRequestSnapshot.fixture(number: 2, author: dependabot)
    #expect(bots([human, bot], skip: false) == [1, 2])
    #expect(bots([human, bot], skip: true) == [1])
}

@Test func anAccountTheViewerListedAsABotIsSkippedToo() {
    let human = PullRequestSnapshot.fixture(number: 1, author: otherHuman)
    let renovate = PullRequestSnapshot.fixture(number: 2, author: renovateUser)
    #expect(bots([human, renovate], skip: true) == [1, 2])
    #expect(bots([human, renovate], skip: true, listed: ["Renovate-Bot"]) == [1])
}

@Test func skippingBotsHidesThemEvenWhenTheViewerWasAskedToReview() {
    let asked = PullRequestSnapshot.fixture(number: 1, author: dependabot, requestedReviewers: [viewer])
    #expect(bots([asked], skip: true).isEmpty)
}

@Test func theSummaryHonorsTheBotSetting() {
    let bot = PullRequestSnapshot.fixture(number: 2, author: dependabot)
    let shown = SummaryBuilder.build(minePRs: [], reviewPRs: [bot], viewer: viewer, ignoredBots: [], ignoredRepos: [])
    let hidden = SummaryBuilder.build(minePRs: [], reviewPRs: [bot], viewer: viewer, ignoredBots: [], ignoredRepos: [], skipsBotPullRequests: true)
    #expect(shown.review.count == 1)
    #expect(hidden.review.isEmpty)
    #expect(hidden.total == 0)
}
