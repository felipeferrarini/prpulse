import Foundation
import Testing
@testable import PRPulseCore

@Test func halvesCoverTheWholeWindow() {
    let window = DateWindow(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 100))
    let (first, second) = window.halves()

    #expect(first.start == window.start)
    #expect(second.end == window.end)
    #expect(first.end == second.start)
}

@Test func qualifierUsesUtcIsoDates() {
    let window = DateWindow(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 86_400))
    #expect(window.qualifier == "created:1970-01-01T00:00:00Z..1970-01-02T00:00:00Z")
}

@Test func windowOfOneSecondCannotBeSplit() {
    let window = DateWindow(start: Date(timeIntervalSince1970: 10), end: Date(timeIntervalSince1970: 11))
    #expect(!window.canSplit)
}
