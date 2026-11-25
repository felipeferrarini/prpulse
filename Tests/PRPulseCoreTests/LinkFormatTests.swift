import Foundation
import Testing
@testable import PRPulseCore

private func pr(_ number: Int, repo: String = "api", title: String? = nil) -> PullRequestSnapshot {
    PullRequestSnapshot(
        ref: PullRequestRef(owner: "acme", repo: repo, number: number),
        title: title ?? "PR \(number)", url: URL(string: "https://github.com/acme/\(repo)/pull/\(number)")!,
        author: Actor(login: "sam", isBot: false), isDraft: false, createdAt: Date(timeIntervalSince1970: 1_000),
        reviewDecision: nil, mergeable: .mergeable, mergeState: .clean, checks: .passing,
        threads: [], comments: [], commits: [], reviews: [], requestedReviewers: []
    )
}

@Test func linksAreTheAddressesOneToALine() {
    let text = LinkFormat.links.text(for: [pr(1), pr(2, repo: "web")])
    #expect(text == "https://github.com/acme/api/pull/1\nhttps://github.com/acme/web/pull/2")
}

@Test func titledPutsTheNameAboveTheAddressAndSeparatesThemWithABlankLine() {
    let text = LinkFormat.titled.text(for: [pr(1, title: "Add paging"), pr(2, repo: "web", title: "Fix tabs")])
    #expect(text == "Add paging (api#1)\nhttps://github.com/acme/api/pull/1\n\nFix tabs (web#2)\nhttps://github.com/acme/web/pull/2")
}

@Test func markdownIsAListOfLinks() {
    let text = LinkFormat.markdown.text(for: [pr(1, title: "Add paging"), pr(2, repo: "web", title: "Fix tabs")])
    #expect(text == "- [Add paging (api#1)](https://github.com/acme/api/pull/1)\n- [Fix tabs (web#2)](https://github.com/acme/web/pull/2)")
}

@Test func noPullRequestsGiveNoText() {
    for format in LinkFormat.allCases { #expect(format.text(for: []).isEmpty) }
}
