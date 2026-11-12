import Foundation

/// Why somebody cannot be nudged right now.
public enum NudgeBlock: Equatable, Sendable {
    /// Nothing was pushed since they last took part, so there is nothing new to look at.
    case noNewCommits
    case tooSoon(until: Date)
    case limitReached
}

public struct NudgeCandidate: Equatable, Identifiable, Sendable {
    public let login: String
    /// The tone the next nudge to them would have.
    public let tone: Int
    public let block: NudgeBlock?
    public let kind: NudgeKind

    public var id: String { login }
    public var isAllowed: Bool { block == nil }

    public init(login: String, tone: Int, block: NudgeBlock?, kind: NudgeKind = .review) {
        self.login = login
        self.tone = tone
        self.block = block
        self.kind = kind
    }
}

/// Who the viewer may nudge about a pull request.
///
/// On the viewer's own pull request, to review it: anyone on the team who has not reviewed it while it still lacks reviews,
/// and whoever took part in it once there is something new to read. On the pull request of someone else, to merge it: its
/// author, once the viewer reviewed it and it has the reviews it needs. Each person can be nudged up to `maxNudges` times
/// about each pull request, `minimumInterval` apart, each time louder, while what they were nudged about stays undone.
public enum NudgeEligibility {
    public static let minimumInterval: TimeInterval = 3 * 3600
    public static let maxNudges = NudgeCodec.maxTone

    public static func candidates(
        for pr: PullRequestSnapshot,
        viewer: String,
        team: [String] = [],
        ignoredBots: Set<String>,
        now: Date
    ) -> [NudgeCandidate] {
        let bots = Set(ignoredBots.map { $0.lowercased() })
        if pr.author.isSame(as: viewer) { return reviewCandidates(for: pr, viewer: viewer, team: team, bots: bots, now: now) }
        return mergeCandidate(for: pr, viewer: viewer, bots: bots, now: now).map { [$0] } ?? []
    }

    // MARK: To review

    private static func reviewCandidates(for pr: PullRequestSnapshot, viewer: String, team: [String], bots: Set<String>, now: Date) -> [NudgeCandidate] {
        guard !pr.isDraft else { return [] }
        let involved = participants(of: pr, viewer: viewer, bots: bots)
        let lacksReviews = !MinimumReviews.isMet(pr)
        return people(of: pr, involved: involved, team: team, viewer: viewer, bots: bots).compactMap { login in
            let canBeAsked = lacksReviews && !hasReviewed(login, in: pr)
            let tookPart = involved.contains { $0.caseInsensitiveCompare(login) == .orderedSame }
            guard canBeAsked || tookPart else { return nil }
            let sent = nudges(from: viewer, to: login, kind: .review, in: pr)
            let block = limit(sent, now: now) ?? (canBeAsked ? nil : staleness(of: login, in: pr))
            return NudgeCandidate(login: login, tone: nextTone(sent), block: block)
        }
    }

    /// Those asked for a review first, then those who took part, then the rest of the team, each in alphabetical order.
    private static func people(of pr: PullRequestSnapshot, involved: [String], team: [String], viewer: String, bots: Set<String>) -> [String] {
        var seen = Set<String>()
        let everyone = (pr.requestedReviewers + involved + team).filter { login in
            !login.isEmpty
                && login.caseInsensitiveCompare(viewer) != .orderedSame
                && !bots.contains(login.lowercased())
                && !login.hasSuffix("[bot]")
                && seen.insert(login.lowercased()).inserted
        }
        func rank(_ login: String) -> Int {
            if pr.requestedReviewers.contains(where: { $0.caseInsensitiveCompare(login) == .orderedSame }) { return 0 }
            return involved.contains { $0.caseInsensitiveCompare(login) == .orderedSame } ? 1 : 2
        }
        return everyone.sorted { a, b in
            rank(a) != rank(b) ? rank(a) < rank(b) : a.localizedCaseInsensitiveCompare(b) == .orderedAscending
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

    private static func hasReviewed(_ login: String, in pr: PullRequestSnapshot) -> Bool {
        MinimumReviews.latestState(of: login, in: pr) != nil
    }

    private static func staleness(of login: String, in pr: PullRequestSnapshot) -> NudgeBlock? {
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

    // MARK: To merge

    /// The author of a pull request the viewer reviewed, once it has the reviews it needs.
    private static func mergeCandidate(for pr: PullRequestSnapshot, viewer: String, bots: Set<String>, now: Date) -> NudgeCandidate? {
        guard !pr.isDraft, !pr.author.isBot, !bots.contains(pr.author.login.lowercased()) else { return nil }
        guard hasReviewed(viewer, in: pr), MinimumReviews.isMet(pr, countingApprovalOf: viewer) else { return nil }
        let sent = nudges(from: viewer, to: pr.author.login, kind: .merge, in: pr)
        return NudgeCandidate(login: pr.author.login, tone: nextTone(sent), block: limit(sent, now: now), kind: .merge)
    }

    // MARK: Limits

    private static func nudges(from sender: String, to login: String, kind: NudgeKind, in pr: PullRequestSnapshot) -> [NudgeSnapshot] {
        pr.nudges.filter {
            $0.kind == kind && $0.recipient.caseInsensitiveCompare(login) == .orderedSame && $0.author.isSame(as: sender)
        }
    }

    private static func nextTone(_ sent: [NudgeSnapshot]) -> Int {
        min(sent.count + 1, NudgeCodec.maxTone)
    }

    private static func limit(_ sent: [NudgeSnapshot], now: Date) -> NudgeBlock? {
        if sent.count >= maxNudges { return .limitReached }
        if let last = sent.map(\.createdAt).max(), now < last.addingTimeInterval(minimumInterval) {
            return .tooSoon(until: last.addingTimeInterval(minimumInterval))
        }
        return nil
    }
}
