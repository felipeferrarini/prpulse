import Foundation

public enum TokenFormat {
    private static let prefixes = ["ghp_", "github_pat_", "gho_", "ghu_"]

    /// Whether the text looks like a GitHub token, so a paste of anything else is not taken for one.
    public static func looksLikeToken(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.count >= 20
            && prefixes.contains { value.hasPrefix($0) }
            && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }

    /// The token page with the scopes the app needs already ticked.
    public static let creationURL = URL(string: "https://github.com/settings/tokens/new?scopes=repo,read:org&description=PRPulse")!
}
