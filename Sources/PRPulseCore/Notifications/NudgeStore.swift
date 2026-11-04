import Foundation

/// The nudges the viewer was already told about, so each one is played once.
public final class NudgeStore: @unchecked Sendable {
    private static let retention: TimeInterval = 30 * 86_400

    private let fileURL: URL?
    private let lock = NSLock()
    private var current: [String: Date]

    /// A store that keeps nothing on disk.
    public init() {
        fileURL = nil
        current = [:]
    }

    public init(fileURL: URL) {
        self.fileURL = fileURL
        current = Self.read(fileURL)
    }

    public static func standard(appName: String) -> NudgeStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return NudgeStore(fileURL: base.appendingPathComponent(appName).appendingPathComponent("nudges.json"))
    }

    public var seen: Set<String> {
        lock.withLock { Set(current.keys) }
    }

    public func remember(_ ids: [String], at date: Date) {
        guard !ids.isEmpty else { return }
        lock.withLock {
            for id in ids { current[id] = date }
            current = current.filter { date.timeIntervalSince($0.value) < Self.retention }
            write(current)
        }
    }

    private static func read(_ url: URL) -> [String: Date] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: Date].self, from: data)) ?? [:]
    }

    private func write(_ values: [String: Date]) {
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(values).write(to: fileURL, options: .atomic)
    }
}
