import Foundation

/// A stack within a repository.
public struct StackKey: Hashable, Sendable {
    public let owner: String
    public let repo: String
    public let number: Int

    public init(owner: String, repo: String, number: Int) {
        self.owner = owner
        self.repo = repo
        self.number = number
    }
}

/// The pull requests of one stack that a list has, bottom first.
public struct StackGroup<Item>: Identifiable {
    public let key: StackKey
    /// How many pull requests the stack has in all; the list may have only some of them.
    public let size: Int
    public let baseRef: String
    public let members: [Member]

    public struct Member {
        public let item: Item
        public let pr: PullRequestSnapshot
        public var position: Int { pr.stack?.position ?? 0 }
    }

    public var id: StackKey { key }
    public var items: [Item] { members.map(\.item) }
    public var refs: [PullRequestRef] { members.map(\.pr.ref) }
    public var isComplete: Bool { members.count == size }
    /// The one that has waited longest.
    public var oldest: PullRequestSnapshot { members.map(\.pr).min { $0.createdAt < $1.createdAt } ?? members[0].pr }
    public var bottom: PullRequestSnapshot { members[0].pr }
}

/// One row of a list: a pull request on its own, or the stack it belongs to.
public enum ListEntry<Item>: Identifiable {
    case single(Item, PullRequestSnapshot)
    case stack(StackGroup<Item>)

    public var id: String {
        switch self {
        case .single(_, let pr): "\(pr.ref.owner)/\(pr.ref.repo)#\(pr.ref.number)"
        case .stack(let group): "stack:\(group.key.owner)/\(group.key.repo)#\(group.key.number)"
        }
    }
}

public enum StackGrouping {
    /// Puts the pull requests of one stack together, at the place of the first of them, in the order of the stack. A stack
    /// with a single pull request in the list stays a row of its own: there is nothing to put together.
    public static func entries<Item>(_ items: [Item], pr: (Item) -> PullRequestSnapshot) -> [ListEntry<Item>] {
        var byStack: [StackKey: [StackGroup<Item>.Member]] = [:]
        for item in items {
            let snapshot = pr(item)
            guard let key = key(of: snapshot) else { continue }
            byStack[key, default: []].append(.init(item: item, pr: snapshot))
        }
        var placed = Set<StackKey>()
        var entries: [ListEntry<Item>] = []
        for item in items {
            let snapshot = pr(item)
            guard let key = key(of: snapshot), let members = byStack[key], members.count > 1 else {
                entries.append(.single(item, snapshot))
                continue
            }
            guard placed.insert(key).inserted, let stack = snapshot.stack else { continue }
            entries.append(.stack(StackGroup(
                key: key, size: stack.size, baseRef: stack.baseRef, members: members.sorted { $0.position < $1.position }
            )))
        }
        return entries
    }

    private static func key(of pr: PullRequestSnapshot) -> StackKey? {
        pr.stack.map { StackKey(owner: pr.ref.owner, repo: pr.ref.repo, number: $0.number) }
    }
}
