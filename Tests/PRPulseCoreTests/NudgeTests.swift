import Foundation
import Testing
@testable import PRPulseCore

private let now = at(1_000_000)
private let hour = 3600.0
private let reviewer = "rita"

private func review(_ login: String = reviewer, _ state: ReviewState = .changesRequested, at seconds: Double) -> ReviewSnapshot {
    ReviewSnapshot(authorLogin: login, state: state, submittedAt: at(seconds))
}

private func nudge(
    to login: String = viewer,
    id: String = UUID().uuidString,
    tone: Int = 1,
    by author: String = "ana",
    at seconds: Double
) -> NudgeSnapshot {
    NudgeSnapshot(id: id, recipient: login, tone: tone, message: nil, author: Actor(login: author, isBot: false), createdAt: at(seconds))
}

private func candidates(_ pr: PullRequestSnapshot, ignoredBots: Set<String> = []) -> [NudgeCandidate] {
    NudgeEligibility.candidates(for: pr, viewer: viewer, ignoredBots: ignoredBots, now: now)
}

// MARK: Marker

@Test func aNudgeSurvivesItsMarker() throws {
    let body = NudgeCodec.body(text: "👋 @rita", recipient: "rita", id: "abc-123", tone: 2, message: "Pushed the fix, thanks!")
    let parsed = try #require(NudgeCodec.parse(body, author: human, createdAt: at(5)))

    #expect(parsed == NudgeSnapshot(id: "abc-123", recipient: "rita", tone: 2, message: "Pushed the fix, thanks!", author: human, createdAt: at(5)))
    #expect(body.hasPrefix("👋 @rita\n<!-- prpulse:nudge v1 "))
}

@Test func theMessageNeverBreaksTheMarker() throws {
    let message = "line one\nline two --> <!-- injected"
    let body = NudgeCodec.body(text: "text", recipient: "rita", id: "x", tone: 1, message: message)
    let parsed = try #require(NudgeCodec.parse(body, author: human, createdAt: at(0)))

    #expect(parsed.message == "line one line two injected")
    #expect(body.components(separatedBy: "-->").count == 2)
}

@Test func theMessageIsCutAtTheLimit() throws {
    let long = String(repeating: "a", count: 300)
    let parsed = try #require(NudgeCodec.parse(NudgeCodec.marker(recipient: "r", id: "i", tone: 1, message: long), author: human, createdAt: at(0)))

    #expect(parsed.message?.count == NudgeCodec.maxMessageLength)
    #expect(NudgeCodec.clean("   \n ") == nil)
}

@Test func commentsWithoutAValidMarkerAreNotNudges() {
    #expect(NudgeCodec.parse("looks good", author: human, createdAt: at(0)) == nil)
    #expect(NudgeCodec.parse("<!-- prpulse:nudge v1 to=rita id=1 tone=9 -->", author: human, createdAt: at(0)) == nil)
    #expect(NudgeCodec.parse("<!-- prpulse:nudge v1 to=rita tone=1 -->", author: human, createdAt: at(0)) == nil)
    #expect(NudgeCodec.parse("<!-- prpulse:nudge v1 to=rita id=1 tone=1", author: human, createdAt: at(0)) == nil)
}

// MARK: Who can be nudged

@Test func aReviewerWithNewCommitsCanBeNudged() {
    let pr = PullRequestSnapshot.fixture(
        commits: [commit(by: viewer, at: 200)],
        reviews: [review(at: 100)]
    )

    #expect(candidates(pr) == [NudgeCandidate(login: reviewer, tone: 1, block: nil)])
}

@Test func withoutNewCommitsThereIsNothingToLookAt() {
    let pr = PullRequestSnapshot.fixture(
        commits: [commit(by: viewer, at: 50)],
        reviews: [review(at: 100)]
    )

    #expect(candidates(pr).first?.block == .noNewCommits)
}

@Test func anApprovalAfterTheLastCommitBlocksTheNudge() {
    let pr = PullRequestSnapshot.fixture(
        commits: [commit(by: viewer, at: 100)],
        reviews: [review("rita", .changesRequested, at: 50), review("rita", .approved, at: 150)]
    )

    #expect(candidates(pr).first?.block == .noNewCommits)
}

@Test func theReviewersOwnCommitsDoNotCount() {
    let pr = PullRequestSnapshot.fixture(
        commits: [commit(by: reviewer, at: 300)],
        reviews: [review(at: 100)]
    )

    #expect(candidates(pr).first?.block == .noNewCommits)
}

