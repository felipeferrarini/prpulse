import Foundation
import Testing
@testable import PRPulseCore

private let first = ReviewTarget(
    ref: PullRequestRef(owner: "acme", repo: "web", number: 412), url: URL(string: "https://github.com/acme/web/pull/412")!
)
private let second = ReviewTarget(
    ref: PullRequestRef(owner: "acme", repo: "api", number: 77), url: URL(string: "https://github.com/acme/api/pull/77")!
)
private let request = ReviewRequest(ref: first.ref, url: first.url)
private let folder = URL(fileURLWithPath: "/Users/me/code/web")

private func plan(
    _ destination: ReviewDestination, prompt: String = "Review https://github.com/acme/web/pull/412",
    folder: URL? = folder, request: ReviewRequest = request, custom: String = ""
) throws -> ReviewLaunch {
    try ReviewLauncher.plan(for: destination, prompt: prompt, folder: folder, request: request, customCommand: custom, cliMissing: { "no \($0)" })
}

private func script(_ launch: ReviewLaunch) -> String {
    if case .terminal(let text) = launch { text } else { "" }
}

// MARK: The destinations

@Test func appsAreReachedByLinksAndTerminalsStartTheAgentThemselves() {
    #expect(ReviewDestination.allCases.filter { $0.style == .link } == [.claudeDesktop, .codexApp, .cursorApp])
    #expect(ReviewDestination.allCases.filter(\.startsByItself) == [.claudeCode, .codexCLI, .cursorAgent, .custom])
    #expect(ReviewDestination.allCases.filter(\.namesSkills) == [.claudeDesktop, .claudeCode])
    #expect(ReviewDestination.default == .claudeDesktop)
}

// MARK: Links

@Test func claudeDesktopGetsItsOwnLinkWithTheFolder() throws {
    let launch = try plan(.claudeDesktop)

    guard case .open(let url) = launch else { Issue.record("expected a link"); return }
    #expect(url.absoluteString.hasPrefix("claude://code/new?q=Review%20https%3A%2F%2Fgithub.com"))
    #expect(url.absoluteString.hasSuffix("&folder=%2FUsers%2Fme%2Fcode%2Fweb"))
}

@Test func codexGetsThePromptAndTheFolderAsItsWorkspace() throws {
    guard case .open(let url) = try plan(.codexApp) else { Issue.record("expected a link"); return }

    #expect(url.absoluteString.hasPrefix("codex://threads/new?prompt=Review%20https%3A%2F%2Fgithub.com%2Facme%2Fweb%2Fpull%2F412"))
    #expect(url.absoluteString.hasSuffix("&path=%2FUsers%2Fme%2Fcode%2Fweb"))
    guard case .open(let bare) = try plan(.codexApp, folder: nil) else { Issue.record("expected a link"); return }
    #expect(!bare.absoluteString.contains("path="))
}

@Test func cursorOpensItsWindowOnTheFolderAndThenTheMessage() throws {
    guard case .openFolderThenLink(let opened, let link) = try plan(.cursorApp) else { Issue.record("expected two steps"); return }

    #expect(opened == folder)
    #expect(link.absoluteString.hasPrefix("cursor://anysphere.cursor-deeplink/prompt?text=Review%20"))
    guard case .open = try plan(.cursorApp, folder: nil) else { Issue.record("a link alone when there is no folder"); return }
}

@Test func theCharactersOfAMessageCannotBecomePartsOfTheAddress() throws {
    guard case .open(let url) = try plan(.codexApp, prompt: "a&path=/etc b#c+d é") else { Issue.record("expected a link"); return }

    #expect(url.absoluteString.contains("prompt=a%26path%3D%2Fetc%20b%23c%2Bd%20%C3%A9"))
}

@Test func noLinkCarriesAMessageThatWouldRunAsACommandOrIsEmptyOrTooLong() {
    for destination in [ReviewDestination.claudeDesktop, .codexApp, .cursorApp] {
        #expect(throws: ReviewLaunchError.slashPrompt) { try plan(destination, prompt: "/code-review {url}") }
        #expect(throws: ReviewLaunchError.emptyPrompt) { try plan(destination, prompt: "  \n ") }
        #expect(throws: ReviewLaunchError.tooLong) { try plan(destination, prompt: String(repeating: "x", count: 9000)) }
    }
}

@Test func aTerminalAcceptsASlashCommandBecauseItIsTheViewersOwnShell() throws {
    #expect(script(try plan(.claudeCode, prompt: "/code-review https://github.com/acme/web/pull/412")).contains("claude '/code-review https://github.com/acme/web/pull/412'"))
}

// MARK: Terminal scripts

