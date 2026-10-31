import Foundation
import Testing
@testable import PRPulseCore

private let ref = PullRequestRef(owner: "acme", repo: "web", number: 412)
private let url = URL(string: "https://github.com/acme/web/pull/412")!
private let start = Date(timeIntervalSince1970: 1_000)

private func run(_ number: Int = 412, at seconds: TimeInterval = 0) -> AgentRun {
    AgentRun(
        ref: PullRequestRef(owner: "acme", repo: "web", number: number),
        title: "Per-tenant session cache",
        url: url,
        folder: "/code/acme",
        skill: nil,
        startedAt: Date(timeIntervalSince1970: seconds)
    )
}

// MARK: Run list

@Test func aNewRunStartsRunningAndUnseen() {
    let made = run()

    #expect(made.isRunning)
    #expect(!made.isSeen)
    #expect(made.output == nil)
}

@Test func finishingARunKeepsTheReviewAndStopsTheActivity() {
    var list = AgentRunList()
    let made = run()
    list.add(made)
    list.update(made.id) { $0.activity = "Reading file" }

    list.finish(made.id, output: "Looks fine.", at: start)

    let done = list.run(id: made.id)
    #expect(done?.state == .finished)
    #expect(done?.output == "Looks fine.")
    #expect(done?.activity == nil)
    #expect(done?.finishedAt == start)
    #expect(list.hasUnseen)
}

@Test func aRunThatAlreadyEndedIgnoresALaterFailure() {
    var list = AgentRunList()
    let made = run()
    list.add(made)
    list.finish(made.id, output: "Done.", at: start)

    list.fail(made.id, message: "exited", at: start)

    #expect(list.run(id: made.id)?.state == .finished)
    #expect(list.run(id: made.id)?.output == "Done.")
}

@Test func openingAFinishedRunMarksItSeen() {
    var list = AgentRunList()
    let made = run()
    list.add(made)
    list.finish(made.id, output: "Done.", at: start)

    list.markSeen(made.id)

    #expect(!list.hasUnseen)
}

@Test func theNewestRunComesFirstAndTheOnesGoingOnAreCounted() {
    var list = AgentRunList()
    let older = run(1)
    let newer = run(2)
    list.add(older)
    list.add(newer)
    list.finish(older.id, output: "Done.", at: start)

    #expect(list.runs.map(\.id) == [newer.id, older.id])
    #expect(list.running.map(\.id) == [newer.id])
    #expect(list.running(for: newer.ref)?.id == newer.id)
    #expect(list.running(for: older.ref) == nil)
}

@Test func onlyTheLatestFinishedRunsAreKeptAndTheOnesGoingOnNever() {
    var list = AgentRunList()
    let going = run(0)
    list.add(going)
    for number in 1 ... (AgentRunList.keptFinished + 5) {
        let made = run(number)
        list.add(made)
        list.finish(made.id, output: "Done.", at: start)
    }

    #expect(list.runs.filter { !$0.isRunning }.count == AgentRunList.keptFinished)
    #expect(list.run(id: going.id) != nil)
}

@Test func whatWasRunningWhenPRPulseClosedBecomesFailed() {
    var list = AgentRunList()
    let made = run()
    list.add(made)

    list.interrupt(at: start, message: "Closed")

    #expect(list.run(id: made.id)?.state == .failed)
    #expect(list.run(id: made.id)?.output == "Closed")
}

@Test func removingARunTakesItOffTheList() {
    var list = AgentRunList()
    let made = run()
    list.add(made)

    list.remove(made.id)

    #expect(list.runs.isEmpty)
}

@Test func theListSurvivesBeingSavedAndLoaded() throws {
    var list = AgentRunList()
    let made = run()
    list.add(made)
    list.finish(made.id, output: "Done.", at: start)

    let decoded = try JSONDecoder().decode(AgentRunList.self, from: JSONEncoder().encode(list))

    #expect(decoded == list)
}

// MARK: Stream

@Test func initGivesTheSession() {
    let line = #"{"type":"system","subtype":"init","session_id":"abc-123","cwd":"/code"}"#

    #expect(ClaudeStream.events(in: line) == [.session("abc-123")])
}

@Test func otherSystemLinesAreIgnored() {
    #expect(ClaudeStream.events(in: #"{"type":"system","subtype":"hook_started","session_id":"x"}"#).isEmpty)
    #expect(ClaudeStream.events(in: #"{"type":"rate_limit_event"}"#).isEmpty)
    #expect(ClaudeStream.events(in: "not json").isEmpty)
}

