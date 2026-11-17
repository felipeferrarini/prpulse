import Testing
@testable import PRPulseCore

private func mine(_ number: Int, _ reasons: [MineReason]) -> MineItem {
    MineItem(pr: .fixture(number: number), reasons: reasons)
}

private func theirs(_ number: Int) -> ReviewItem {
    ReviewItem(pr: .fixture(number: number, author: otherHuman))
}

@Test func reasonsMapToTheActionTheyAskFor() {
    #expect(MineReason.changesRequested.lane == .changes)
    #expect(MineReason.openThreads(3).lane == .respond)
    #expect(MineReason.unansweredComment.lane == .respond)
    #expect(MineReason.ciFailed.lane == .ci)
    #expect(MineReason.conflict.lane == .conflict)
    #expect(MineReason.readyToMerge.lane == .merge)
}

@Test func mineItemMatchesEveryLaneOfItsReasons() {
    let item = mine(1, [.changesRequested, .openThreads(2), .ciFailed])

    #expect(item.matches(.changes))
    #expect(item.matches(.respond))
    #expect(item.matches(.ci))
    #expect(!item.matches(.merge))
    #expect(!item.matches(.review))
}

@Test func reviewItemOnlyMatchesTheReviewLane() {
    #expect(theirs(1).matches(.review))
    #expect(!theirs(1).matches(.ci))
}

@Test func summaryCountsPerLane() {
    let summary = Summary(
        mine: [mine(1, [.changesRequested, .openThreads(1)]), mine(2, [.unansweredComment]), mine(3, [.readyToMerge])],
        review: [theirs(10), theirs(11)]
    )

    #expect(summary.count(for: .review) == 2)
    #expect(summary.count(for: .changes) == 1)
    #expect(summary.count(for: .respond) == 2)
    #expect(summary.count(for: .merge) == 1)
    #expect(summary.count(for: .ci) == 0)
}

@Test func activeLanesSkipEmptyOnesAndKeepTheDisplayOrder() {
    let summary = Summary(mine: [mine(1, [.readyToMerge]), mine(2, [.conflict])], review: [theirs(10)])

    #expect(summary.activeLanes == [.review, .conflict, .merge])
}

// MARK: Where a pull request stands

private func reviewed(_ number: Int, ready: Bool = false, draft: Bool = false, requested: Bool = false) -> ReviewItem {
    ReviewItem(
        pr: .fixture(number: number, author: otherHuman, isDraft: draft, mergeState: ready ? .clean : .blocked),
        isRequested: requested, hasReviewed: true
    )
}

@Test func theLanesOfPullRequestsOfOthersFollowWhereTheyStandForTheViewer() {
    #expect(reviewed(1, ready: true).matches(.ready))
    #expect(!reviewed(1, ready: true).matches(.reviewed))
    #expect(reviewed(2).matches(.reviewed))
    #expect(!reviewed(2).matches(.review))
    #expect(reviewed(3, requested: true).matches(.review))
    #expect(reviewed(4, draft: true).matches(.draft))
    #expect(!reviewed(4, draft: true).matches(.reviewed))
    #expect(theirs(5).matches(.review))
    #expect(!theirs(5).matches(.waiting))
}

@Test func theLanesOfMyPullRequestsIncludeTheOnesThatAskNothing() {
    let waiting = MineItem(pr: .fixture(number: 1), reasons: [], quiet: .noReview)
    let inReview = MineItem(pr: .fixture(number: 2), reasons: [], quiet: .inReview)
    let draft = MineItem(pr: .fixture(number: 3, isDraft: true), reasons: [], quiet: .draft)
    let draftWithFeedback = MineItem(pr: .fixture(number: 4, isDraft: true), reasons: [.openThreads(1)], quiet: .draft)

    #expect(waiting.matches(.waiting) && !waiting.matches(.inReview))
    #expect(inReview.matches(.inReview) && !inReview.matches(.waiting))
    #expect(draft.matches(.draft) && !draft.matches(.waiting))
    #expect(draftWithFeedback.matches(.draft) && draftWithFeedback.matches(.respond))
    #expect(!mine(5, [.readyToMerge]).matches(.waiting))
}

@Test func everyStatusHasItsOwnCountAndDraftsOfBothListsAreTogether() {
    let summary = Summary(
        mine: [
            MineItem(pr: .fixture(number: 1), reasons: [], quiet: .noReview),
            MineItem(pr: .fixture(number: 2), reasons: [], quiet: .inReview),
            MineItem(pr: .fixture(number: 3, isDraft: true), reasons: [], quiet: .draft),
        ],
        review: [theirs(10), reviewed(11, ready: true), reviewed(12), reviewed(13, draft: true)]
    )

    #expect(summary.count(for: .review) == 1)
    #expect(summary.count(for: .ready) == 1)
    #expect(summary.count(for: .reviewed) == 1)
    #expect(summary.count(for: .waiting) == 1)
    #expect(summary.count(for: .inReview) == 1)
    #expect(summary.count(for: .draft) == 2)
    #expect(summary.activeLanes == [.review, .ready, .reviewed, .waiting, .inReview, .draft])
}
