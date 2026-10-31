import Foundation

public struct GhCliTokenProvider: TokenProvider {
    public typealias Run = @Sendable (_ executable: String, _ arguments: [String]) throws -> (status: Int32, output: String)

    public static let defaultPaths = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]

    private let candidatePaths: [String]
    private let fileExists: @Sendable (String) -> Bool
    private let run: Run

    public init(
        candidatePaths: [String] = Self.defaultPaths,
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        run: @escaping Run = Self.runProcess
    ) {
        self.candidatePaths = candidatePaths
        self.fileExists = fileExists
        self.run = run
    }

    public func token() async throws -> String {
        guard let executable = candidatePaths.first(where: fileExists) else { throw AuthError.ghNotInstalled }
        let result = try await Task.detached { [run] in try run(executable, ["auth", "token"]) }.value
        let token = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.status == 0, !token.isEmpty else { throw AuthError.ghNotLoggedIn }
        return token
    }

    @Sendable
    public static func runProcess(_ executable: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
