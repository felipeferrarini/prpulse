import Foundation

/// Which releases to announce after the app was updated.
public enum ReleaseNotes {
    /// The releases the viewer has not been told about, newest first, up to the one running now.
    ///
    /// A fresh install has nothing to catch up on. An install that predates this feature has no version on record, so it
    /// hears about the running version only.
    public static func unseen(
        in releases: [ChangelogRelease],
        current: String,
        seen: String,
        isFirstRun: Bool
    ) -> [ChangelogRelease] {
        guard isNumeric(current) else { return [] }
        if seen.isEmpty {
            return isFirstRun ? [] : releases.filter { compare($0.version, current) == .orderedSame }
        }
        return releases.filter { compare($0.version, seen) == .orderedDescending && compare($0.version, current) != .orderedDescending }
    }

    /// Compares dotted version numbers part by part, so `0.10.0` comes after `0.9.0`.
    public static func compare(_ left: String, _ right: String) -> ComparisonResult {
        let a = parts(left), b = parts(right)
        for index in 0 ..< max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0, y = index < b.count ? b[index] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    /// A build that was not made from a release, such as `dev`, has no version to announce.
    public static func isNumeric(_ version: String) -> Bool {
        let pieces = version.split(separator: ".", omittingEmptySubsequences: false)
        return !pieces.isEmpty && pieces.allSatisfy { Int($0) != nil }
    }

    private static func parts(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }
}
