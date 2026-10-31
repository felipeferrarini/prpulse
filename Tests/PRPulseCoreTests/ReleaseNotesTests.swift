import Testing
@testable import PRPulseCore

@Suite("ReleaseNotes")
struct ReleaseNotesTests {
    private let releases = ["0.10.0", "0.9.0", "0.8.0", "0.7.0"].map {
        ChangelogRelease(version: $0, date: nil, sections: [ChangelogSection(title: "Added", items: ["x"])])
    }

    private func versions(_ current: String, seen: String, firstRun: Bool = false) -> [String] {
        ReleaseNotes.unseen(in: releases, current: current, seen: seen, isFirstRun: firstRun).map(\.version)
    }

    @Test("announces every version after the one last shown, up to the running one")
    func catchesUp() {
        #expect(versions("0.9.0", seen: "0.7.0") == ["0.9.0", "0.8.0"])
        #expect(versions("0.10.0", seen: "0.9.0") == ["0.10.0"])
    }

    @Test("does not announce a version that was already shown")
    func alreadySeen() {
        #expect(versions("0.9.0", seen: "0.9.0").isEmpty)
        #expect(versions("0.8.0", seen: "0.9.0").isEmpty)
    }

    @Test("leaves out releases newer than the running version")
    func ignoresNewer() {
        #expect(versions("0.8.0", seen: "0.7.0") == ["0.8.0"])
    }

    @Test("a fresh install announces nothing")
    func firstRun() {
        #expect(versions("0.9.0", seen: "", firstRun: true).isEmpty)
    }

    @Test("an install from before the feature hears about the running version only")
    func upgradeFromBefore() {
        #expect(versions("0.9.0", seen: "") == ["0.9.0"])
    }

    @Test("a build that is not a release announces nothing")
    func developmentBuild() {
        #expect(versions("dev", seen: "0.7.0").isEmpty)
    }

    @Test("compares version parts as numbers")
    func ordering() {
        #expect(ReleaseNotes.compare("0.10.0", "0.9.0") == .orderedDescending)
        #expect(ReleaseNotes.compare("1.0", "1.0.0") == .orderedSame)
        #expect(ReleaseNotes.compare("0.8.1", "0.9.0") == .orderedAscending)
    }
}