@Test func aToolUseShowsWhatItWorksOn() {
    let read = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/code/acme/web/src/auth.ts"}}]}}"#
    let command = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"gh pr diff 412 --repo acme/web\nmore"}}]}}"#
    let skill = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"code-review"}}]}}"#

    #expect(ClaudeStream.events(in: read) == [.tool(name: "Read", detail: "auth.ts")])
    #expect(ClaudeStream.events(in: command) == [.tool(name: "Bash", detail: "gh pr diff 412 --repo acme/web")])
    #expect(ClaudeStream.events(in: skill) == [.tool(name: "Skill", detail: "code-review")])
}

@Test func aLongDetailIsCut() {
    let long = String(repeating: "a", count: 200)
    let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Grep","input":{"pattern":"\#(long)"}}]}}"#

    guard case .tool(_, let detail)? = ClaudeStream.events(in: line).first else {
        Issue.record("no tool event")
        return
    }
    #expect(detail?.count == 71)
}

@Test func assistantTextMeansItIsWritingAndUnknownToolsHaveNoDetail() {
    let text = #"{"type":"assistant","message":{"content":[{"type":"text","text":"The PR is fine."}]}}"#
    let other = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"ToolSearch","input":{"query":"x"}}]}}"#

    #expect(ClaudeStream.events(in: text) == [.writing])
    #expect(ClaudeStream.events(in: other) == [.tool(name: "ToolSearch", detail: nil)])
}

@Test func aSuccessfulResultCarriesTheReview() {
    let line = #"{"type":"result","subtype":"success","is_error":false,"result":"All good.","session_id":"abc"}"#

    #expect(ClaudeStream.events(in: line) == [.result(text: "All good.", isError: false, sessionID: "abc")])
}

@Test func aResultThatEndedInAnErrorIsMarkedAsOne() {
    let flagged = #"{"type":"result","subtype":"success","is_error":true,"result":"Not logged in","session_id":"abc"}"#
    let stopped = #"{"type":"result","subtype":"error_max_turns","session_id":"abc"}"#

    #expect(ClaudeStream.events(in: flagged) == [.result(text: "Not logged in", isError: true, sessionID: "abc")])
    #expect(ClaudeStream.events(in: stopped) == [.result(text: "error_max_turns", isError: true, sessionID: "abc")])
}

// MARK: Command line

private func value(after option: String, in arguments: [String]) -> String? {
    zip(arguments, arguments.dropFirst()).first { $0.0 == option }?.1
}

private let sessionID = UUID(uuidString: "9E0E68A2-0A13-41AE-8C2C-07E958BA8032")!

private func settings(in arguments: [String]) throws -> [String: Any] {
    let text = try #require(value(after: "--settings", in: arguments))
    return try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
}

@Test func theAutomaticReviewReadsByItselfAndLeavesTheRestToClaudesAutoMode() {
    let arguments = ClaudeCLI.reviewArguments(sessionID: sessionID, name: "Review acme/web#412", folder: "/code/web")

    #expect(arguments.starts(with: ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose"]))
    #expect(value(after: "--session-id", in: arguments) == "9e0e68a2-0a13-41ae-8c2c-07e958ba8032")
    #expect(value(after: "--permission-mode", in: arguments) == "auto")
    #expect(value(after: "--permission-prompt-tool", in: arguments) == "stdio")
    let allowed = value(after: "--allowedTools", in: arguments) ?? ""
    #expect(allowed.contains("Bash(gh pr diff:*)"))
    for forbidden in ["Edit", "Write", "WebFetch", "Bash(gh pr comment", "Bash(gh api", "Bash(git push", "Bash(rm"] {
        #expect(!allowed.contains(forbidden), "\(forbidden) must not be allowed")
    }
}

@Test func theAutomaticReviewNeverEditsChangesGitOrWritesToGitHub() {
    let arguments = ClaudeCLI.reviewArguments(sessionID: sessionID, name: "Review", folder: "/code/web")

    let denied = (value(after: "--disallowedTools", in: arguments) ?? "").split(separator: ",").map(String.init)
    for tool in ["Edit", "Write", "NotebookEdit", "Bash(rm:*)", "Bash(git push:*)", "Bash(git checkout:*)", "Bash(gh pr checkout:*)", "Bash(gh pr comment:*)", "Bash(gh pr merge:*)", "Bash(gh api:*)"] {
        #expect(denied.contains(tool), "\(tool) must be denied")
    }
    #expect(Set(denied).isDisjoint(with: ClaudeCLI.readOnlyTools))
}

