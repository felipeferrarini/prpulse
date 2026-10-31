import Foundation

/// Where the agent starts working for a pull request.
public enum ReviewFolderChoice: Equatable, Sendable {
    case use(URL)
    /// The viewer said there is no folder to use for this repository.
    case without
}

public enum ReviewFolders {
    /// What the viewer has already decided: the folder picked for the repository, else the default project of its
    /// organization. A path that is no longer a folder is skipped. `nil` leaves it to looking for a clone, or asking.
    public static func saved(
        for ref: PullRequestRef,
        repositories: [String: String],
        organizations: [String: String],
        isFolder: (String) -> Bool
    ) -> ReviewFolderChoice? {
        if let path = repositories[ref.folderKey] {
            if path.isEmpty { return .without }
            if isFolder(path) { return .use(URL(fileURLWithPath: path)) }
        }
        if let path = organizations[ref.ownerKey], !path.isEmpty, isFolder(path) {
            return .use(URL(fileURLWithPath: path))
        }
        return nil
    }
}