@Test func claudeCodeRunsInTheFolderWithTheQuotedPrompt() throws {
    let text = script(try plan(.claudeCode, prompt: "Review it, it's fine"))

    #expect(text.hasPrefix("#!/bin/zsh -il\ncd '/Users/me/code/web' || exit 1\n"))
    #expect(text.contains("if command -v claude >/dev/null 2>&1; then\n  claude 'Review it, it'\\''s fine'\n"))
    #expect(text.contains("echo 'no claude'"))
}

@Test func codexAndCursorAgentUseTheirOwnCommands() throws {
    #expect(script(try plan(.codexCLI)).contains("  codex 'Review https://github.com/acme/web/pull/412'\n"))
    let cursor = script(try plan(.cursorAgent))
    #expect(cursor.contains("if command -v agent >/dev/null 2>&1; then\n  agent '"))
    #expect(cursor.contains("elif command -v cursor-agent >/dev/null 2>&1; then\n  cursor-agent '"))
}

@Test func withoutAFolderTheScriptDoesNotChangeDirectory() throws {
    #expect(!script(try plan(.claudeCode, folder: nil)).contains("cd "))
}

@Test func aFolderNameCannotBreakOutOfItsQuotes() throws {
    let tricky = URL(fileURLWithPath: "/Users/me/it's; rm -rf ~")
    #expect(script(try plan(.claudeCode, folder: tricky)).contains("cd '/Users/me/it'\\''s; rm -rf ~' || exit 1"))
}

// MARK: The custom command

@Test func theCustomCommandGetsEveryPlaceholderAsOneQuotedWord() throws {
    let group = ReviewRequest(targets: [first, second], scope: .together)
    let text = script(try plan(.custom, prompt: "it's here", request: group, custom: "my-agent --repo {repo} --pr {number} --dir {folder} {prompt}"))

    #expect(text.contains("my-agent --repo 'acme/web' --pr '412' --dir '/Users/me/code/web' 'it'\\''s here'\n"))
}

@Test func theCustomCommandGetsThePromptAtTheEndWhenItDoesNotAskWhere() throws {
    let text = script(try plan(.custom, prompt: "Review", custom: "my-agent --review"))

    #expect(text.contains("my-agent --review 'Review'\n"))
}

@Test func whatAPullRequestHoldsCannotBecomePartOfTheCustomCommand() throws {
    let text = script(try plan(.custom, prompt: "x'; touch /tmp/owned; echo '", custom: "my-agent {prompt}"))

    #expect(text.contains("my-agent 'x'\\''; touch /tmp/owned; echo '\\'''\n"))
}

@Test func aCustomDestinationWithoutACommandCannotBeLaunched() {
    #expect(throws: ReviewLaunchError.missingCommand) { try plan(.custom, custom: "   ") }
}

@Test func theUrlsPlaceholderOfTheCustomCommandListsEveryPullRequest() {
    let group = ReviewRequest(targets: [first, second], scope: .stack)
    let line = CustomCommand.render("run {urls}", prompt: "p", request: group, folder: nil)

    #expect(line == "run 'https://github.com/acme/web/pull/412\nhttps://github.com/acme/api/pull/77' 'p'")
}

// MARK: The scripts really run

private func run(_ script: String) throws -> (output: String, status: Int32) {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("prpulse-test-\(UUID().uuidString).sh")
    try script.write(to: file, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: file) }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = [file.path]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    return (String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self), process.terminationStatus)
}

@Test func aCustomScriptRunsInTheFolderWithEveryValueIntact() throws {
    let where_ = FileManager.default.temporaryDirectory.appendingPathComponent("it's a folder \(UUID().uuidString)")
    try FileManager.default.createDirectory(at: where_, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: where_) }
    let tricky = "it's; echo OWNED \"$HOME\" `id` $(id) & done"
    let launch = try plan(.custom, prompt: tricky, folder: where_, custom: "printf '[%s]' {prompt} {number} {folder}; pwd")

    let result = try run(script(launch))

    #expect(result.status == 0)
    #expect(result.output.contains("[\(tricky)][412][\(where_.path)]"))
    #expect(!result.output.contains("OWNED\n"))
    #expect(result.output.hasSuffix(where_.resolvingSymlinksInPath().path + "\n") || result.output.contains(where_.lastPathComponent))
}

@Test func aMissingCommandSaysSoAndDoesNotRunAnythingElse() throws {
    let launch = try ReviewLauncher.plan(
        for: .claudeCode, prompt: "p", folder: nil, request: request, cliMissing: { "PRPULSE_TEST: \($0) is missing" }
    )
    let text = script(launch).replacingOccurrences(of: "#!/bin/zsh -il", with: "#!/bin/zsh\nPATH=/usr/bin:/bin")

    let result = try run(text.replacingOccurrences(of: "read -k 1 -s '?Press any key to close.'", with: "true"))

    #expect(result.output.contains("PRPULSE_TEST: claude is missing"))
}