@Test func theAutomaticReviewRunsItsCommandsInASandboxWhereTheFolderIsReadOnly() throws {
    let settings = try settings(in: ClaudeCLI.reviewArguments(sessionID: sessionID, name: "Review", folder: "/code/web"))

    let sandbox = try #require(settings["sandbox"] as? [String: Any])
    #expect(sandbox["enabled"] as? Bool == true)
    #expect(sandbox["failIfUnavailable"] as? Bool == true)
    #expect(sandbox["allowUnsandboxedCommands"] as? Bool == false)
    let filesystem = try #require(sandbox["filesystem"] as? [String: Any])
    #expect(filesystem["denyWrite"] as? [String] == ["/code/web"])
    #expect(filesystem["denyRead"] as? [String] == ClaudeCLI.unreadablePaths)
    let network = try #require(sandbox["network"] as? [String: Any])
    #expect(network["allowedDomains"] as? [String] == ["api.github.com", "github.com"])
}

@Test func theClassifierIsToldItIsAReadOnlyReviewAndKeepsItsOwnRules() throws {
    let settings = try settings(in: ClaudeCLI.reviewArguments(sessionID: sessionID, name: "Review", folder: "/code/web"))

    let auto = try #require(settings["autoMode"] as? [String: Any])
    let environment = try #require(auto["environment"] as? [String])
    let hardDeny = try #require(auto["hard_deny"] as? [String])
    #expect(environment.first == "$defaults")
    #expect(environment.contains { $0.contains("read-only review") })
    #expect(hardDeny.first == "$defaults")
    #expect(hardDeny.count > 1)
}

@Test func theFolderInTheSandboxIsExactlyTheOneThePathHasSpacesOrQuotes() throws {
    let folder = "/Users/me/My \"Code\"/web"

    let settings = try settings(in: ClaudeCLI.reviewArguments(sessionID: sessionID, name: "Review", folder: folder))

    let filesystem = try #require((settings["sandbox"] as? [String: Any])?["filesystem"] as? [String: Any])
    #expect(filesystem["denyWrite"] as? [String] == [folder])
}

@Test func askingMeKeepsTheOldRulesAndNoSandbox() {
    let arguments = ClaudeCLI.reviewArguments(sessionID: sessionID, name: "Review", folder: "/code/web", approval: .ask)

    #expect(value(after: "--permission-mode", in: arguments) == "default")
    #expect(value(after: "--permission-prompt-tool", in: arguments) == "stdio")
    #expect(!arguments.contains("--settings"))
    #expect(!arguments.contains("--disallowedTools"))
    #expect(value(after: "--allowedTools", in: arguments) == ClaudeCLI.readOnlyTools.joined(separator: ","))
}

@Test func aFollowUpPicksTheSessionUpAgainWithTheSameRules() throws {
    let automatic = ClaudeCLI.resumeArguments(sessionID: "abc-123", folder: "/code/web")
    let ask = ClaudeCLI.resumeArguments(sessionID: "abc-123", folder: "/code/web", approval: .ask)

    #expect(value(after: "--resume", in: automatic) == "abc-123")
    #expect(!automatic.contains("--session-id"))
    #expect(value(after: "--permission-mode", in: automatic) == "auto")
    #expect(try settings(in: automatic)["sandbox"] != nil)
    #expect(value(after: "--permission-mode", in: ask) == "default")
    #expect(!ask.contains("--settings"))
}

@Test func theReviewPromptNeverTravelsAsAnArgument() {
    let arguments = ClaudeCLI.reviewArguments(sessionID: UUID(), name: "Review", folder: "/code/web")

    #expect(!arguments.contains { $0.contains("pull request") && !$0.contains("sandbox") && !$0.contains("autoMode") })
}

@Test func theCommandIsFoundInTheUsualPlaces() {
    let home = URL(fileURLWithPath: "/Users/me")

    #expect(ClaudeCLI.locate(home: home, fileExists: { $0 == "/Users/me/.local/bin/claude" })?.path == "/Users/me/.local/bin/claude")
    #expect(ClaudeCLI.locate(home: home, fileExists: { $0 == "/opt/homebrew/bin/claude" })?.path == "/opt/homebrew/bin/claude")
    #expect(ClaudeCLI.locate(home: home, fileExists: { _ in false }) == nil)
}

@Test func thePathHasGitAndGhEvenWhenTheAppWasNotStartedFromAShell() {
    let path = ClaudeCLI.environmentPath(home: URL(fileURLWithPath: "/Users/me"), current: "/usr/bin:/custom/bin")

    #expect(path == "/Users/me/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/custom/bin")
}

