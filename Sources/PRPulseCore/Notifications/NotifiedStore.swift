import Foundation

public final class NotifiedStore: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    private var current: Set<PendingKey>

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.current = Self.read(fileURL)
    }

    public static func standard(appName: String) -> NotifiedStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return NotifiedStore(fileURL: base.appendingPathComponent(appName).appendingPathComponent("notified.json"))
    }

    public var keys: Set<PendingKey> {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    public func replace(with keys: Set<PendingKey>) {
        lock.lock()
        defer { lock.unlock() }
        current = keys
        write(keys)
    }

    private static func read(_ url: URL) -> Set<PendingKey> {
        guard let data = try? Data(contentsOf: url),
              let keys = try? JSONDecoder().decode([PendingKey].self, from: data)
        else { return [] }
        return Set(keys)
    }

    private func write(_ keys: Set<PendingKey>) {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(Array(keys)).write(to: fileURL, options: .atomic)
    }
}
