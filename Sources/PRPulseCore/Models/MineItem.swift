public struct MineItem: Equatable, Sendable {
    public let pr: PullRequestSnapshot
    public let reasons: [MineReason]

    public init(pr: PullRequestSnapshot, reasons: [MineReason]) {
        self.pr = pr
        self.reasons = reasons
    }

    public var primary: MineReason { reasons[0] }
}
