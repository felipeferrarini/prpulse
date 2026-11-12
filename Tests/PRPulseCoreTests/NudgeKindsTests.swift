import Foundation
import Testing
@testable import PRPulseCore

private let now = at(1_000_000)
private let hour = 3600.0
private let me = Actor(login: viewer, isBot: false)

private func mine(
    _ number: Int = 1,
    decision: ReviewDecision? = nil,
    reviews: [ReviewSnapshot] = [],
    requested: [String] = [],
    nudges: [NudgeSnapshot] = [],
    isDraft: Bool = false
) -> PullRequestSnapshot {
    .fixture(number: number, author: me, isDraft: isDraft, reviewDecision: decision, reviews: reviews, requestedReviewers: requested, nudges: nudges)
}

private func theirs(
    _ number: Int = 1,
    by author: Actor = Actor(login: "mateus", isBot: false),
    decision: ReviewDecision? = nil,
    reviews: [ReviewSnapshot] = [],
    nudges: [NudgeSnapshot] = [],
    isDraft: Bool = false
) -> PullRequestSnapshot {
    .fixture(number: number, author: author, isDraft: isDraft, reviewDecision: decision, reviews: reviews, nudges: nudges)
}

private func review(_ login: String, _ state: ReviewState, at seconds: Double = 10) -> ReviewSnapshot {
    ReviewSnapshot(authorLogin: login, state: state, submittedAt: at(seconds))
}

private func nudge(
    from sender: String, to recipient: String, kind: NudgeKind = .review, tone: Int = 1, hoursAgo: Double = 10, id: String? = nil
) -> NudgeSnapshot {
    NudgeSnapshot(
        id: id ?? "\(sender)-\(recipient)-\(hoursAgo)", recipient: recipient, tone: tone, message: nil,
        author: Actor(login: sender, isBot: false), createdAt: now.addingTimeInterval(-hoursAgo * hour), kind: kind
    )
}

private func candidates(_ pr: PullRequestSnapshot, team: [String] = []) -> [NudgeCandidate] {
    NudgeEligibility.candidates(for: pr, viewer: viewer, team: team, ignoredBots: [], now: now)
}

private func logins(_ list: [NudgeCandidate]) -> [String] {
    list.map(\.login)
}

// MARK: Minimum reviews

@Test func theReviewDecisionSaysWhetherTheMinimumIsMet() {
    #expect(MinimumReviews.isMet(theirs(decision: .approved)))
    #expect(!MinimumReviews.isMet(theirs(decision: .reviewRequired)))
    #expect(!MinimumReviews.isMet(theirs(decision: .changesRequested)))
}

@Test func withoutAReviewRuleOneApprovalIsEnough() {
    let approved = theirs(reviews: [review("rita", .approved)])
    #expect(MinimumReviews.isMet(approved))
    #expect(MinimumReviews.isMet(approved, countingApprovalOf: "rita"))
    #expect(!MinimumReviews.isMet(approved, countingApprovalOf: viewer))
    #expect(!MinimumReviews.isMet(theirs(reviews: [review("rita", .commented)])))
}

@Test func theLatestWordOfAReviewerIsTheOneThatCounts() {
    let changed = theirs(reviews: [review("rita", .approved, at: 10), review("rita", .changesRequested, at: 20)])
    #expect(MinimumReviews.latestState(of: "rita", in: changed) == .changesRequested)
    #expect(!MinimumReviews.isMet(changed))
}

// MARK: To review: anyone on the team

@Test func anyoneOnTheTeamCanBeAskedWhileThePullRequestLacksReviews() {
    let result = candidates(mine(), team: ["zeca", "Ana", "bia"])

    #expect(logins(result) == ["Ana", "bia", "zeca"])
    #expect(result.allSatisfy { $0.isAllowed && $0.kind == .review && $0.tone == 1 })
}

@Test func thoseAskedForAReviewComeFirst() {
    #expect(logins(candidates(mine(requested: ["zeca"]), team: ["ana", "zeca"])) == ["zeca", "ana"])
}

@Test func someoneWhoAlreadyReviewedIsNotAskedAgainByTheNewRule() {
    let pr = mine(decision: .reviewRequired, reviews: [review("ana", .approved), review("bia", .commented)])
    #expect(!logins(candidates(pr, team: ["ana", "bia", "caio"])).contains("ana"))
    #expect(logins(candidates(pr, team: ["caio"])).contains("caio"))
}

@Test func onceThePullRequestHasItsReviewsNoOneNewIsAsked() {
    let pr = mine(decision: .approved, reviews: [review("ana", .approved)])
    #expect(candidates(pr, team: ["bia", "caio"]).isEmpty)
}

