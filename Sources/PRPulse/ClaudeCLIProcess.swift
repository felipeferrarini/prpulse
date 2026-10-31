import Foundation
import PRPulseCore

/// One `claude -p` conversation: starts it, writes to it and reports what it prints, one line at a time. The process
/// stays open after an answer, waiting for the next message, until its input is closed or it is stopped.
final class ClaudeCLIProcess: @unchecked Sendable {
    private static let errorLimit = 8_000
    private static let closeGrace: TimeInterval = 5
    private static let denial = "The reviewer did not allow this."

    /// A write to a process that is gone must come back as an error and not end PRPulse.
    private static let ignoreBrokenPipes: Void = { signal(SIGPIPE, SIG_IGN) }()

    private let process = Process()
    private let queue = DispatchQueue(label: "io.github.felipeferrarini.prpulse.claude-cli")
    private var input: FileHandle?
    private var pending = Data()
    private var errors = Data()
    private var requests: [String: Data] = [:]
    private(set) var wasStopped = false
    /// Set once the input is closed, from the main queue: a message sent after that needs a new process.
    private(set) var isClosing = false

    init(executable: URL, arguments: [String], directory: URL, environment: [String: String]) {
        _ = Self.ignoreBrokenPipes
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = environment
    }

    /// `onEvent` and `onExit` are called on the main queue, in the order things happened.
    func run(
        prompt: String,
        onEvent: @escaping @Sendable (ClaudeStreamEvent) -> Void,
        onExit: @escaping @Sendable (Int32, String) -> Void
    ) throws {
        let stdin = Pipe()
        let output = Pipe()
        let failure = Pipe()
        process.standardInput = stdin
        process.standardOutput = output
        process.standardError = failure

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return handle.readabilityHandler = nil }
            self?.queue.async { self?.consume(data, onEvent: onEvent) }
        }
        failure.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return handle.readabilityHandler = nil }
            self?.queue.async { self?.keepError(data) }
        }
        process.terminationHandler = { [weak self] process in
            self?.queue.async {
                guard let self else { return }
                output.fileHandleForReading.readabilityHandler = nil
                failure.fileHandleForReading.readabilityHandler = nil
                if let rest = try? output.fileHandleForReading.readToEnd() { self.consume(rest, onEvent: onEvent) }
                if let rest = try? failure.fileHandleForReading.readToEnd() { self.keepError(rest) }
                self.consume(Data("\n".utf8), onEvent: onEvent)
                let text = String(decoding: self.errors, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                let status = process.terminationStatus
                DispatchQueue.main.async { onExit(status, text) }
            }
        }
        try process.run()
        input = stdin.fileHandleForWriting
        ask(prompt)
    }

    // MARK: Talking to it

    /// Another message in the same conversation.
    func ask(_ text: String) {
        write(ClaudeProtocol.userMessage(text))
    }

    /// Answers a request the agent made to use a tool.
    func answer(requestID: String, allow: Bool) {
        queue.async { [weak self] in
            guard let self, let tool = self.requests.removeValue(forKey: requestID) else { return }
            self.send(ClaudeProtocol.permissionResponse(requestID: requestID, allow: allow, input: tool, denial: Self.denial))
        }
    }

    /// Stops what it is doing and leaves the conversation open.
    func interrupt() {
        write(ClaudeProtocol.interruptRequest(id: "prpulse-\(UUID().uuidString.lowercased())"))
    }

    /// Lets it finish and leave. It is stopped if it does not.
    func closeInput() {
        isClosing = true
        queue.async { [weak self] in
            try? self?.input?.close()
            self?.input = nil
        }
        queue.asyncAfter(deadline: .now() + Self.closeGrace) { [weak self] in
            guard let self, self.process.isRunning else { return }
            self.process.terminate()
        }
    }

    func stop() {
        wasStopped = true
        if process.isRunning { process.terminate() }
    }

    private func write(_ line: String) {
        queue.async { [weak self] in self?.send(line) }
    }

    private func send(_ line: String) {
        try? input?.write(contentsOf: Data((line + "\n").utf8))
    }

    // MARK: What it prints

    private func consume(_ data: Data, onEvent: @escaping @Sendable (ClaudeStreamEvent) -> Void) {
        pending.append(data)
        while let newline = pending.firstIndex(of: 0x0A) {
            let line = String(decoding: pending[pending.startIndex ..< newline], as: UTF8.self)
            pending.removeSubrange(pending.startIndex ... newline)
            for event in ClaudeStream.events(in: line) {
                remember(event)
                DispatchQueue.main.async { onEvent(event) }
            }
        }
    }

    /// The answer to a request carries the tool's input back, so it is kept until the viewer decides.
    private func remember(_ event: ClaudeStreamEvent) {
        switch event {
        case .permission(let request): requests[request.id] = request.input
        case .permissionCancelled(let id): requests[id] = nil
        default: break
        }
    }

    private func keepError(_ data: Data) {
        errors.append(data)
        if errors.count > Self.errorLimit { errors = errors.suffix(Self.errorLimit) }
    }
}

/// What `claude auth status` says about this Mac.
enum CLIState: Equatable {
    case unknown
    case missing
    case signedOut
    case ready(account: String?)

    var isReady: Bool {
        if case .ready = self { true } else { false }
    }

    static func check() async -> CLIState {
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let cli = ClaudeCLI.locate(home: home) else { return .missing }
        let environment = ClaudeCLI.environment(home: home)
        let output = await Task.detached { Self.run(cli, arguments: ["auth", "status"], environment: environment) }.value
        switch ClaudeCLI.login(fromStatus: output) {
        case .signedIn(let account): return .ready(account: account)
        case .signedOut: return .signedOut
        }
    }

    private static func run(_ cli: URL, arguments: [String], environment: [String: String]) -> String {
        let process = Process()
        process.executableURL = cli
        process.arguments = arguments
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        let stop = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: stop)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        stop.cancel()
        return String(decoding: data, as: UTF8.self)
    }
}
