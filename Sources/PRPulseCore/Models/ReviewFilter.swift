import Foundation

/// What narrows the pull requests the viewer was asked to review: who wrote them, where they live, and words in the title or
/// the branch.
public struct ReviewFilter: Equatable, Sendable {
    public var author: String?
    /// `owner/repo`.
    public var repository: String?
    public var query: String

    public init(author: String? = nil, repository: String? = nil, query: String = "") {
        self.author = author
        self.repository = repository
        self.query = query
    }

    public var isActive: Bool {
        author != nil || repository != nil || !terms.isEmpty
    }

    public func apply(to items: [ReviewItem]) -> [ReviewItem] {
        isActive ? items.filter { matches($0.pr) } : items
    }

    public func matches(_ pr: PullRequestSnapshot) -> Bool {
        if let author, pr.author.login.caseInsensitiveCompare(author) != .orderedSame { return false }
        if let repository, Self.key(of: pr).caseInsensitiveCompare(repository) != .orderedSame { return false }
        let haystack = Self.fold(pr.title + "\n" + pr.branch)
        return terms.allSatisfy { haystack.contains($0) }
    }

    /// Every word must be somewhere in the title or the branch, whatever the case or the accents.
    private var terms: [String] {
        Self.fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func key(of pr: PullRequestSnapshot) -> String {
        "\(pr.ref.owner)/\(pr.ref.repo)"
    }

    /// A value the viewer can pick, and how many pull requests have it.
    public struct Choice: Equatable, Sendable {
        public let value: String
        public let count: Int
    }

    public static func authors(in items: [ReviewItem]) -> [Choice] {
        choices(items.map(\.pr.author.login))
    }

    public static func repositories(in items: [ReviewItem]) -> [Choice] {
        choices(items.map { key(of: $0.pr) })
    }

    private static func choices(_ values: [String]) -> [Choice] {
        var counts: [String: (name: String, count: Int)] = [:]
        for value in values {
            let id = value.lowercased()
            counts[id, default: (value, 0)].count += 1
        }
        return counts.values
            .map { Choice(value: $0.name, count: $0.count) }
            .sorted { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }
    }
}
