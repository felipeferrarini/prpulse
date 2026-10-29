import Foundation
import Testing
@testable import PRPulseCore

struct FixedClock: Clock {
    let now: Date
}

final class FakeTransport: GraphQLTransport, @unchecked Sendable {
    typealias Handler = (_ query: String, _ variables: [String: Any]) throws -> Data

    private let lock = NSLock()
    private var recorded: [(query: String, variables: [String: Any])] = []
    private let handler: Handler

    init(_ handler: @escaping Handler) {
        self.handler = handler
    }

    var calls: [(query: String, variables: [String: Any])] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    var searchQueries: [String] {
        calls.compactMap { $0.variables["q"] as? String }
    }

    func send(query: String, variables: [String: Any]) async throws -> Data {
        lock.lock()
        recorded.append((query, variables))
        lock.unlock()
        return try handler(query, variables)
    }
}

func fixtureData(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

func fixtureNode(_ name: String) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: fixtureData(name)) as? [String: Any]
    let search = ((object?["data"] as? [String: Any])?["search"] as? [String: Any])
    return try #require((search?["nodes"] as? [[String: Any]])?.first)
}

func json(_ object: Any) -> Data {
    try! JSONSerialization.data(withJSONObject: object)
}

func minimalPR(number: Int, repo: String = "web", author: String = "someone") -> [String: Any] {
    [
        "number": number,
        "title": "PR \(number)",
        "url": "https://github.com/org/\(repo)/pull/\(number)",
        "isDraft": false,
        "createdAt": "2026-10-01T00:00:00Z",
        "repository": ["name": repo, "owner": ["login": "org"]],
        "author": ["login": author, "__typename": "User"],
    ]
}

func searchResponse(
    nodes: [[String: Any]],
    issueCount: Int? = nil,
    hasNextPage: Bool = false,
    endCursor: String? = nil
) -> Data {
    json([
        "data": [
            "search": [
                "issueCount": issueCount ?? nodes.count,
                "pageInfo": ["hasNextPage": hasNextPage, "endCursor": endCursor as Any],
                "nodes": nodes,
            ],
        ],
    ])
}
