import Foundation

public enum MineClassifier {
    public static func reasons(
        for pr: PullRequestSnapshot,
        viewer: String,
        ignoredBots: Set<String>,
        ignoresBotComments: Bool = true
    ) -> [MineReason] {
        let ignored = BotFilter(names: Set(ignoredBots.map { $0.lowercased() }), isOn: ignoresBotComments)
        var found: [MineReason] = []

        if pr.reviewDecision == .changesRequested { found.append(.changesRequested) }
        let threads = openThreadCount(pr, ignored: ignored)
        if threads > 0 { found.append(.openThreads(threads)) }
        if hasUnansweredComment(pr, viewer: viewer, ignored: ignored) { found.append(.unansweredComment) }
        if !pr.isDraft { found.append(contentsOf: workflowReasons(pr)) }

        return found.sorted { $0.urgencyRank < $1.urgencyRank }
    }

    private static func workflowReasons(_ pr: PullRequestSnapshot) -> [MineReason] {
        var found: [MineReason] = []
        if pr.checks == .failing { found.append(.ciFailed) }
        if pr.mergeable == .conflicting { found.append(.conflict) }
        if pr.mergeState == .clean { found.append(.readyToMerge) }
        return found
    }

    /// Who counts as a bot when comments are read: accounts GitHub marks as bots and the ones the viewer listed.
    private struct BotFilter {
        let names: Set<String>
        let isOn: Bool

        func ignores(_ actor: Actor) -> Bool {
            isOn && (actor.isBot || names.contains(actor.login.lowercased()))
        }
    }

    private static func isIgnored(_ actor: Actor, ignored: BotFilter) -> Bool {
        ignored.ignores(actor)
    }

    private static func openThreadCount(_ pr: PullRequestSnapshot, ignored: BotFilter) -> Int {
        pr.threads.filter { !$0.isResolved && !isIgnored($0.firstAuthor, ignored: ignored) }.count
    }

    private static func hasUnansweredComment(
        _ pr: PullRequestSnapshot,
        viewer: String,
        ignored: BotFilter
    ) -> Bool {
        let fromOthers = pr.comments.filter { !$0.author.isSame(as: viewer) && !isIgnored($0.author, ignored: ignored) }
        guard let lastOther = fromOthers.map(\.createdAt).max() else { return false }
        guard let lastMine = lastViewerActivity(pr, viewer: viewer) else { return true }
        return lastOther > lastMine
    }

    private static func lastViewerActivity(_ pr: PullRequestSnapshot, viewer: String) -> Date? {
        let commitDates = pr.commits
            .filter { $0.authorLogin?.caseInsensitiveCompare(viewer) == .orderedSame }
            .map(\.authoredDate)
        let commentDates = pr.comments.filter { $0.author.isSame(as: viewer) }.map(\.createdAt)
        return (commitDates + commentDates).max()
    }
}
