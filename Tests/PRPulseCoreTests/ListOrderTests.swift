import Testing
@testable import PRPulseCore

private func item(
    _ number: Int,
    repo: String = "app",
    author: String = "ana",
    title: String? = nil,
    branch: String = "",
    createdAt: Double = 0,
    comments: [CommentSnapshot] = [],
    requested: Bool = false,
    isDraft: Bool = false
) -> ReviewItem {
    ReviewItem(
        pr: .fixture(
            number: number, repo: repo, title: title, branch: branch, author: Actor(login: author, isBot: false), isDraft: isDraft,
            createdAt: at(createdAt), comments: comments
        ),
        isRequested: requested
    )
}

private func numbers(_ items: [ReviewItem]) -> [Int] {
    items.map(\.pr.ref.number)
}

// MARK: Sorting

@Test func reviewPriorityPutsRequestsFirstThenReadyBeforeDraftsThenOldest() {
    let items = [
        item(1, createdAt: 10, isDraft: true),
        item(2, createdAt: 30),
        item(3, createdAt: 20),
        item(4, createdAt: 40, requested: true),
    ]
    #expect(numbers(ListOrder.sorted(items, by: .priority)) == [4, 3, 2, 1])
}

@Test func oldestAndNewestFollowTheDateTheyWereOpened() {
    let items = [item(1, createdAt: 20), item(2, createdAt: 10), item(3, createdAt: 30)]

    #expect(numbers(ListOrder.sorted(items, by: .oldest)) == [2, 1, 3])
    #expect(numbers(ListOrder.sorted(items, by: .newest)) == [3, 1, 2])
}

@Test func recentActivityPutsTheLatestCommentOrReviewFirst() {
    let quiet = item(1, createdAt: 50)
    let talked = item(2, createdAt: 10, comments: [comment(by: human, at: 90)])
    let items = [quiet, talked]

    #expect(numbers(ListOrder.sorted(items, by: .activity)) == [2, 1])
    #expect(talked.pr.lastActivity == at(90))
    #expect(quiet.pr.lastActivity == at(50))
}

@Test func repositoryAndAuthorSortAlphabeticallyAndTieByPriority() {
    let items = [
        item(1, repo: "web", author: "Zoe", createdAt: 5),
        item(2, repo: "api", author: "ana", createdAt: 9),
        item(3, repo: "api", author: "Bia", createdAt: 1),
    ]

    #expect(numbers(ListOrder.sorted(items, by: .repository)) == [3, 2, 1])
    #expect(numbers(ListOrder.sorted(items, by: .author)) == [2, 3, 1])
}

@Test func mineSortsByTheSameOptions() {
    let old = MineItem(pr: .fixture(number: 1, createdAt: at(1)), reasons: [.readyToMerge])
    let new = MineItem(pr: .fixture(number: 2, createdAt: at(9)), reasons: [.conflict])

    #expect(ListOrder.sorted([old, new], by: .priority).map(\.pr.ref.number) == [2, 1])
    #expect(ListOrder.sorted([old, new], by: .oldest).map(\.pr.ref.number) == [1, 2])
    #expect(ListOrder.sorted([old, new], by: .newest).map(\.pr.ref.number) == [2, 1])
}

// MARK: Filtering

@Test func filterByAuthorAndRepositoryIgnoresCase() {
    let items = [item(1, repo: "web", author: "Ana"), item(2, repo: "api", author: "ana"), item(3, repo: "api", author: "bia")]

    #expect(numbers(ReviewFilter(author: "ANA").apply(to: items)) == [1, 2])
    #expect(numbers(ReviewFilter(repository: "org/api").apply(to: items)) == [2, 3])
    #expect(numbers(ReviewFilter(author: "ana", repository: "org/api").apply(to: items)) == [2])
}

@Test func searchLooksInTheTitleAndTheBranchWithEveryWord() {
    let items = [
        item(1, title: "Fix pagination on invoices", branch: "fix/ENG-12-pagination"),
        item(2, title: "Add cache", branch: "feat/ENG-99-session-cache"),
        item(3, title: "Refactor Ação do aluno", branch: "chore/refactor"),
    ]

    #expect(numbers(ReviewFilter(query: "pagination").apply(to: items)) == [1])
    #expect(numbers(ReviewFilter(query: "eng-99").apply(to: items)) == [2])
    #expect(numbers(ReviewFilter(query: "fix invoices").apply(to: items)) == [1])
    #expect(numbers(ReviewFilter(query: "acao").apply(to: items)) == [3])
    #expect(numbers(ReviewFilter(query: "pagination cache").apply(to: items)).isEmpty)
}

@Test func anEmptyFilterKeepsEverythingAndSaysItIsOff() {
    let items = [item(1), item(2)]

    #expect(!ReviewFilter().isActive)
    #expect(!ReviewFilter(query: "   ").isActive)
    #expect(ReviewFilter(author: "ana").isActive)
    #expect(numbers(ReviewFilter(query: "  ").apply(to: items)) == [1, 2])
}

@Test func theChoicesAreTheDistinctNamesWithTheirCounts() {
    let items = [item(1, repo: "web", author: "bia"), item(2, repo: "api", author: "Ana"), item(3, repo: "api", author: "ana")]

    #expect(ReviewFilter.authors(in: items) == [.init(value: "Ana", count: 2), .init(value: "bia", count: 1)])
    #expect(ReviewFilter.repositories(in: items) == [.init(value: "org/api", count: 2), .init(value: "org/web", count: 1)])
}

@Test func theBranchComesFromTheQuery() throws {
    let node: JSONObject = ["number": 7, "title": "T", "url": "https://github.com/org/app/pull/7", "createdAt": "2026-11-01T10:00:00Z",
                            "headRefName": "feat/x", "repository": ["name": "app", "owner": ["login": "org"]]]
    #expect(try SnapshotMapper.snapshot(from: node).branch == "feat/x")
}

@Test func bothSearchesAskForTheBranch() {
    #expect(Queries.search(.mine).contains("headRefName"))
    #expect(Queries.search(.review).contains("headRefName"))
}
