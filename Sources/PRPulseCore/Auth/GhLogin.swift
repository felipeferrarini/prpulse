import Foundation

/// A running command whose error output is read line by line.
public protocol LoginProcess: Sendable {
    /// What the process writes to its error output, until it ends.
    var lines: AsyncStream<String> { get }
    func waitUntilExit() async -> Int32
    func terminate()
}

/// Signs in with the GitHub CLI: `gh auth login --web` prints a one-time code and waits until it is entered in the browser.
/// The CLI keeps the token, so the app keeps using `gh auth token` as before.
public struct GhLogin: Sendable {
    public typealias Launch = @Sendable (_ executable: String, _ arguments: [String]) throws -> LoginProcess

    public static let verificationURL = URL(string: "https://github.com/login/device")!
    static let arguments = ["auth", "login", "--web", "--hostname", "github.com", "--git-protocol", "https", "--scopes", "repo,read:org"]

    private let candidatePaths: [String]
    private let fileExists: @Sendable (String) -> Bool
    private let launch: Launch

    public init(
        candidatePaths: [String] = GhCliTokenProvider.defaultPaths,
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        launch: @escaping Launch = Self.launchProcess
    ) {
        self.candidatePaths = candidatePaths
        self.fileExists = fileExists
        self.launch = launch
    }

    /// Returns when the viewer has approved the sign-in. `onCode` gets the code to enter. Cancelling the task stops the login.
    public func signIn(onCode: @escaping @Sendable (DeviceCode) -> Void) async throws {
        guard let executable = candidatePaths.first(where: fileExists) else { throw AuthError.ghNotInstalled }
        let process = try launch(executable, Self.arguments)
        try await withTaskCancellationHandler {
            for await line in process.lines {
                if let code = Self.code(in: line) { onCode(DeviceCode(userCode: code, verificationURL: Self.verificationURL)) }
            }
            let status = await process.waitUntilExit()
            try Task.checkCancellation()
            guard status == 0 else { throw AuthError.ghLoginFailed }
        } onCancel: {
            process.terminate()
        }
    }

    /// `! First copy your one-time code: 2CAB-334F` gives `2CAB-334F`.
    static func code(in line: String) -> String? {
        guard line.contains("one-time code"),
              let range = line.range(of: #"[A-Z0-9]{4}-[A-Z0-9]{4}"#, options: .regularExpression) else { return nil }
        return String(line[range])
    }

    @Sendable
    public static func launchProcess(_ executable: String, _ arguments: [String]) throws -> LoginProcess {
        try SystemLoginProcess(executable: executable, arguments: arguments)
    }
}

private final class SystemLoginProcess: LoginProcess, @unchecked Sendable {
    let lines: AsyncStream<String>
    private let process = Process()
    private let exit: Task<Int32, Never>

    init(executable: String, arguments: [String]) throws {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        // The app opens the page itself, so the CLI must not open a second one.
        environment["GH_BROWSER"] = "/usr/bin/true"
        environment["BROWSER"] = "/usr/bin/true"
        environment["GH_PROMPT_DISABLED"] = "1"
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors

        var continuation: AsyncStream<String>.Continuation!
        lines = AsyncStream { continuation = $0 }
        let output = continuation!
        var pending = Data()
        errors.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                if let rest = String(data: pending, encoding: .utf8), !rest.isEmpty { output.yield(rest) }
                output.finish()
                return
            }
            pending.append(data)
            while let newline = pending.firstIndex(of: 0x0A) {
                if let line = String(data: pending[..<newline], encoding: .utf8) { output.yield(line) }
                pending = Data(pending[pending.index(after: newline)...])
            }
        }
        exit = Task { [process] in
            await withCheckedContinuation { (resume: CheckedContinuation<Int32, Never>) in
                process.terminationHandler = { resume.resume(returning: $0.terminationStatus) }
            }
        }
        try process.run()
    }

    func waitUntilExit() async -> Int32 { await exit.value }

    func terminate() {
        if process.isRunning { process.terminate() }
    }
}
