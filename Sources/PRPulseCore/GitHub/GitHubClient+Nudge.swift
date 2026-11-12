import Foundation

extension GitHubClient: PullRequestNudger {
    /// Asks the reviewer for a new review, then leaves the comment that carries the nudge. A refused review request does not
    /// stop the comment: the reviewer still gets it.
    public func nudge(_ request: NudgeRequest) async throws -> NudgeOutcome {
        let targets = try await execute(Queries.nudgeTargets, [
            "owner": request.ref.owner, "repo": request.ref.repo, "number": request.ref.number, "login": request.reviewer,
        ])
        guard let pullRequestID = targets.object("repository")?.object("pullRequest")?.string("id"),
              let reviewerID = targets.object("user")?.string("id")
        else { throw ProviderError.malformed("pull request or reviewer not found") }

        let requested = request.kind == .merge ? true : try await requestReview(of: pullRequestID, from: reviewerID)

        let body = NudgeCodec.body(
            text: request.text,
            recipient: request.reviewer,
            id: UUID().uuidString.lowercased(),
            tone: request.tone,
            message: request.message,
            kind: request.kind
        )
        _ = try await mutate(Queries.addComment, ["subject": pullRequestID, "body": body])
        return requested ? .sent : .commentOnly
    }

    /// False when the host refuses: the comment is still worth leaving.
    private func requestReview(of pullRequestID: String, from reviewerID: String) async throws -> Bool {
        do {
            _ = try await mutate(Queries.requestReviews, ["pullRequest": pullRequestID, "users": [reviewerID]])
            return true
        } catch ProviderError.rateLimited(let retryAfter) {
            throw ProviderError.rateLimited(retryAfter: retryAfter)
        } catch {
            return false
        }
    }
}
