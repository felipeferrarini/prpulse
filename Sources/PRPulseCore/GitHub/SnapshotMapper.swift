import Foundation

enum SnapshotMapper {
    static func snapshot(from node: JSONObject) throws -> PullRequestSnapshot {
        guard let number = node.int("number"),
              let repo = node.object("repository"),
              let repoName = repo.string("name"),
              let owner = repo.object("owner")?.string("login"),
              let url = node.string("url").flatMap(URL.init(string:)),
              let createdAt = parseDate(node.string("createdAt"))
        else { throw GitHubError.malformed("pull request node is missing required fields") }

        return PullRequestSnapshot(
            ref: PullRequestRef(owner: owner, repo: repoName, number: number),
            title: node.string("title") ?? "",
            url: url,
            author: actor(node.object("author")),
            isDraft: node.bool("isDraft") ?? false,
            createdAt: createdAt,
            reviewDecision: reviewDecision(node.string("reviewDecision")),
            mergeable: mergeable(node.string("mergeable")),
            mergeState: mergeState(node.string("mergeStateStatus")),
            checks: .none,
            threads: threads(node.nodes("reviewThreads")),
            comments: comments(from: node) + reviewBodies(from: node),
            commits: commits(from: node),
            reviews: reviews(from: node),
            requestedReviewers: requestedReviewers(from: node)
        )
    }

    static func threadContinuation(from node: JSONObject) -> (id: String, cursor: String)? {
        guard let info = node.object("reviewThreads")?.object("pageInfo"),
              info.bool("hasNextPage") == true,
              let cursor = info.string("endCursor"),
              let id = node.string("id")
        else { return nil }
        return (id, cursor)
    }

    static func threads(_ nodes: [JSONObject]) -> [ThreadSnapshot] {
        nodes.map {
            ThreadSnapshot(
                isResolved: $0.bool("isResolved") ?? false,
                firstAuthor: actor($0.nodes("comments").first?.object("author"))
            )
        }
    }

    private static func actor(_ node: JSONObject?) -> Actor {
        guard let login = node?.string("login") else { return .ghost }
        return Actor(login: login, isBot: node?.string("__typename") == "Bot")
    }

    private static func comments(from node: JSONObject) -> [CommentSnapshot] {
        node.nodes("comments").compactMap { comment in
            guard let createdAt = parseDate(comment.string("createdAt")) else { return nil }
            return CommentSnapshot(author: actor(comment.object("author")), createdAt: createdAt, isReviewBody: false)
        }
    }

    private static func reviewBodies(from node: JSONObject) -> [CommentSnapshot] {
        node.nodes("reviews").compactMap { review in
            let body = review.string("body")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard review.string("state") != "APPROVED", !body.isEmpty, let submittedAt = parseDate(review.string("submittedAt")) else { return nil }
            return CommentSnapshot(author: actor(review.object("author")), createdAt: submittedAt, isReviewBody: true)
        }
    }

    private static func commits(from node: JSONObject) -> [CommitSnapshot] {
        node.nodes("commits").compactMap { entry in
            guard let commit = entry.object("commit"), let date = parseDate(commit.string("authoredDate")) else { return nil }
            let login = commit.object("author")?.object("user")?.string("login")
            return CommitSnapshot(authorLogin: login, authoredDate: date)
        }
    }

    private static func reviews(from node: JSONObject) -> [ReviewSnapshot] {
        node.nodes("reviews").map {
            ReviewSnapshot(
                authorLogin: actor($0.object("author")).login,
                state: reviewState($0.string("state")),
                submittedAt: parseDate($0.string("submittedAt"))
            )
        }
    }

    private static func requestedReviewers(from node: JSONObject) -> [String] {
        node.nodes("reviewRequests").compactMap { $0.object("requestedReviewer")?.string("login") }
    }

    private static func reviewDecision(_ value: String?) -> ReviewDecision? {
        switch value {
        case "APPROVED": .approved
        case "CHANGES_REQUESTED": .changesRequested
        case "REVIEW_REQUIRED": .reviewRequired
        default: nil
        }
    }

    private static func mergeable(_ value: String?) -> Mergeable {
        switch value {
        case "MERGEABLE": .mergeable
        case "CONFLICTING": .conflicting
        default: .unknown
        }
    }

    private static func mergeState(_ value: String?) -> MergeState {
        switch value {
        case "CLEAN": .clean
        case "BLOCKED": .blocked
        case "BEHIND": .behind
        case "DIRTY": .dirty
        case "UNSTABLE": .unstable
        case "DRAFT": .draft
        case "HAS_HOOKS": .hasHooks
        default: .unknown
        }
    }

    private static func reviewState(_ value: String?) -> ReviewState {
        switch value {
        case "APPROVED": .approved
        case "CHANGES_REQUESTED": .changesRequested
        case "DISMISSED": .dismissed
        case "PENDING": .pending
        default: .commented
        }
    }
}
