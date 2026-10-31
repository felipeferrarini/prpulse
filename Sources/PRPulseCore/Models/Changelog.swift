import Foundation

public struct ChangelogSection: Equatable, Sendable {
    /// `Added`, `Changed`, `Fixed`… as written in the file.
    public let title: String
    public let items: [String]

    public init(title: String, items: [String]) {
        self.title = title
        self.items = items
    }
}

public struct ChangelogRelease: Equatable, Identifiable, Sendable {
    public let version: String
    public let date: String?
    public let sections: [ChangelogSection]

    public var id: String { version }

    public init(version: String, date: String?, sections: [ChangelogSection]) {
        self.version = version
        self.date = date
        self.sections = sections
    }
}

/// Reads a changelog in the Keep a Changelog format: `## [1.2.0] - 2026-10-30`, then `### Added`, then `- ` items.
public enum Changelog {
    public static func parse(_ markdown: String) -> [ChangelogRelease] {
        var reader = Reader()
        for line in markdown.components(separatedBy: .newlines) { reader.read(line) }
        return reader.finish()
    }

    private struct Reader {
        private var releases: [ChangelogRelease] = []
        private var version: String?
        private var date: String?
        private var sections: [ChangelogSection] = []
        private var title: String?
        private var items: [String] = []

        mutating func read(_ line: String) {
            if line.hasPrefix("## ") {
                closeRelease()
                (version, date) = Self.heading(String(line.dropFirst(3)))
            } else if line.hasPrefix("### ") {
                closeSection()
                title = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("- ") {
                items.append(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            } else if line.hasPrefix(" "), !items.isEmpty, !line.trimmingCharacters(in: .whitespaces).isEmpty {
                items[items.count - 1] += " " + line.trimmingCharacters(in: .whitespaces)
            }
        }

        mutating func finish() -> [ChangelogRelease] {
            closeRelease()
            return releases
        }

        private mutating func closeSection() {
            if let title, !items.isEmpty { sections.append(ChangelogSection(title: title, items: items)) }
            title = nil
            items = []
        }

        /// A release that is still being written (`Unreleased`) is not news yet.
        private mutating func closeRelease() {
            closeSection()
            if let version, version.lowercased() != "unreleased", !sections.isEmpty {
                releases.append(ChangelogRelease(version: version, date: date, sections: sections))
            }
            version = nil
            date = nil
            sections = []
        }

        /// `[0.6.0] - 2026-10-30` gives `0.6.0` and `2026-10-30`.
        private static func heading(_ text: String) -> (String?, String?) {
            guard text.hasPrefix("["), let close = text.firstIndex(of: "]") else { return (nil, nil) }
            let version = String(text[text.index(after: text.startIndex) ..< close])
            let rest = text[text.index(after: close)...].trimmingCharacters(in: CharacterSet(charactersIn: " -"))
            return (version, rest.isEmpty ? nil : rest)
        }
    }
}