@Test func someoneWhoOnlyApprovedIsNotListed() {
    let pr = PullRequestSnapshot.fixture(commits: [commit(by: viewer, at: 200)], reviews: [review("amy", .approved, at: 100)])

    #expect(candidates(pr).isEmpty)
}

@Test func aCommenterCanBeNudgedToo() {
    let pr = PullRequestSnapshot.fixture(
        comments: [comment(by: Actor(login: "carl", isBot: false), at: 100)],
        commits: [commit(by: viewer, at: 200)]
    )

    #expect(candidates(pr) == [NudgeCandidate(login: "carl", tone: 1, block: nil)])
}

@Test func botsAndTheAuthorAreNeverListed() {
    let pr = PullRequestSnapshot.fixture(
        comments: [comment(by: botActor, at: 100), comment(by: Actor(login: viewer, isBot: false), at: 100)],
        commits: [commit(by: viewer, at: 200)],
        reviews: [review("coderabbitai", .commented, at: 100)]
    )

    #expect(candidates(pr, ignoredBots: ["coderabbitai"]).isEmpty)
}

@Test func draftsAndOthersPullRequestsCannotNudge() {
    let reviews = [review(at: 100)], commits = [commit(by: viewer, at: 200)]

    #expect(candidates(.fixture(isDraft: true, commits: commits, reviews: reviews)).isEmpty)
    #expect(candidates(.fixture(author: otherHuman, commits: commits, reviews: reviews)).isEmpty)
}

@Test func nudgesAreSpacedAndCapped() {
    let base = PullRequestSnapshot.fixture(commits: [commit(by: viewer, at: 900_000)], reviews: [review(at: 100)])
    func with(_ nudges: [NudgeSnapshot]) -> PullRequestSnapshot {
        .fixture(commits: base.commits, reviews: base.reviews, nudges: nudges)
    }
    let recent = nudge(to: reviewer, tone: 1, by: viewer, at: now.timeIntervalSince1970 - hour)
    let old = nudge(to: reviewer, tone: 1, by: viewer, at: now.timeIntervalSince1970 - 4 * hour)

    let soon = candidates(with([recent])).first
    #expect(soon?.block == .tooSoon(until: recent.createdAt.addingTimeInterval(NudgeEligibility.minimumInterval)))
    #expect(soon?.tone == 2)

    #expect(candidates(with([old])).first == NudgeCandidate(login: reviewer, tone: 2, block: nil))

    let three = (1 ... 3).map { nudge(to: reviewer, tone: $0, by: viewer, at: now.timeIntervalSince1970 - Double(10 - $0) * 4 * hour) }
    #expect(candidates(with(three)).first?.block == .limitReached)
    #expect(candidates(with(three)).first?.tone == 3)
}

@Test func nudgesToSomeoneElseDoNotCountAgainstThisReviewer() {
    let pr = PullRequestSnapshot.fixture(
        commits: [commit(by: viewer, at: 900_000)],
        reviews: [review(at: 100)],
        nudges: [nudge(to: "carl", by: viewer, at: now.timeIntervalSince1970 - hour)]
    )

    #expect(candidates(pr).first?.block == nil)
}

// MARK: Receiving

private func summary(_ prs: [PullRequestSnapshot]) -> Summary {
    Summary(mine: [], review: prs.map { ReviewItem(pr: $0, isRequested: true) })
}

private func incoming(_ prs: [PullRequestSnapshot], seen: Set<String> = [], at date: Date = now) -> [IncomingNudge] {
    NudgePlanner.incoming(in: summary(prs), viewer: viewer, seen: seen, now: date)
}

private func theirPR(_ nudges: [NudgeSnapshot], author: String = "ana") -> PullRequestSnapshot {
    .fixture(author: Actor(login: author, isBot: false), requestedReviewers: [viewer], nudges: nudges)
}

@Test func aNudgeFromTheAuthorToTheViewerArrives() {
    let found = incoming([theirPR([nudge(id: "n1", at: now.timeIntervalSince1970 - 60)])])

    #expect(found.map(\.id) == ["n1"])
    #expect(found.first?.isFresh == true)
}

