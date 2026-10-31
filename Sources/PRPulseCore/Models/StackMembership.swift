/// A pull request that is part of a GitHub stack: pull requests stacked on one another, bottom first.
public struct StackMembership: Hashable, Sendable {
    /// The number that identifies the stack within its repository.
    public let number: Int
    /// How many pull requests the stack has.
    public let size: Int
    /// Where this one is in the stack: 1 is the bottom, the one closest to the base branch.
    public let position: Int
    public let baseRef: String

    public init(number: Int, size: Int, position: Int, baseRef: String) {
        self.number = number
        self.size = size
        self.position = position
        self.baseRef = baseRef
    }
}
