/// How a set of pull requests is written out when it is copied or shared, so it reads well where it lands.
public enum LinkFormat: String, CaseIterable, Sendable {
    /// The addresses only, one per line: chat apps turn each one into a preview.
    case links
    /// The title and where it lives, with the address under it.
    case titled
    /// A list of links with the title as their text, for places that read Markdown.
    case markdown

    public func text(for pullRequests: [PullRequestSnapshot]) -> String {
        switch self {
        case .links:
            pullRequests.map { $0.url.absoluteString }.joined(separator: "\n")
        case .titled:
            pullRequests.map { "\(Self.name(of: $0))\n\($0.url.absoluteString)" }.joined(separator: "\n\n")
        case .markdown:
            pullRequests.map { "- [\(Self.name(of: $0))](\($0.url.absoluteString))" }.joined(separator: "\n")
        }
    }

    private static func name(of pr: PullRequestSnapshot) -> String {
        "\(pr.title) (\(pr.ref.repo)#\(pr.ref.number))"
    }
}