@Test func aNudgeIsPlayedOnce() {
    let pr = theirPR([nudge(id: "n1", at: now.timeIntervalSince1970 - 60)])

    #expect(incoming([pr], seen: ["n1"]).isEmpty)
}

@Test func anOldNudgeArrivesQuietly() {
    let found = incoming([theirPR([nudge(id: "n1", at: now.timeIntervalSince1970 - 5 * hour)])])

    #expect(found.first?.isFresh == false)
}

@Test func onlyTheAuthorCanNudgeAndOnlyTheViewer() {
    let stranger = theirPR([nudge(id: "n1", by: "mallory", at: now.timeIntervalSince1970 - 60)])
    let other = theirPR([nudge(to: "carl", id: "n2", at: now.timeIntervalSince1970 - 60)])

    #expect(incoming([stranger, other]).isEmpty)
}

@Test func nudgesTooCloseOrTooManyAreIgnored() {
    let t = now.timeIntervalSince1970
    let nudges = [
        nudge(id: "a", at: t - 20 * hour),
        nudge(id: "b", at: t - 19 * hour),
        nudge(id: "c", at: t - 10 * hour),
        nudge(id: "d", at: t - 5 * hour),
        nudge(id: "e", at: t - 1 * hour),
    ]

    // a, c and d are the three that keep the spacing; b came too soon after a and e would be the fourth.
    #expect(incoming([theirPR(nudges)], seen: ["c"]).map(\.id) == ["d"])
    #expect(incoming([theirPR(nudges)], seen: ["c", "d"]).isEmpty)
}

@Test func onlyTheLatestNudgeOfAPullRequestIsPlayed() {
    let t = now.timeIntervalSince1970
    let found = incoming([theirPR([nudge(id: "a", tone: 1, at: t - 9 * hour), nudge(id: "b", tone: 2, at: t - 300)])])

    #expect(found.map(\.id) == ["b"])
}

@Test func theNudgeStoreRemembersAcrossLaunches() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("prpulse-\(UUID().uuidString)/nudges.json")
    NudgeStore(fileURL: url).remember(["n1", "n2"], at: now)

    #expect(NudgeStore(fileURL: url).seen == ["n1", "n2"])

    let store = NudgeStore(fileURL: url)
    store.remember(["n3"], at: now.addingTimeInterval(40 * 86_400))
    #expect(NudgeStore(fileURL: url).seen == ["n3"])
}

// MARK: Reading from GitHub

@Test func theNudgeCommentIsKeptApartFromTheConversation() throws {
    var node = minimalPR(number: 1, author: "ana")
    let marker = NudgeCodec.body(text: "👋", recipient: "me", id: "n1", tone: 1, message: nil)
    node["comments"] = ["nodes": [
        ["createdAt": "2026-10-01T10:00:00Z", "body": "please fix", "author": ["login": "rita", "__typename": "User"]],
        ["createdAt": "2026-10-02T10:00:00Z", "body": marker, "author": ["login": "ana", "__typename": "User"]],
    ]]

    let pr = try SnapshotMapper.snapshot(from: node)

    #expect(pr.comments.map(\.author.login) == ["rita"])
    #expect(pr.nudges.map(\.id) == ["n1"])
    #expect(pr.nudges.first?.author.login == "ana")
}

@Test func aReviewerAskedAgainSeesThePullRequestAgain() {
    let reviewed = PullRequestSnapshot.fixture(
        author: otherHuman,
        reviews: [ReviewSnapshot(authorLogin: viewer, state: .changesRequested, submittedAt: at(10))],
        requestedReviewers: [viewer]
    )
    let notAsked = PullRequestSnapshot.fixture(
        number: 2,
        author: otherHuman,
        reviews: [ReviewSnapshot(authorLogin: viewer, state: .changesRequested, submittedAt: at(10))]
    )

    let items = ReviewClassifier.items(from: [reviewed, notAsked], viewer: viewer, ignoredRepos: [])

    #expect(items.map(\.pr.ref.number) == [1, 2])
    #expect(items.map(\.needsAction) == [true, false])
}

// MARK: Sending

private func nudgeRequest() -> NudgeRequest {
    NudgeRequest(ref: PullRequestRef(owner: "org", repo: "app", number: 7), reviewer: "rita", tone: 2, message: "ping", text: "👋 @rita")
}

private func targets() -> Data {
    json(["data": ["repository": ["pullRequest": ["id": "PR_1"]], "user": ["id": "U_1"]]])
}

