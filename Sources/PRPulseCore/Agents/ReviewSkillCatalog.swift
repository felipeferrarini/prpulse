import Foundation

/// A Claude skill that is about reviewing code.
public struct ReviewSkill: Equatable, Hashable, Sendable, Identifiable {
    public enum Source: Equatable, Hashable, Sendable {
        case personal
        case plugin(String)
    }

    public let name: String
    public let summary: String
    public let source: Source

    public var id: String { name }

    public init(name: String, summary: String, source: Source) {
        self.name = name
        self.summary = summary
        self.source = source
    }

    /// Named for reviews, as opposed to only mentioning them.
    var namesAReview: Bool { name.lowercased().contains("review") }
}

/// Finds the review skills the viewer already has under `~/.claude`, so the prompt can name one.
public enum ReviewSkillCatalog {
    /// Settings value: use the best skill found, or the generic prompt when there is none.
    public static let automaticChoice = "auto"
    /// Settings value: always use the generic prompt.
    public static let noneChoice = "none"

    private static let fileName = "SKILL.md"
    private static let maxDepth = 3

    public static func discover(home: URL, fileManager: FileManager = .default) -> [ReviewSkill] {
        let claude = home.appendingPathComponent(".claude")
        var found = skills(in: claude.appendingPathComponent("skills"), source: .personal, fileManager: fileManager)
        found += pluginSkills(in: claude.appendingPathComponent("plugins/cache"), fileManager: fileManager)

        var seen = Set<String>()
        let unique = found.filter { seen.insert($0.name).inserted }
        return unique.filter { $0.namesAReview || $0.summary.lowercased().contains("review") }.sorted(by: ranksBefore)
    }

    public static func automatic(from skills: [ReviewSkill]) -> ReviewSkill? {
        skills.first(where: \.namesAReview)
    }

    public static func resolve(choice: String, from skills: [ReviewSkill]) -> ReviewSkill? {
        switch choice {
        case automaticChoice: automatic(from: skills)
        case noneChoice: nil
        default: skills.first { $0.name == choice }
        }
    }

    /// The `name` and `description` of a skill file's front matter.
    static func frontmatter(_ text: String) -> (name: String?, description: String?) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else { return (nil, nil) }
        var values: [String: String] = [:]
        for line in lines[1 ..< end] {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon])
            let value = unquoted(String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
            if values[key] == nil, !value.isEmpty, value != ">", value != "|" { values[key] = value }
        }
        return (values["name"], values["description"])
    }

    private static func unquoted(_ text: String) -> String {
        guard text.count >= 2, let first = text.first, first == text.last, first == "\"" || first == "'" else { return text }
        return String(text.dropFirst().dropLast())
    }

    private static func ranksBefore(_ lhs: ReviewSkill, _ rhs: ReviewSkill) -> Bool {
        if lhs.namesAReview != rhs.namesAReview { return lhs.namesAReview }
        if (lhs.source == .personal) != (rhs.source == .personal) { return lhs.source == .personal }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    /// `<marketplace>/<plugin>/<version>/skills/...`, newest version first so a plugin's skill is listed once.
    private static func pluginSkills(in cache: URL, fileManager: FileManager) -> [ReviewSkill] {
        var found: [ReviewSkill] = []
        for marketplace in directories(in: cache, fileManager) {
            for plugin in directories(in: marketplace, fileManager) {
                for version in directories(in: plugin, fileManager).sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
                    found += skills(in: version.appendingPathComponent("skills"), source: .plugin(plugin.lastPathComponent), fileManager: fileManager)
                }
            }
        }
        return found
    }

    private static func skills(in folder: URL, source: ReviewSkill.Source, fileManager: FileManager, depth: Int = 1) -> [ReviewSkill] {
        var found: [ReviewSkill] = []
        for entry in directories(in: folder, fileManager) {
            let file = entry.appendingPathComponent(fileName)
            if let text = try? String(contentsOf: file, encoding: .utf8) {
                let parsed = frontmatter(text)
                found.append(ReviewSkill(name: parsed.name ?? entry.lastPathComponent, summary: parsed.description ?? "", source: source))
            } else if depth < maxDepth {
                found += skills(in: entry, source: source, fileManager: fileManager, depth: depth + 1)
            }
        }
        return found
    }

    private static func directories(in folder: URL, _ fileManager: FileManager) -> [URL] {
        let entries = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
