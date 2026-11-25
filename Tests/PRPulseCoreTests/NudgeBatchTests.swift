import Foundation
import Testing
@testable import PRPulseCore

private func pr(_ number: Int) -> PullRequestSnapshot {
    PullRequestSnapshot(
        ref: PullRequestRef(owner: "acme", repo: "api", number: number),
        title: "PR \(number)", url: URL(string: "https://github.com/acme/api/pull/\(number)")!,
        author: Actor(login: "sam", isBot: false), isDraft: false, createdAt: Date(timeIntervalSince1970: 1_000),
        reviewDecision: nil, mergeable: .mergeable, mergeState: .clean, checks: .passing,
        threads: [], comments: [], commits: [], reviews: [], requestedReviewers: []
    )
}

private func candidate(_ login: String, tone: Int = 1, block: NudgeBlock? = nil, kind: NudgeKind = .review) -> NudgeCandidate {
    NudgeCandidate(login: login, tone: tone, block: block, kind: kind)
}

private func logins(_ targets: [NudgeTarget]) -> [String] { targets.map(\.login) }

@Test func aPersonAllowedOnSeveralPullRequestsIsOneTargetWithAnItemForEach() {
    let table: [Int: [NudgeCandidate]] = [1: [candidate("mia")], 2: [candidate("mia", tone: 2)], 3: [candidate("leo")]]
    let targets = NudgeBatch.targets(for: [pr(1), pr(2), pr(3)]) { table[$0.ref.number] ?? [] }
    #expect(logins(targets) == ["mia", "leo"])
    #expect(targets[0].items.map(\.pr.ref.number) == [1, 2])
    #expect(targets[0].items.map(\.candidate.tone) == [1, 2])
}

@Test func whoIsBlockedOnAPullRequestOnlyLosesThatOne() {
    let table: [Int: [NudgeCandidate]] = [1: [candidate("mia", block: .limitReached)], 2: [candidate("mia")]]
    let targets = NudgeBatch.targets(for: [pr(1), pr(2)]) { table[$0.ref.number] ?? [] }
    #expect(targets.count == 1)
    #expect(targets[0].items.map(\.pr.ref.number) == [2])
}

@Test func someoneBlockedOnEveryOneIsLeftOut() {
    let targets = NudgeBatch.targets(for: [pr(1)]) { _ in [candidate("mia", block: .noNewCommits)] }
    #expect(targets.isEmpty)
}

@Test func theMergeNudgeIsNotOfferedHere() {
    let targets = NudgeBatch.targets(for: [pr(1)]) { _ in [candidate("mia", kind: .merge)] }
    #expect(targets.isEmpty)
}

@Test func theOneAllowedOnMostComesFirstThenAlphabetically() {
    let table: [Int: [NudgeCandidate]] = [1: [candidate("zed"), candidate("bob")], 2: [candidate("zed"), candidate("Amy")], 3: [candidate("Amy")]]
    let targets = NudgeBatch.targets(for: [pr(1), pr(2), pr(3)]) { table[$0.ref.number] ?? [] }
    #expect(logins(targets) == ["Amy", "zed", "bob"])
}

@Test func theSameLoginInAnotherCaseIsTheSamePerson() {
    let table: [Int: [NudgeCandidate]] = [1: [candidate("Mia")], 2: [candidate("mia")]]
    let targets = NudgeBatch.targets(for: [pr(1), pr(2)]) { table[$0.ref.number] ?? [] }
    #expect(targets.count == 1)
    #expect(targets[0].login == "Mia")
    #expect(targets[0].items.count == 2)
}

@Test func nothingPickedGivesNoTargets() {
    #expect(NudgeBatch.targets(for: []) { _ in [candidate("mia")] }.isEmpty)
}
