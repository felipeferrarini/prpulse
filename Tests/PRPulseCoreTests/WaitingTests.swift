import Foundation
import Testing
@testable import PRPulseCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func waiting(hours: Double) -> Waiting {
    Waiting(since: now.addingTimeInterval(-hours * 3600), now: now)
}

@Test func lessThanAnHourReadsAsNow() {
    #expect(waiting(hours: 0.4).unit == .now)
}

@Test func underADayCountsWholeHours() {
    let wait = waiting(hours: 7.9)

    #expect(wait.unit == .hours)
    #expect(wait.value == 7)
}

@Test func fromADayOnCountsWholeDays() {
    let wait = waiting(hours: 76)

    #expect(wait.unit == .days)
    #expect(wait.value == 3)
}

@Test func toneWarmsAtOneDayAndTurnsHotAtThree() {
    #expect(waiting(hours: 23).tone == .normal)
    #expect(waiting(hours: 24).tone == .warm)
    #expect(waiting(hours: 71).tone == .warm)
    #expect(waiting(hours: 72).tone == .hot)
}

@Test func barFillsLinearlyAndCapsAtFourDays() {
    #expect(waiting(hours: 48).fraction == 0.5)
    #expect(waiting(hours: 500).fraction == 1)
}

@Test func aStartInTheFutureNeverGoesNegative() {
    let wait = Waiting(since: now.addingTimeInterval(3600), now: now)

    #expect(wait.hours == 0)
    #expect(wait.unit == .now)
}