@Test func loginComesFromTheAuthStatus() {
    #expect(ClaudeCLI.login(fromStatus: #"{"loggedIn":true,"email":"me@acme.com"}"#) == .signedIn(account: "me@acme.com"))
    #expect(ClaudeCLI.login(fromStatus: #"{"loggedIn":false,"authMethod":"none"}"#) == .signedOut)
    #expect(ClaudeCLI.login(fromStatus: "Not logged in") == .signedOut)
}

@Test func continuingInDesktopCarriesTheReviewAndCutsAVeryLongOne() {
    let short = ClaudeCLI.continuationPrompt(url: url, review: "Two issues.")
    let long = ClaudeCLI.continuationPrompt(url: url, review: String(repeating: "x", count: 10_000), limit: 100)

    #expect(short.contains("https://github.com/acme/web/pull/412"))
    #expect(short.contains("Two issues."))
    #expect(!short.hasPrefix("/"))
    #expect(long.contains("[…]"))
    #expect(long.count < 400)
}

@Test func theTerminalScriptQuotesWhatItRuns() {
    let script = ClaudeCLI.resumeScript(cli: URL(fileURLWithPath: "/Users/me/.local/bin/claude"), folder: "/Users/me/My Code/it's", sessionID: "abc-123")

    #expect(script == "#!/bin/zsh\ncd '/Users/me/My Code/it'\\''s' && '/Users/me/.local/bin/claude' --resume 'abc-123'\n")
}

// MARK: Asking and answering

private let bashRequest = #"{"type":"control_request","request_id":"r1","request":{"subtype":"can_use_tool","tool_name":"Bash","display_name":"Bash","input":{"command":"touch note.txt","description":"Create a file"},"description":"Create a file"}}"#

private func json(_ line: String) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
}

@Test func aToolTheAgentMayNotUseBecomesARequestWithWhatItWantsToDo() {
    let events = ClaudeStream.events(in: bashRequest)

    guard case .permission(let request)? = events.first else {
        Issue.record("no request in \(events)")
        return
    }
    #expect(request.id == "r1")
    #expect(request.tool == "Bash")
    #expect(request.summary == "touch note.txt")
    #expect(String(decoding: request.input, as: UTF8.self) == #"{"command":"touch note.txt","description":"Create a file"}"#)
}

@Test func theRequestShowsTheFileTheAgentWantsToChange() {
    let line = #"{"type":"control_request","request_id":"r2","request":{"subtype":"can_use_tool","tool_name":"Edit","input":{"file_path":"/code/web/a.ts","old_string":"x","new_string":"y"}}}"#

    guard case .permission(let request)? = ClaudeStream.events(in: line).first else {
        Issue.record("no request")
        return
    }
    #expect(request.tool == "Edit")
    #expect(request.summary == "/code/web/a.ts")
}

@Test func aToolWithoutAKnownShapeShowsItsInput() {
    let line = #"{"type":"control_request","request_id":"r3","request":{"subtype":"can_use_tool","tool_name":"mcp__x__go","input":{"a":1}}}"#

    guard case .permission(let request)? = ClaudeStream.events(in: line).first else {
        Issue.record("no request")
        return
    }
    #expect(request.summary == #"{"a":1}"#)
}

@Test func aVeryLongCommandIsCutInTheSummaryButNotInTheInput() {
    let command = String(repeating: "a", count: 2_000)
    let line = #"{"type":"control_request","request_id":"r4","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"\#(command)"}}}"#

    guard case .permission(let request)? = ClaudeStream.events(in: line).first else {
        Issue.record("no request")
        return
    }
    #expect(request.summary.count == 601)
    #expect(String(decoding: request.input, as: UTF8.self).contains(command))
}

@Test func otherControlRequestsAreIgnoredAndACancelNamesTheRequest() {
    let other = #"{"type":"control_request","request_id":"r5","request":{"subtype":"hook_callback"}}"#
    let cancel = #"{"type":"control_cancel_request","request_id":"r1"}"#

    #expect(ClaudeStream.events(in: other).isEmpty)
    #expect(ClaudeStream.events(in: cancel) == [.permissionCancelled("r1")])
}

