import Foundation

public enum ListEditing {
    public enum Kind {
        case repository
        case account
    }

    /// Repositories are kept as `owner/name`; a bare name belongs to `owner`.
    public static func adding(_ input: String, to list: [String], kind: Kind, owner: String? = nil) -> [String] {
        var result = list
        for entry in input.split(separator: ",").map({ normalized(String($0), kind: kind, owner: owner) }) where !entry.isEmpty {
            if !result.contains(where: { $0.caseInsensitiveCompare(entry) == .orderedSame }) { result.append(entry) }
        }
        return result
    }

    public static func removing(_ item: String, from list: [String]) -> [String] {
        list.filter { $0.caseInsensitiveCompare(item) != .orderedSame }
    }

    private static func normalized(_ raw: String, kind: Kind, owner: String?) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .repository:
            if !text.isEmpty, !text.contains("/"), let owner { text = "\(owner)/\(text)" }
        case .account:
            if text.hasPrefix("@") { text.removeFirst() }
            if text.hasSuffix("[bot]") { text.removeLast(5) }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
