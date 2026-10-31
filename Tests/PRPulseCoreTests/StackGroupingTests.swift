import Foundation
import Testing
@testable import PRPulseCore

private func pr(_ number: Int, repo: String = "api", stack: Int? = nil, position: Int = 1, size: Int = 3, age: TimeInterval = 0) -> PullRequestSnapshot {
    PullRequestSnapshot(
        ref: PullRequestRef(owner: "acme", repo: repo, number: number),
        title: "PR \(number)", url: URL(string: "https://github.com/acme/\(repo)/pull/\(number)")!,
        author: Actor(login: "sam", isBot: false), isDraft: false, createdAt: Date(timeIntervalSince1970: 1_000 + age),
        reviewDecision: nil, mergeable: .mergeable, mergeState: .clean, checks: .passing,
        threads: [], comments: [], commits: [], reviews: [], requestedReviewers: [],
        stack: stack.map { StackMembership(number: $0, size: size, position: position, baseRef: "main") }
    )
}

private func entries(_ prs: [PullRequestSnapshot]) -> [ListEntry<PullRequestSnapshot>] {
    StackGrouping.entries(prs, pr: { $0 })
}

private func shape(_ list: [ListEntry<PullRequestSnapshot>]) -> [String] {
    list.map { entry in
        switch entry {
        case .single(_, let pr): "#\(pr.ref.number)"
        case .stack(let group): "stack(\(group.refs.map { "#\($0.number)" }.joined(separator: ",")))"
        }
    }
}

@Test func pullRequestsOfOneStackBecomeOneEntryInTheOrderOfTheStack() {
    let list = entries([pr(3, stack: 9, position: 3), pr(1, stack: 9, position: 1), pr(2, stack: 9, position: 2)])

    #expect(shape(list) == ["stack(#1,#2,#3)"])
}

@Test func theStackTakesThePlaceOfItsFirstMemberAndTheRestOfTheListKeepsItsOrder() {
    let list = entries([pr(10), pr(3, stack: 9, position: 3), pr(11), pr(1, stack: 9, position: 1), pr(12)])

    #expect(shape(list) == ["#10", "stack(#1,#3)", "#11", "#12"])
}

@Test func aStackWithOneMemberInTheListStaysARowOfItsOwn() {
    let list = entries([pr(2, stack: 9, position: 2, size: 4), pr(5)])

    #expect(shape(list) == ["#2", "#5"])
}

@Test func twoStacksAndTwoRepositoriesAreKeptApart() {
    let list = entries([
        pr(1, stack: 1, position: 1), pr(2, stack: 1, position: 2),
        pr(1, repo: "web", stack: 1, position: 1), pr(2, repo: "web", stack: 1, position: 2),
        pr(7, stack: 2, position: 1), pr(8, stack: 2, position: 2),
    ])

    #expect(shape(list) == ["stack(#1,#2)", "stack(#1,#2)", "stack(#7,#8)"])
    let keys = list.compactMap { entry -> StackKey? in if case .stack(let group) = entry { group.key } else { nil } }
    #expect(Set(keys).count == 3)
}

@Test func theGroupKnowsItsSizeCompletenessAndWhoWaitedLongest() {
    let list = entries([pr(1, stack: 9, position: 1, size: 4, age: 500), pr(2, stack: 9, position: 2, size: 4, age: 100)])

    guard case .stack(let group)? = list.first else {
        Issue.record("no group")
        return
    }
    #expect(group.size == 4)
    #expect(!group.isComplete)
    #expect(group.oldest.ref.number == 2)
    #expect(group.bottom.ref.number == 1)
}

@Test func aCompleteStackSaysSo() {
    let list = entries([pr(1, stack: 9, position: 1, size: 2), pr(2, stack: 9, position: 2, size: 2)])

    guard case .stack(let group)? = list.first else {
        Issue.record("no group")
        return
    }
    #expect(group.isComplete)
}

@Test func pullRequestsWithoutAStackAreNeverGrouped() {
    #expect(shape(entries([pr(1), pr(2), pr(3)])) == ["#1", "#2", "#3"])
    #expect(entries([PullRequestSnapshot]()).isEmpty)
}
