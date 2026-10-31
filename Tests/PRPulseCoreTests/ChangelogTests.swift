import Foundation
import Testing
@testable import PRPulseCore

private let sample = """
# Changelog

All notable changes.

## [Unreleased]

### Added

- Something not out yet.

## [0.6.0] - 2026-10-30

### Added

- **Review with Claude.** A long item that
  continues on a second line.
- Another one with `code`.

### Fixed

- A bug.

## [0.5.0] - 2026-10-29

### Notes

- Only notes here.
"""

@Test func theReleasesComeInTheOrderOfTheFileWithoutTheOnesNotOutYet() {
    let releases = Changelog.parse(sample)

    #expect(releases.map(\.version) == ["0.6.0", "0.5.0"])
    #expect(releases.map(\.date) == ["2026-10-30", "2026-10-29"])
}

@Test func eachReleaseKeepsItsSectionsAndItems() {
    let latest = Changelog.parse(sample)[0]

    #expect(latest.sections.map(\.title) == ["Added", "Fixed"])
    #expect(latest.sections[0].items.count == 2)
    #expect(latest.sections[1].items == ["A bug."])
}

@Test func anItemThatContinuesOnTheNextLineIsOneItem() {
    let item = Changelog.parse(sample)[0].sections[0].items[0]

    #expect(item == "**Review with Claude.** A long item that continues on a second line.")
}

@Test func aReleaseWithoutADateStillCounts() {
    let releases = Changelog.parse("## [1.0.0]\n\n### Added\n\n- First.\n")

    #expect(releases == [ChangelogRelease(version: "1.0.0", date: nil, sections: [ChangelogSection(title: "Added", items: ["First."])])])
}

@Test func textWithoutReleasesGivesNothing() {
    #expect(Changelog.parse("").isEmpty)
    #expect(Changelog.parse("# Changelog\n\nJust words.\n").isEmpty)
}

@Test func theRealChangelogOfThisRepositoryIsRead() throws {
    let file = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("CHANGELOG.md")
    let releases = Changelog.parse(try String(contentsOf: file, encoding: .utf8))

    #expect(releases.count >= 10)
    #expect(releases.allSatisfy { !$0.sections.isEmpty })
    #expect(releases.first?.date != nil)
}
