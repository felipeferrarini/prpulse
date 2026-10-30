import Foundation
import Testing
@testable import PRPulseCore

private let hour: Double = 3600
private let now = at(100 * 24 * hour)

private func summary(
    review: [ReviewItem] = [],
    mine: [MineItem] = [],
    waiting: [WaitingItem] = []
) -> Summary {
    Summary(mine: mine, review: review, waiting: waiting)
}

private func requested(_ number: Int, hoursAgo: Double) -> ReviewItem {
    ReviewItem(pr: .fixture(number: number, author: otherHuman, createdAt: now.addingTimeInterval(-hoursAgo * hour)), isRequested: true)
}

private func mood(_ situation: MascotSituation) -> MascotMood {
    MascotMoodResolver.mood(for: situation, now: now)
}

@Test func nothingToDoIsCalmAndTurnsSleepyWhenItLasts() {
    let quiet = summary()
    #expect(mood(MascotSituation(state: .ready(quiet), summary: quiet, upToDateSince: now.addingTimeInterval(-60))) == .calm)
    #expect(mood(MascotSituation(state: .ready(quiet), summary: quiet, upToDateSince: now.addingTimeInterval(-31 * 60))) == .sleep)
    #expect(mood(MascotSituation()) == .calm)
}

@Test func somethingToDoAlertsTheMascot() {
    let busy = summary(review: [requested(1, hoursAgo: 5)])
    #expect(mood(MascotSituation(state: .ready(busy), summary: busy)) == .alert)
}

@Test func aRequestOrAWaitingPRThatIsThreeDaysOldWorriesTheMascot() {
    let old = summary(review: [requested(1, hoursAgo: 73)])
    #expect(mood(MascotSituation(summary: old)) == .worried)

    let waiting = summary(waiting: [WaitingItem(pr: .fixture(number: 2, createdAt: now.addingTimeInterval(-80 * hour)))])
    #expect(mood(MascotSituation(summary: waiting)) == .worried)

    let almost = summary(review: [requested(3, hoursAgo: 70)])
    #expect(mood(MascotSituation(summary: almost)) == .alert)
}

@Test func anOldPullRequestNobodyAskedAboutDoesNotWorry() {
    let team = ReviewItem(pr: .fixture(number: 1, author: otherHuman, createdAt: now.addingTimeInterval(-200 * hour)), isRequested: false)
    #expect(mood(MascotSituation(summary: summary(review: [team]))) == .alert)
}

@Test func somethingNewMakesItHappyEvenWhenThereIsMoreToDo() {
    let busy = summary(review: [requested(1, hoursAgo: 100)])
    let situation = MascotSituation(summary: busy, freshUntil: now.addingTimeInterval(5))
    #expect(mood(situation) == .joy)

    var expired = situation
    expired.freshUntil = now.addingTimeInterval(-1)
    #expect(mood(expired) == .worried)
}

@Test func troubleBeatsEverythingElse() {
    let busy = summary(review: [requested(1, hoursAgo: 5)])
    let fresh = now.addingTimeInterval(5)
    #expect(mood(MascotSituation(state: .failed(.unauthenticated), summary: busy, freshUntil: fresh)) == .sad)
    #expect(mood(MascotSituation(isOffline: true, summary: busy, freshUntil: fresh)) == .sad)
}

@Test func aRefreshInFlightMakesItThinkUnlessSomethingBeatsIt() {
    let busy = summary(review: [requested(1, hoursAgo: 100)])
    #expect(mood(MascotSituation(summary: busy, isRefreshing: true)) == .think)
    #expect(mood(MascotSituation(isOffline: true, summary: busy, isRefreshing: true)) == .sad)
}

