import Foundation

/// The address that starts a new Code session in Claude Desktop.
public enum ClaudeDesktopLink {
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// `nil` when there is nothing to say, or when the prompt starts with a slash: Claude Desktop refuses those, since
    /// a link must not be able to run a command.
    public static func newSession(prompt: String, folder: URL?) -> URL? {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.hasPrefix("/") else { return nil }
        var address = "claude://code/new?q=\(encode(text))"
        if let folder { address += "&folder=\(encode(folder.path))" }
        return URL(string: address)
    }

    private static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }
}
