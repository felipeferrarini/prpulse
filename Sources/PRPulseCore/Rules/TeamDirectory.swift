import Foundation

/// The people PRPulse knows the viewer works with: whoever shows up in the pull requests it has fetched. There is no list of
/// members to ask for, so this is the team.
public enum TeamDirectory {
    public static func members(in summary: Summary, viewer: String, ignoredBots: Set<String>) -> [String] {
        let bots = Set(ignoredBots.map { $0.lowercased() })
        var names: [String] = []
        for item in summary.review {
            names.append(item.pr.author.login)
            names += item.pr.requestedReviewers + item.pr.reviews.map(\.authorLogin)
        }
        for item in summary.mine {
            names += item.pr.requestedReviewers + item.pr.reviews.map(\.authorLogin)
            names += item.pr.comments.filter { !$0.author.isBot }.map(\.author.login)
        }
        var seen = Set<String>()
        return names.filter { login in
            !login.isEmpty
                && login.caseInsensitiveCompare(viewer) != .orderedSame
                && !bots.contains(login.lowercased())
                && !login.hasSuffix("[bot]")
                && seen.insert(login.lowercased()).inserted
        }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
