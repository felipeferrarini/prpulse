enum PRFragment {
    case mine, review
}

enum Queries {
    static let viewer = """
    query { viewer { login organizations(first: 100) { nodes { login } } } }
    """

    static let organization = """
    query($login: String!) { organization(login: $login) { login } }
    """

    static let reviewThreadsPage = """
    query($id: ID!, $after: String) {
      node(id: $id) {
        ... on PullRequest {
          reviewThreads(first: 100, after: $after) {
            pageInfo { hasNextPage endCursor }
            nodes { isResolved comments(first: 1) { nodes { author { login __typename } } } }
          }
        }
      }
    }
    """

    static func search(_ fragment: PRFragment) -> String {
        """
        query($q: String!, $first: Int!, $after: String) {
          search(query: $q, type: ISSUE, first: $first, after: $after) {
            issueCount
            pageInfo { hasNextPage endCursor }
            nodes { ... on PullRequest { \(fields(fragment)) } }
          }
        }
        """
    }

    static func checks(for refs: [PullRequestRef]) -> String {
        let aliases = refs.enumerated().map { index, ref in
            """
            pr\(index): repository(owner: "\(escaped(ref.owner))", name: "\(escaped(ref.repo))") {
              pullRequest(number: \(ref.number)) {
                commits(last: 1) { nodes { commit { statusCheckRollup {
                  state
                  contexts(first: 100) { nodes {
                    __typename
                    ... on CheckRun { conclusion status isRequired(pullRequestNumber: \(ref.number)) }
                    ... on StatusContext { state isRequired(pullRequestNumber: \(ref.number)) }
                  } }
                } } } }
              }
            }
            """
        }
        return "query {\n\(aliases.joined(separator: "\n"))\n}"
    }

    private static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static let identity = """
    number title url isDraft createdAt
    repository { name owner { login } }
    author { login __typename }
    reviewRequests(first: 20) { nodes { requestedReviewer { ... on User { login } } } }
    """

    private static func fields(_ fragment: PRFragment) -> String {
        switch fragment {
        case .mine:
            identity + """

            id reviewDecision mergeable mergeStateStatus
            reviewThreads(first: 100) {
              pageInfo { hasNextPage endCursor }
              nodes { isResolved comments(first: 1) { nodes { author { login __typename } } } }
            }
            comments(last: 50) { nodes { createdAt author { login __typename } } }
            reviews(last: 50) { nodes { state body submittedAt author { login __typename } } }
            commits(last: 100) { nodes { commit { authoredDate author { user { login } } } } }
            """
        case .review:
            identity + """

            reviews(last: 50) { nodes { state submittedAt author { login __typename } } }
            """
        }
    }
}
