import Foundation

/// Why a reviewer cannot be nudged right now.
public enum NudgeBlock: Equatable, Sendable {
    /// Nothing was pushed since the reviewer last took part, so there is nothing new to look at.
    case noNewCommits
    case tooSoon(until: Date)
    case limitReached
}

public struct NudgeCandidate: Equatable, Identifiable, Sendable {
    public let login: String
    /// The tone the next nudge to this reviewer would have.
    public let tone: Int
    public let block: NudgeBlock?

    public var id: String { login }
    public var isAllowed: Bool { block == nil }

    public init(login: String, tone: Int, block: NudgeBlock?) {
        self.login = login
        self.tone = tone
        self.block = block
    }
}

/// Who the author of a pull request may nudge: people who took part in it, once there is something new for them to read.
public enum NudgeEligibility {
    public static let minimumInterval: TimeInterval = 3 * 3600
    public static let maxNudges = NudgeCodec.maxTone

    public static func candidates(
        for pr: PullRequestSnapshot,
        viewer: String,
        ignoredBots: Set<String>,
        now: Date
    ) -> [NudgeCandidate] {
        guard !pr.isDraft, pr.author.isSame(as: viewer) else { return [] }
        let bots = Set(ignoredBots.map { $0.lowercased() })
        return participants(of: pr, viewer: viewer, bots: bots).map { login in
            let sent = pr.nudges.filter { $0.recipient.caseInsensitiveCompare(login) == .orderedSame && $0.author.isSame(as: viewer) }
            return NudgeCandidate(
                login: login,
                tone: min(sent.count + 1, NudgeCodec.maxTone),
                block: block(for: login, in: pr, sent: sent, now: now)
            )
        }
    }

    /// Whoever reviewed with comments or changes, or commented, in the order they first appear.
    private static func participants(of pr: PullRequestSnapshot, viewer: String, bots: Set<String>) -> [String] {
        let reviewers = pr.reviews
            .filter { $0.state == .commented || $0.state == .changesRequested }
            .map(\.authorLogin)
        let commenters = pr.comments.filter { !$0.author.isBot }.map(\.author.login)
        var seen = Set<String>()
        return (reviewers + commenters).filter { login in
            !login.isEmpty
                && login.caseInsensitiveCompare(viewer) != .orderedSame
                && !bots.contains(login.lowercased())
                && seen.insert(login.lowercased()).inserted
        }
    }

    private static func block(for login: String, in pr: PullRequestSnapshot, sent: [NudgeSnapshot], now: Date) -> NudgeBlock? {
        if sent.count >= maxNudges { return .limitReached }
        if let last = sent.map(\.createdAt).max(), now < last.addingTimeInterval(minimumInterval) {
            return .tooSoon(until: last.addingTimeInterval(minimumInterval))
        }
        guard let activity = lastActivity(of: login, in: pr) else { return .noNewCommits }
        let pushed = pr.commits.contains {
            $0.authoredDate > activity && $0.authorLogin?.caseInsensitiveCompare(login) != .orderedSame
        }
        return pushed ? nil : .noNewCommits
    }

    private static func lastActivity(of login: String, in pr: PullRequestSnapshot) -> Date? {
        let reviewed = pr.reviews
            .filter { $0.authorLogin.caseInsensitiveCompare(login) == .orderedSame && $0.state != .pending && $0.state != .dismissed }
            .compactMap(\.submittedAt)
        let commented = pr.comments.filter { $0.author.isSame(as: login) }.map(\.createdAt)
        return (reviewed + commented).max()
    }
}
