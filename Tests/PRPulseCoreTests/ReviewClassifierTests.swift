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
