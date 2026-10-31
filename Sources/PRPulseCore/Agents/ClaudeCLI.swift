import Foundation

/// The Claude Code command line on this Mac, used to review in the background.
public enum ClaudeCLI {
    public static let candidatePaths = [".local/bin/claude", ".claude/local/claude", ".npm-global/bin/claude", ".bun/bin/claude"]
    public static let systemPaths = ["/opt/homebrew/bin/claude", "/usr/local/bin/claude", "/usr/bin/claude"]

    /// Read-only: the agent can look at the code and at the pull request, and nothing else.
    public static let readOnlyTools = [
        "Read", "Grep", "Glob", "Skill", "Task",
        "Bash(gh pr view:*)", "Bash(gh pr diff:*)", "Bash(gh pr checks:*)", "Bash(gh pr list:*)",
        "Bash(git log:*)", "Bash(git diff:*)", "Bash(git show:*)", "Bash(git status:*)", "Bash(git blame:*)", "Bash(git ls-files:*)",
    ]

    public static func locate(home: URL, fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> URL? {
        let paths = candidatePaths.map { home.appendingPathComponent($0).path } + systemPaths
        return paths.first(where: fileExists).map { URL(fileURLWithPath: $0) }
    }

    /// What a review never does in the automatic mode, whatever Claude's classifier decides: change files, the checkout or git
    /// history, or write to GitHub. A rule by command only catches the plain forms, so the settings below say the same in words.
    public static let neverAllowedTools = [
        "Edit", "Write", "MultiEdit", "NotebookEdit",
        "Bash(rm:*)", "Bash(mv:*)",
        "Bash(git push:*)", "Bash(git commit:*)", "Bash(git reset:*)", "Bash(git clean:*)", "Bash(git checkout:*)", "Bash(git switch:*)",
        "Bash(git restore:*)", "Bash(git stash:*)", "Bash(git merge:*)", "Bash(git rebase:*)", "Bash(git pull:*)",
        "Bash(git cherry-pick:*)", "Bash(git apply:*)",
        "Bash(gh pr checkout:*)", "Bash(gh pr comment:*)", "Bash(gh pr review:*)", "Bash(gh pr merge:*)", "Bash(gh pr close:*)",
        "Bash(gh pr edit:*)", "Bash(gh api:*)",
    ]

    /// Where nothing in a sandboxed command may read: the keys and credentials of this Mac that a pull request has no business with.
    public static let unreadablePaths = ["~/.ssh", "~/.aws", "~/.gnupg"]

    /// Settings for one run in the automatic mode, as JSON for `--settings`. Two layers, because the classifier alone let a shell
    /// redirect write a file: a sandbox that makes the folder read-only to every command and lets them reach GitHub and nothing
    /// else, and what the classifier is told about this session (`$defaults` keeps Claude's own rules).
    public static func automaticSettings(folder: String) -> String {
        let settings: [String: Any] = [
            "sandbox": [
                "enabled": true,
                "failIfUnavailable": true,
                "allowUnsandboxedCommands": false,
                "enableWeakerNetworkIsolation": true,
                "network": ["allowedDomains": ["api.github.com", "github.com"]],
                "filesystem": ["denyWrite": [folder], "denyRead": unreadablePaths],
            ],
            "autoMode": [
                "environment": [
                    "$defaults",
                    "This session is a read-only review of a pull request. Reading the code and the pull request is expected. Changing anything is not.",
                ],
                "hard_deny": [
                    "$defaults",
                    "Creating, editing, moving or deleting files in any repository, by any command or redirection",
                    "Changing the checkout or the git history: commit, push, reset, checkout, switch, stash, merge, rebase, pull, cherry-pick",
                    "Writing to GitHub: commenting, reviewing, approving, merging or closing, including through gh api",
                ],
            ],
        ]
        let data = (try? JSONSerialization.data(withJSONObject: settings, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// What every run has in common. Messages go in as JSON lines through standard input, so nothing the viewer or a pull
    /// request writes can pass for an option. A tool outside `readOnlyTools` is not run on its own: in the automatic mode Claude's
    /// classifier decides, inside the limits above; otherwise the agent asks and the viewer answers.
    private static func conversation(_ approval: ReviewApproval, folder: String) -> [String] {
        let mode: [String] = switch approval {
        case .ask: ["--permission-mode", "default"]
        case .automatic: ["--permission-mode", "auto", "--disallowedTools", neverAllowedTools.joined(separator: ","), "--settings", automaticSettings(folder: folder)]
        }
        return ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose"]
            + mode
            + ["--permission-prompt-tool", "stdio", "--allowedTools", readOnlyTools.joined(separator: ",")]
    }

    /// Arguments for a review that works in `folder`.
    public static func reviewArguments(sessionID: UUID, name: String, folder: String, approval: ReviewApproval = .automatic) -> [String] {
        conversation(approval, folder: folder) + ["--session-id", sessionID.uuidString.lowercased(), "--name", name]
    }

    /// Arguments to talk again with a review whose process is gone.
    public static func resumeArguments(sessionID: String, folder: String, approval: ReviewApproval = .automatic) -> [String] {
        conversation(approval, folder: folder) + ["--resume", sessionID]
    }

    /// Where `PATH` points for the agent: a Mac app is not started from a shell, so `gh` and `git` would not be found.
    public static func environmentPath(home: URL, current: String?) -> String {
        let extra = [home.appendingPathComponent(".local/bin").path, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        let existing = (current ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        return (extra + existing).filter { seen.insert($0).inserted }.joined(separator: ":")
    }

    /// The environment the agent runs in: this app's, with a `PATH` that finds the tools.
    public static func environment(home: URL, current: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var environment = current
        environment["PATH"] = environmentPath(home: home, current: current["PATH"])
        return environment
    }

    public enum Login: Equatable, Sendable {
        case signedIn(account: String?)
        case signedOut
    }

    /// The answer of `claude auth status`.
    public static func login(fromStatus output: String) -> Login {
        guard let data = output.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["loggedIn"] as? Bool == true else { return .signedOut }
        return .signedIn(account: object["email"] as? String)
    }

    /// What to say to continue a review in Claude Desktop, where a link can only carry text.
    public static func continuationPrompt(url: URL, review: String, limit: Int = 6000) -> String {
        let text = review.count > limit ? String(review.prefix(limit)) + "\n[…]" : review
        return "I asked for a review of this pull request: \(url.absoluteString)\nThis is what it said:\n\n\(text)\n\nLet's go through the points together. Start with the most serious one."
    }

    /// A script Terminal opens to pick a review up again where it was.
    public static func resumeScript(cli: URL, folder: String, sessionID: String) -> String {
        "#!/bin/zsh\ncd \(quoted(folder)) && \(quoted(cli.path)) --resume \(quoted(sessionID))\n"
    }

    private static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
