import Foundation
import Testing
@testable import PRPulseCore

private let now = Date(timeIntervalSince1970: 1_000)

private func summary(pending: Int) -> Summary {
    let items = (0 ..< pending).map { number in
        MineItem(pr: .fixture(number: number + 1), reasons: [.conflict])
    }
    return Summary(mine: items, review: [])
}

@Test func iconStateMapping() {
    #expect(IconState.make(state: .idle, summary: nil, freshUntil: nil, now: now) == .upToDate)

    let three = summary(pending: 3)
    #expect(IconState.make(state: .ready(three), summary: three, freshUntil: nil, now: now) == .pending(3))
    #expect(IconState.make(state: .ready(three), summary: three, freshUntil: now.addingTimeInterval(5), now: now) == .fresh(3))
    #expect(IconState.make(state: .ready(three), summary: three, freshUntil: now.addingTimeInterval(-5), now: now) == .pending(3))
}

@Test func iconStateIsUpToDateWhenNothingIsPending() {
    let none = summary(pending: 0)
    #expect(IconState.make(state: .ready(none), summary: none, freshUntil: now.addingTimeInterval(5), now: now) == .upToDate)
}

@Test func iconStateIsErrorForAnyFailedStateEvenWithALastSummary() {
    let three = summary(pending: 3)
    #expect(IconState.make(state: .failed(.unauthenticated), summary: three, freshUntil: nil, now: now) == .error)
    #expect(IconState.make(state: .failed(.ssoRequired(org: nil)), summary: nil, freshUntil: nil, now: now) == .error)
    #expect(IconState.make(state: .failed(.notConfigured), summary: nil, freshUntil: nil, now: now) == .error)
}

@Test func iconStateKeepsLastSummaryWhileOffline() {
    let two = summary(pending: 2)
    #expect(IconState.make(state: .ready(two), summary: two, freshUntil: nil, now: now) == .pending(2))
    #expect(IconState.make(state: .idle, summary: two, freshUntil: nil, now: now) == .pending(2))
}
