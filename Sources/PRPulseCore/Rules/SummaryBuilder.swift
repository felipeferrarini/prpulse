import Foundation

public enum SummaryBuilder {
    public static func build(
        minePRs: [PullRequestSnapshot],
        reviewPRs: [PullRequestSnapshot],
        viewer: String,
        ignoredBots: Set<String>,
        ignoredRepos: Set<String>,
        ignoresBotComments: Bool = true,
        skipsBotPullRequests: Bool = false
    ) -> Summary {
        Summary(
            mine: mineItems(minePRs, viewer: viewer, ignoredBots: ignoredBots, ignoresBotComments: ignoresBotComments),
            review: ReviewClassifier.items(
                from: reviewPRs,
                viewer: viewer,
                ignoredRepos: ignoredRepos,
                ignoredBots: ignoredBots,
                skipsBotAuthors: skipsBotPullRequests
            )
        )
    }

    private static func mineItems(
        _ prs: [PullRequestSnapshot],
        viewer: String,
        ignoredBots: Set<String>,
        ignoresBotComments: Bool
    ) -> [MineItem] {
        let items = prs.map { pr in
            let reasons = MineClassifier.reasons(for: pr, viewer: viewer, ignoredBots: ignoredBots, ignoresBotComments: ignoresBotComments)
            return MineItem(pr: pr, reasons: reasons, quiet: MineClassifier.quietState(of: pr, viewer: viewer, ignoredBots: ignoredBots))
        }
        return ListOrder.sorted(items, by: .priority)
    }
}