@Test func aDraftHasNoOneToNudge() {
    #expect(candidates(mine(isDraft: true), team: ["ana"]).isEmpty)
}

@Test func theViewerAndBotsAreLeftOut() {
    let result = NudgeEligibility.candidates(
        for: mine(), viewer: viewer, team: [viewer, "ana", "Copilot", "ci[bot]"], ignoredBots: ["copilot"], now: now
    )
    #expect(logins(result) == ["ana"])
}

// MARK: To review: one budget per person and per pull request

@Test func theSecondNudgeWaitsAndIsLouderAndTheBudgetBelongsToThePullRequest() {
    let soon = mine(1, nudges: [nudge(from: viewer, to: "ana", hoursAgo: 1)])
    let later = mine(2, nudges: [nudge(from: viewer, to: "ana", hoursAgo: 4)])
    let other = mine(3)

    #expect(candidates(soon, team: ["ana"]).first?.block == .tooSoon(until: now.addingTimeInterval(2 * hour)))
    #expect(candidates(later, team: ["ana"]).first?.isAllowed == true)
    #expect(candidates(later, team: ["ana"]).first?.tone == 2)
    #expect(candidates(other, team: ["ana"]).first?.tone == 1)
}

@Test func afterThreeNudgesAboutThePullRequestThereAreNoMore() {
    let sent = (1 ... 3).map { nudge(from: viewer, to: "ana", hoursAgo: Double(40 - $0 * 10)) }
    #expect(candidates(mine(nudges: sent), team: ["ana"]).first?.block == .limitReached)
}

@Test func nudgesOfOthersAndOfOtherKindsDoNotUseUpTheBudget() {
    let pr = mine(nudges: [nudge(from: "caio", to: "ana"), nudge(from: viewer, to: "ana", kind: .merge)])
    #expect(candidates(pr, team: ["ana"]).first?.tone == 1)
}

@Test func someoneWhoTookPartStillNeedsSomethingNewToReadAgain() {
    let commented = mine(reviews: [review("ana", .commented, at: 10)])
    #expect(candidates(commented).first?.block == .noNewCommits)
}

// MARK: To merge

@Test func theAuthorCanBeToldAPullRequestTheViewerReviewedCanGoUp() {
    let pr = theirs(decision: .approved, reviews: [review(viewer, .approved)])
    let result = candidates(pr)

    #expect(logins(result) == ["mateus"])
    #expect(result[0].kind == .merge)
    #expect(result[0].isAllowed)
}

@Test func theViewerMustHaveReviewedAndTheMinimumMustBeMet() {
    #expect(candidates(theirs(decision: .approved, reviews: [review("rita", .approved)])).isEmpty)
    #expect(candidates(theirs(decision: .reviewRequired, reviews: [review(viewer, .approved)])).isEmpty)
    #expect(candidates(theirs(decision: nil, reviews: [review(viewer, .commented)])).isEmpty)
    #expect(candidates(theirs(decision: nil, reviews: [review(viewer, .approved)])).count == 1)
}

@Test func checksAndConflictsAreNotLookedAtForTheMinimum() {
    let pr = PullRequestSnapshot.fixture(
        author: Actor(login: "mateus", isBot: false), reviewDecision: .approved, mergeable: .conflicting, mergeState: .blocked,
        checks: .failing, reviews: [review(viewer, .approved)]
    )
    #expect(candidates(pr).count == 1)
}

@Test func aDraftOrABotAuthorIsNotToldToMerge() {
    let reviewed = [review(viewer, .approved)]
    #expect(candidates(theirs(decision: .approved, reviews: reviewed, isDraft: true)).isEmpty)
    #expect(candidates(theirs(by: Actor(login: "dependabot", isBot: true), decision: .approved, reviews: reviewed)).isEmpty)
}

@Test func theMergeNudgeHasItsOwnLimits() {
    let reviewed = [review(viewer, .approved)]
    let soon = theirs(decision: .approved, reviews: reviewed, nudges: [nudge(from: viewer, to: "mateus", kind: .merge, hoursAgo: 1)])
    let louder = theirs(decision: .approved, reviews: reviewed, nudges: [nudge(from: viewer, to: "mateus", kind: .merge, hoursAgo: 5)])
    let reviewKind = theirs(decision: .approved, reviews: reviewed, nudges: [nudge(from: viewer, to: "mateus", kind: .review, hoursAgo: 1)])

    #expect(candidates(soon).first?.block == .tooSoon(until: now.addingTimeInterval(2 * hour)))
    #expect(candidates(louder).first?.tone == 2)
    #expect(candidates(reviewKind).first?.isAllowed == true)
}

