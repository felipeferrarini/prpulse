import Foundation

/// Finds where a repository is cloned, so the agent can work on the code instead of only reading the pull request.
public enum RepositoryLocator {
    /// Where people usually keep their clones, relative to the home folder.
    public static let commonFolders = ["Projects", "Developer", "Code", "code", "src", "dev", "repos", "work", "GitHub", "Documents/GitHub", "Documents/Projects"]

    private static let skipped: Set<String> = ["node_modules", "Pods", "build", "DerivedData", "Library", "vendor"]

    public static func roots(home: URL, fileManager: FileManager = .default) -> [URL] {
        commonFolders.map { home.appendingPathComponent($0) }.filter { fileManager.fileExists(atPath: $0.path) }
    }

    public static func find(owner: String, repo: String, roots: [URL], maxDepth: Int = 3, fileManager: FileManager = .default) -> URL? {
        for root in roots {
            if let match = search(root, depth: 0, owner: owner, repo: repo, maxDepth: maxDepth, fileManager) { return match }
        }
        return nil
    }

    private static func search(_ folder: URL, depth: Int, owner: String, repo: String, maxDepth: Int, _ fileManager: FileManager) -> URL? {
        if depth > 0, fileManager.fileExists(atPath: folder.appendingPathComponent(".git/config").path) {
            return remotes(of: folder).contains { isRemote($0, owner: owner, repo: repo) } ? folder : nil
        }
        guard depth < maxDepth else { return nil }
        let entries = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = entry.lastPathComponent
            guard !name.hasPrefix("."), !skipped.contains(name), (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            if let match = search(entry, depth: depth + 1, owner: owner, repo: repo, maxDepth: maxDepth, fileManager) { return match }
        }
        return nil
    }

    private static func remotes(of clone: URL) -> [String] {
        guard let text = try? String(contentsOf: clone.appendingPathComponent(".git/config"), encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("url") ? trimmed.split(separator: "=", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) } : nil
        }
    }

    /// `git@github.com:owner/repo.git` and `https://github.com/owner/repo`, in any letter case.
    private static func isRemote(_ remote: String, owner: String, repo: String) -> Bool {
        var path = remote.lowercased()
        if path.hasSuffix(".git") { path.removeLast(4) }
        return path.hasSuffix("github.com/\(owner.lowercased())/\(repo.lowercased())")
            || path.hasSuffix("github.com:\(owner.lowercased())/\(repo.lowercased())")
    }
}