@Test func allowingHandsTheInputBackUnchanged() throws {
    let input = Data(#"{"command":"touch note.txt"}"#.utf8)

    let line = ClaudeProtocol.permissionResponse(requestID: "r1", allow: true, input: input, denial: "no")

    let response = try #require(json(line)["response"] as? [String: Any])
    #expect(try json(line)["type"] as? String == "control_response")
    #expect(response["subtype"] as? String == "success")
    #expect(response["request_id"] as? String == "r1")
    let body = try #require(response["response"] as? [String: Any])
    #expect(body["behavior"] as? String == "allow")
    #expect((body["updatedInput"] as? [String: Any])?["command"] as? String == "touch note.txt")
}

@Test func denyingSaysWhyAndLeavesTheInputOut() throws {
    let line = ClaudeProtocol.permissionResponse(requestID: "r1", allow: false, input: Data("{}".utf8), denial: "The reviewer said no.")

    let body = try #require((json(line)["response"] as? [String: Any])?["response"] as? [String: Any])
    #expect(body["behavior"] as? String == "deny")
    #expect(body["message"] as? String == "The reviewer said no.")
    #expect(body["updatedInput"] == nil)
}

@Test func aMessageIsOneLineEvenWhenItHasLineBreaksAndQuotes() throws {
    let line = ClaudeProtocol.userMessage("First \"point\"\nSecond / point")

    #expect(!line.contains("\n"))
    #expect(try json(line)["type"] as? String == "user")
    let message = try #require(json(line)["message"] as? [String: Any])
    #expect(message["role"] as? String == "user")
    #expect(message["content"] as? String == "First \"point\"\nSecond / point")
}

@Test func theInterruptNamesItsRequest() throws {
    let line = ClaudeProtocol.interruptRequest(id: "prpulse-1")

    #expect(try json(line)["type"] as? String == "control_request")
    #expect(try json(line)["request_id"] as? String == "prpulse-1")
    #expect((try json(line)["request"] as? [String: Any])?["subtype"] as? String == "interrupt")
}

private let approval = ToolApproval(requestID: "r1", tool: "Bash", summary: "touch note.txt")

@Test func anApprovalLivesOnlyWhileTheRunIsGoing() {
    var list = AgentRunList()
    let made = run()
    list.add(made)

    list.setApproval(made.id, approval)
    #expect(list.run(id: made.id)?.approval == approval)
    #expect(list.needsApproval)

    list.finish(made.id, output: "Done.", at: start)
    #expect(list.run(id: made.id)?.approval == nil)
    list.setApproval(made.id, approval)
    #expect(list.run(id: made.id)?.approval == nil)
}

@Test func aQuestionKeepsTheReviewAndPutsTheAnswerAfterIt() {
    var list = AgentRunList()
    let made = run()
    list.add(made)
    list.finish(made.id, output: "Review.", at: start)

    let accepted = list.ask(made.id, question: "Why the lock?", at: start)
    #expect(accepted)
    #expect(list.run(id: made.id)?.isRunning == true)
    #expect(list.run(id: made.id)?.output == "Review." + AgentRunList.separator + "Why the lock?\n\n")

    list.finish(made.id, output: "Because of the race.", at: start)

    let done = list.run(id: made.id)
    #expect(done?.state == .finished)
    #expect(done?.question == nil)
    #expect(done?.output == "Review." + AgentRunList.separator + "Why the lock?\n\nBecause of the race.")
    #expect(done?.isSeen == false)
}

@Test func onlyAReviewThatIsReadyTakesAQuestion() {
    var list = AgentRunList()
    let going = run()
    let broken = run(7)
    list.add(going)
    list.add(broken)
    list.fail(broken.id, message: "exited", at: start)

    let whileGoing = list.ask(going.id, question: "Hm?", at: start)
    let afterFailing = list.ask(broken.id, question: "Hm?", at: start)
    let unknown = list.ask(UUID(), question: "Hm?", at: start)
    #expect(!whileGoing)
    #expect(!afterFailing)
    #expect(!unknown)
}

@Test func aFollowUpThatFailsLeavesTheReviewAsItWas() {
    var list = AgentRunList()
    let made = run()
    list.add(made)
    list.finish(made.id, output: "Review.", at: start)
    list.ask(made.id, question: "More?", at: start)

    list.fail(made.id, message: "Claude stopped with code 1.", at: start)

    let after = list.run(id: made.id)
    #expect(after?.state == .finished)
    #expect(after?.output?.hasPrefix("Review.") == true)
    #expect(after?.output?.hasSuffix("Claude stopped with code 1.") == true)
}

@Test func runsSavedBeforeApprovalsExistStillLoad() throws {
    let old = #"{"runs":[{"id":"6B29FC40-CA47-4B10-8F0E-0F8B1B6F9C11","ref":{"owner":"acme","repo":"web","number":1},"title":"T","url":"https://github.com/acme/web/pull/1","folder":"/code","startedAt":1000,"state":"finished","output":"ok","isSeen":true}]}"#

    let list = try JSONDecoder().decode(AgentRunList.self, from: Data(old.utf8))

    #expect(list.runs.count == 1)
    #expect(list.runs[0].approval == nil)
    #expect(list.runs[0].question == nil)
}
