import Foundation

struct DateWindow: Equatable, Sendable {
    let start: Date
    let end: Date

    var canSplit: Bool { end.timeIntervalSince(start) >= 2 }

    var qualifier: String {
        "created:\(start.formatted(.iso8601))..\(end.formatted(.iso8601))"
    }

    func halves() -> (DateWindow, DateWindow) {
        let middle = Date(timeIntervalSince1970: ((start.timeIntervalSince1970 + end.timeIntervalSince1970) / 2).rounded(.down))
        return (DateWindow(start: start, end: middle), DateWindow(start: middle, end: end))
    }
}
