import Foundation

/// What opening a review means, decided here and carried out by the app.
public enum ReviewLaunch: Equatable, Sendable {
    /// A link the destination's app handles.
    case open(URL)
    /// Cursor takes a message without a folder, so its window is opened on the folder first and the link comes after.
    case openFolderThenLink(folder: URL, link: URL)
    /// A script a terminal runs.
    case terminal(script: String)
}

public enum ReviewLaunchError: Error, Equatable, Sendable {
    case emptyPrompt
    /// A message that starts with a slash could run a command in the app, so no link carries one.
    case slashPrompt
    case tooLong
    case missingCommand
}

public enum ReviewLauncher {
    /// What a link can carry, in characters of the whole address: Cursor's is the smallest, and Claude cuts its message at about 14,000.
    public static let maxLinkLength = 8000

    /// `cliMissing` is what a terminal says when the command is not installed.
    public static func plan(
        for destination: ReviewDestination,
        prompt: String,
        folder: URL?,
        request: ReviewRequest,
        customCommand: String = "",
        cliMissing: (String) -> String = { "\($0) was not found" }
    ) throws -> ReviewLaunch {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ReviewLaunchError.emptyPrompt }
        switch destination {
        case .claudeDesktop:
            return .open(try checked(ClaudeDesktopLink.newSession(prompt: text, folder: folder), text))
        case .codexApp:
            return .open(try checked(AppLinks.codex(prompt: text, folder: folder), text))
        case .cursorApp:
            let link = try checked(AppLinks.cursor(prompt: text), text)
            return folder.map { .openFolderThenLink(folder: $0, link: link) } ?? .open(link)
        case .claudeCode:
            return .terminal(script: TerminalScript.make(folder: folder, command: .program("claude", fallback: nil, prompt: text), cliMissing: cliMissing))
        case .codexCLI:
            return .terminal(script: TerminalScript.make(folder: folder, command: .program("codex", fallback: nil, prompt: text), cliMissing: cliMissing))
        case .cursorAgent:
            return .terminal(script: TerminalScript.make(folder: folder, command: .program("agent", fallback: "cursor-agent", prompt: text), cliMissing: cliMissing))
        case .custom:
            let line = CustomCommand.render(customCommand, prompt: text, request: request, folder: folder)
            guard let line else { throw ReviewLaunchError.missingCommand }
            return .terminal(script: TerminalScript.make(folder: folder, command: .line(line), cliMissing: cliMissing))
        }
    }

    private static func checked(_ link: URL?, _ prompt: String) throws -> URL {
        guard !prompt.hasPrefix("/") else { throw ReviewLaunchError.slashPrompt }
        guard let link else { throw ReviewLaunchError.emptyPrompt }
        guard link.absoluteString.count <= maxLinkLength else { throw ReviewLaunchError.tooLong }
        return link
    }
}

/// The addresses that open a new conversation in the apps that have one.
public enum AppLinks {
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// A new Codex chat with the text in the box and the folder as its workspace. Nothing is sent until the viewer sends it.
    public static func codex(prompt: String, folder: URL?) -> URL? {
        var address = "codex://threads/new?prompt=\(encode(prompt))"
        if let folder { address += "&path=\(encode(folder.path))" }
        return URL(string: address)
    }

    /// Cursor has no folder in its link: it opens the text in the window that has focus.
    public static func cursor(prompt: String) -> URL? {
        URL(string: "cursor://anysphere.cursor-deeplink/prompt?text=\(encode(prompt))")
    }

    static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }
}

/// The command of a destination that is not one of the known ones, with what the viewer chose filled in.
public enum CustomCommand {
    public static let placeholders = ["{prompt}", "{url}", "{urls}", "{repo}", "{number}", "{folder}"]

    private static let token = try! NSRegularExpression(pattern: #"\{(prompt|urls|url|repo|number|folder)\}"#)

    /// Every value goes in as one quoted word, so what a pull request or a folder name holds cannot become part of the command.
    /// A command without `{prompt}` gets the prompt at its end. Nil when there is no command.
    public static func render(_ template: String, prompt: String, request: ReviewRequest, folder: URL?) -> String? {
        let text = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let values = [
            "prompt": prompt,
            "url": request.url.absoluteString,
            "urls": request.targets.map(\.url.absoluteString).joined(separator: "\n"),
            "repo": "\(request.ref.owner)/\(request.ref.repo)",
            "number": String(request.ref.number),
            "folder": folder?.path ?? "",
        ]
        var result = ""
        var cursor = text.startIndex
        for match in token.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let whole = Range(match.range, in: text), let name = Range(match.range(at: 1), in: text) else { continue }
            result += text[cursor ..< whole.lowerBound]
            result += TerminalScript.quoted(values[String(text[name])] ?? "")
            cursor = whole.upperBound
        }
        result += text[cursor...]
        return text.contains("{prompt}") ? result : result + " " + TerminalScript.quoted(prompt)
    }
}

/// The script a terminal opens to run the agent in the repository's folder.
public enum TerminalScript {
    public enum Command: Equatable, Sendable {
        case program(String, fallback: String?, prompt: String)
        case line(String)
    }

    /// A login shell, so the `PATH` is the one the viewer works with in a terminal: a Mac app is not started from one.
    public static func make(folder: URL?, command: Command, cliMissing: (String) -> String) -> String {
        var lines = ["#!/bin/zsh -il"]
        if let folder { lines.append("cd \(quoted(folder.path)) || exit 1") }
        switch command {
        case let .program(name, fallback, prompt):
            let found = fallback.map { "command -v \($0) >/dev/null 2>&1" }
            let missing = quoted(cliMissing(fallback.map { "\(name) or \($0)" } ?? name))
            var check = "if command -v \(name) >/dev/null 2>&1; then\n  \(name) \(quoted(prompt))\n"
            if let fallback, let found {
                check += "elif \(found); then\n  \(fallback) \(quoted(prompt))\n"
            }
            check += "else\n  echo \(missing)\n  read -k 1 -s '?Press any key to close.'\nfi"
            lines.append(check)
        case .line(let text):
            lines.append(text)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
