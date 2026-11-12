import Foundation

/// Where a review is carried out: the app or the terminal of the viewer's choice. PRPulse only takes the pull request there,
/// with the words, the folder and the skill already in place.
public enum ReviewDestination: String, CaseIterable, Codable, Sendable {
    case claudeDesktop, claudeCode, codexApp, codexCLI, cursorApp, cursorAgent, custom

    public static let `default` = ReviewDestination.claudeDesktop

    /// An app is reached through a link that only fills in the message; a terminal runs the agent right away.
    public enum Style: Sendable {
        case link, terminal
    }

    public var style: Style {
        switch self {
        case .claudeDesktop, .codexApp, .cursorApp: .link
        case .claudeCode, .codexCLI, .cursorAgent, .custom: .terminal
        }
    }

    /// The agent starts on its own, so one conversation for each pull request can be opened at once.
    public var startsByItself: Bool { style == .terminal }

    /// Claude has skills the prompt can name; the others get the plain request.
    public var namesSkills: Bool { self == .claudeDesktop || self == .claudeCode }
}