private let accepted = json(["data": ["x": ["clientMutationId": NSNull()]]])

@Test func aNudgeAsksForTheReviewAndLeavesTheComment() async throws {
    let transport = FakeTransport { query, _ in query.contains("nudge") || query.contains("repository(") ? targets() : accepted }
    let client = GitHubClient(transport: transport, clock: FixedClock(now: now))

    let outcome = try await client.nudge(nudgeRequest())

    #expect(outcome == .sent)
    let calls = transport.calls
    #expect(calls.count == 3)
    #expect(calls[1].query.contains("requestReviews"))
    #expect(calls[1].variables["pullRequest"] as? String == "PR_1")
    #expect(calls[1].variables["users"] as? [String] == ["U_1"])
    #expect(calls[2].query.contains("addComment"))
    let body = try #require(calls[2].variables["body"] as? String)
    let parsed = try #require(NudgeCodec.parse(body, author: human, createdAt: now))
    #expect(parsed.recipient == "rita" && parsed.tone == 2 && parsed.message == "ping")
}

@Test func aRefusedReviewRequestStillLeavesTheComment() async throws {
    let refused = json(["data": ["requestReviews": NSNull()], "errors": [["type": "FORBIDDEN", "message": "not allowed"]]])
    let transport = FakeTransport { query, _ in
        if query.contains("requestReviews") { return refused }
        return query.contains("addComment") ? accepted : targets()
    }
    let client = GitHubClient(transport: transport, clock: FixedClock(now: now))

    #expect(try await client.nudge(nudgeRequest()) == .commentOnly)
    #expect(transport.calls.contains { $0.query.contains("addComment") })
}

@Test func aRefusedCommentFailsTheNudge() async throws {
    let refused = json(["data": NSNull(), "errors": [["type": "FORBIDDEN", "message": "no write access"]]])
    let transport = FakeTransport { query, _ in query.contains("mutation") ? refused : targets() }
    let client = GitHubClient(transport: transport, clock: FixedClock(now: now))

    await #expect(throws: ProviderError.malformed("no write access")) {
        try await client.nudge(nudgeRequest())
    }
}

// MARK: Settings and mood

@Test func oldSettingsGetNudgesSwitchedOn() throws {
    let old = #"{"orgs":["org"],"authSource":"ghCli","hasCompletedSetup":true}"#
    let settings = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))

    #expect(settings.nudgesEnabled && settings.nudgeSoundEnabled)
    #expect(settings.nudgesPausedUntil == nil)
    #expect(!settings.areNudgesPaused(at: now))
    #expect(settings.nudgeSound == "system:Sosumi")
}

@Test func nudgeSoundChoiceSurvivesSaving() throws {
    var settings = AppSettings.defaults
    settings.nudgeSound = NudgeSoundChoice.user("fah.mp3").id
    let saved = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))

    #expect(saved.nudgeSound == "user:fah.mp3")
}

@Test func soundIDsNameASystemSoundOrAFile() {
    #expect(NudgeSoundChoice(id: "system:Glass") == .system("Glass"))
    #expect(NudgeSoundChoice(id: "user:fah.mp3") == .user("fah.mp3"))
    #expect(NudgeSoundChoice.system("Glass").id == "system:Glass")
    #expect(NudgeSoundChoice.user("fah.mp3").name == "fah")
    #expect(NudgeSoundChoice.defaultID == "system:Sosumi")
}

@Test func soundIDsCannotLeaveTheirFolder() {
    for id in ["", "Glass", "system:", "user:", "user:../secret.mp3", "user:a/b.mp3", "user:..", "system:/etc/passwd", "other:x"] {
        #expect(NudgeSoundChoice(id: id) == nil, "\(id)")
    }
}

@Test func pausedNudgesResumeByThemselves() {
    var settings = AppSettings.defaults
    settings.nudgesPausedUntil = now.addingTimeInterval(hour)

    #expect(settings.areNudgesPaused(at: now))
    #expect(!settings.areNudgesPaused(at: now.addingTimeInterval(2 * hour)))
}

@Test func aNudgeMakesTheMascotInsistentUnlessThereIsTrouble() {
    #expect(MascotMoodResolver.mood(for: MascotSituation(isNudged: true), now: now) == .nudged)
    #expect(MascotMoodResolver.mood(for: MascotSituation(isOffline: true, isNudged: true), now: now) == .sad)
}
