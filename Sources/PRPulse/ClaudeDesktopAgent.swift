import AppKit
import PRPulseCore

enum AgentError: Error {
    case invalidRequest
    case couldNotOpen
}

/// Claude Desktop, reached through its `claude://` address: the review shows up there as a new Code session.
struct ClaudeDesktopAgent: ReviewAgent {
    let id = "claude-desktop"
    let title = "Claude Desktop"

    private static let probe = URL(string: "claude://code/new")!

    func availability() -> AgentAvailability {
        NSWorkspace.shared.urlForApplication(toOpen: Self.probe) == nil ? .notInstalled : .ready
    }

    @MainActor func launch(_ launch: AgentLaunch) throws {
        guard let url = ClaudeDesktopLink.newSession(prompt: launch.prompt, folder: launch.folder) else { throw AgentError.invalidRequest }
        guard NSWorkspace.shared.open(url) else { throw AgentError.couldNotOpen }
    }
}
