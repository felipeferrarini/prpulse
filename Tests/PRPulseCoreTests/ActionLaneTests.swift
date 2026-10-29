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
