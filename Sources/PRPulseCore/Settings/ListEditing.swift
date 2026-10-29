import Foundation

public enum ListEditing {
    public enum Kind {
        case repository
        case account
    }

    public static func adding(_ input: String, to list: [String], kind: Kind) -> [String] {
        var result = list
        for entry in input.split(separator: ",").map({ normalized(String($0), kind: kind) }) where !entry.isEmpty {
            if !result.contains(where: { $0.caseInsensitiveCompare(entry) == .orderedSame }) { result.append(entry) }
        }
        return result
    }

    public static func removing(_ item: String, from list: [String]) -> [String] {
        list.filter { $0.caseInsensitiveCompare(item) != .orderedSame }
    }

    private static func normalized(_ raw: String, kind: Kind) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .repository:
            if let slash = text.lastIndex(of: "/") { text = String(text[text.index(after: slash)...]) }
        case .account:
            if text.hasPrefix("@") { text.removeFirst() }
            if text.hasSuffix("[bot]") { text.removeLast(5) }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
