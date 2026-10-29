public enum SummaryBuilder {
    public static func build(
        minePRs: [PullRequestSnapshot],
        reviewPRs: [PullRequestSnapshot],
        viewer: String,
        ignoredBots: Set<String>,
        ignoredRepos: Set<String>
    ) -> Summary {
        Summary(
            mine: mineItems(minePRs, viewer: viewer, ignoredBots: ignoredBots),
            review: ReviewClassifier.items(from: reviewPRs, viewer: viewer, ignoredRepos: ignoredRepos)
        )
    }

    private static func mineItems(
        _ prs: [PullRequestSnapshot],
        viewer: String,
        ignoredBots: Set<String>
    ) -> [MineItem] {
        prs
            .map { MineItem(pr: $0, reasons: MineClassifier.reasons(for: $0, viewer: viewer, ignoredBots: ignoredBots)) }
            .filter { !$0.reasons.isEmpty }
            .sorted { a, b in
                if a.primary.urgencyRank != b.primary.urgencyRank { return a.primary.urgencyRank < b.primary.urgencyRank }
                return a.pr.createdAt < b.pr.createdAt
            }
    }
}