// MARK: The marker

@Test func theKindTravelsInTheMarkerAndOldMarkersAreReviewNudges() throws {
    let merge = NudgeCodec.marker(recipient: "mateus", id: "a1", tone: 2, message: nil, kind: .merge)
    let review = NudgeCodec.marker(recipient: "rita", id: "b2", tone: 1, message: nil)
    let author = Actor(login: viewer, isBot: false)

    #expect(NudgeCodec.parse(merge, author: author, createdAt: now)?.kind == .merge)
    #expect(NudgeCodec.parse(review, author: author, createdAt: now)?.kind == .review)
    #expect(!review.contains("kind="))
    #expect(NudgeCodec.parse("<!-- prpulse:nudge v1 to=rita id=old tone=1 -->", author: author, createdAt: now)?.kind == .review)
}

// MARK: Receiving

private func incoming(mineList: [PullRequestSnapshot] = [], reviewList: [ReviewItem] = []) -> [IncomingNudge] {
    let items = mineList.map { MineItem(pr: $0, reasons: [.readyToMerge]) }
    return NudgePlanner.incoming(in: Summary(mine: items, review: reviewList), viewer: viewer, seen: [], now: now)
}

@Test func aReviewerCanTellTheViewerThatThePullRequestCanGo() {
    let pr = mine(reviews: [review("rita", .approved)], nudges: [nudge(from: "rita", to: viewer, kind: .merge, hoursAgo: 1)])
    let result = incoming(mineList: [pr])

    #expect(result.count == 1)
    #expect(result[0].nudge.kind == .merge)
    #expect(result[0].isFresh)
}

@Test func someoneWhoNeverReviewedCannotSendAMergeNudge() {
    let pr = mine(reviews: [review("rita", .approved)], nudges: [nudge(from: "stranger", to: viewer, kind: .merge, hoursAgo: 1)])
    #expect(incoming(mineList: [pr]).isEmpty)
}

@Test func aMergeNudgeMustBeAddressedToTheViewer() {
    let pr = mine(reviews: [review("rita", .approved)], nudges: [nudge(from: "rita", to: "someone", kind: .merge, hoursAgo: 1)])
    #expect(incoming(mineList: [pr]).isEmpty)
}

@Test func eachReviewerHasABudgetOfTheirOwnForMergeNudges() {
    let pr = mine(
        reviews: [review("rita", .approved), review("bia", .approved)],
        nudges: [
            nudge(from: "rita", to: viewer, kind: .merge, hoursAgo: 5, id: "r1"),
            nudge(from: "rita", to: viewer, kind: .merge, hoursAgo: 4.5, id: "r2"),
            nudge(from: "bia", to: viewer, kind: .merge, hoursAgo: 1, id: "b1"),
        ]
    )
    #expect(incoming(mineList: [pr]).map(\.id) == ["b1"])
}

@Test func aReviewNudgeOnlyCountsWhileThePullRequestWaitsForTheViewer() {
    let asked = nudge(from: "mateus", to: viewer, hoursAgo: 1)
    let waiting = ReviewItem(pr: theirs(nudges: [asked]), isRequested: true)
    let done = ReviewItem(pr: theirs(2, nudges: [asked]), isRequested: false, hasReviewed: true)

    #expect(incoming(reviewList: [waiting, done]).map(\.ref.number) == [1])
}

@Test func aReviewNudgeMustComeFromTheAuthorOfThePullRequest() {
    let forged = ReviewItem(pr: theirs(nudges: [nudge(from: "stranger", to: viewer, hoursAgo: 1)]), isRequested: true)
    #expect(incoming(reviewList: [forged]).isEmpty)
}

// MARK: The team

@Test func theTeamIsWhoeverShowsUpInThePullRequests() {
    let review = ReviewItem(
        pr: .fixture(number: 5, author: Actor(login: "Zoe", isBot: false), reviews: [ReviewSnapshot(authorLogin: "bia", state: .approved, submittedAt: at(1))], requestedReviewers: ["ana"])
    )
    let own = MineItem(pr: mine(1, reviews: [ReviewSnapshot(authorLogin: "caio", state: .commented, submittedAt: at(1))], requested: ["ana", viewer]), reasons: [])
    let members = TeamDirectory.members(in: Summary(mine: [own], review: [review]), viewer: viewer, ignoredBots: ["bia"])

    #expect(members == ["ana", "caio", "Zoe"])
}