@Test func theArrivalNamesTheNewPullRequests() {
    let first = PullRequestSnapshot.fixture(number: 1, author: otherHuman)
    let second = PullRequestSnapshot.fixture(number: 2, author: otherHuman)
    let all = Summary(mine: [], review: [ReviewItem(pr: first, isRequested: true), ReviewItem(pr: second, isRequested: false)])
    let keys = [PendingKey(ref: second.ref, reason: "needsReview"), PendingKey(ref: first.ref, reason: "needsReview"), PendingKey(ref: first.ref, reason: "other")]

    let arrival = Arrival.make(from: keys, in: all, at: now)
    #expect(arrival == Arrival(count: 2, firstTitle: "PR 1", at: now))
    #expect(Arrival.make(from: [], in: all, at: now) == nil)
}

// MARK: Manifest

private func manifest(
    frame: MascotManifest.FrameSize = .init(width: 28, height: 28),
    fps: Int = 8,
    states: [String: MascotManifest.Clip] = ["calm": .init(row: 0, frames: 4), "joy": .init(row: 1, frames: 3)]
) -> MascotManifest {
    MascotManifest(name: "Test", frame: frame, fps: fps, states: states)
}

@Test func aWellFormedManifestIsValid() throws {
    try manifest().validate(sheetWidth: 28 * 4, sheetHeight: 56)
}

@Test func aManifestNeedsCalmAndSaneNumbers() {
    #expect(throws: MascotManifest.Problem.missingCalm) { try manifest(states: ["joy": .init(row: 0, frames: 1)]).validate(sheetWidth: 100, sheetHeight: 100) }
    #expect(throws: MascotManifest.Problem.badFrameSize) { try manifest(frame: .init(width: 0, height: 28)).validate(sheetWidth: 100, sheetHeight: 100) }
    #expect(throws: MascotManifest.Problem.badFramesPerSecond) { try manifest(fps: 0).validate(sheetWidth: 100, sheetHeight: 100) }
    #expect(throws: MascotManifest.Problem.badFramesPerSecond) { try manifest(fps: 60).validate(sheetWidth: 100, sheetHeight: 100) }
}

@Test func aClipThatFallsOutsideTheSheetIsRejected() {
    #expect(throws: MascotManifest.Problem.clipOutsideSheet("joy")) { try manifest().validate(sheetWidth: 28 * 4, sheetHeight: 28) }
    #expect(throws: MascotManifest.Problem.clipOutsideSheet("calm")) { try manifest().validate(sheetWidth: 28 * 3, sheetHeight: 56) }
}

@Test func moodsThePackDoesNotKnowAreIgnoredAndMissingOnesFallBackToCalm() throws {
    let pack = manifest(states: ["calm": .init(row: 0, frames: 2), "dancing": .init(row: 99, frames: 99)])
    try pack.validate(sheetWidth: 56, sheetHeight: 28)
    #expect(pack.clip(for: .sad) == .init(row: 0, frames: 2))
}

@Test func theBuiltInManifestShapeDecodes() throws {
    let json = Data(#"{"name":"Brasa","author":"PRPulse","frame":{"width":28,"height":28},"fps":8,"states":{"calm":{"row":0,"frames":24}}}"#.utf8)
    let decoded = try JSONDecoder().decode(MascotManifest.self, from: json)
    #expect(decoded.name == "Brasa")
    #expect(decoded.clip(for: .calm).frames == 24)
}

@Test func mascotSettingsDefaultOnWithBrasaAndSurviveARoundTrip() throws {
    let defaults = AppSettings.defaults
    #expect(defaults.mascotEnabled)
    #expect(defaults.mascotPack == "brasa")
    #expect(defaults.mascotScale == 4)
    #expect(defaults.mascotAnchor == nil)

    let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"org":"acme"}"#.utf8))
    #expect(old.mascotEnabled && old.mascotPack == "brasa" && !old.mascotIntroduced)

    var settings = AppSettings.defaults
    settings.mascotEnabled = false
    settings.mascotPack = "gota"
    settings.mascotAnchor = MascotAnchor(screen: "42", right: 24, bottom: 30)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
    #expect(decoded == settings)
}
