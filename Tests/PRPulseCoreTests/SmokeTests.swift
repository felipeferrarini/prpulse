import Foundation
import Testing
@testable import PRPulseCore

@Test func smokeSystemClockIsNow() {
    #expect(abs(SystemClock().now.timeIntervalSinceNow) < 1)
}
