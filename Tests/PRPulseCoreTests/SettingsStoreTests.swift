import Foundation
import Testing
@testable import PRPulseCore

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "prpulse-tests-\(UUID().uuidString)")!
}

@Test func defaultsMatchSpec() {
    let defaults = AppSettings.defaults

    #expect(defaults.refreshMinutes == 5)
    #expect(defaults.ignoredBots == ["coderabbitai", "sonarqubecloud"])
    #expect(defaults.ignoredRepos.isEmpty)
    #expect(defaults.notificationsEnabled)
    #expect(!defaults.launchAtLogin)
    #expect(!defaults.hasCompletedSetup)
    #expect(defaults.authSource == .ghCli)
    #expect(defaults.org == "")
    #expect(defaults.popoverLayout == .single)
}

@Test func settingsRoundTripAndCorruptDataFallsBack() {
    let suite = freshDefaults()
    let store = SettingsStore(defaults: suite)
    #expect(store.settings == AppSettings.defaults)

    var changed = AppSettings.defaults
    changed.org = "acme"
    changed.ignoredRepos = ["docs"]
    changed.refreshMinutes = 10
    store.settings = changed
    #expect(SettingsStore(defaults: suite).settings == changed)

    suite.set(Data("not json".utf8), forKey: SettingsStore.key)
    #expect(SettingsStore(defaults: suite).settings == AppSettings.defaults)
}

@Test func settingsDecodeKeepsDefaultsForMissingKeys() throws {
    let partial = Data(#"{"org":"acme"}"#.utf8)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: partial)

    #expect(decoded.org == "acme")
    #expect(decoded.refreshMinutes == 5)
    #expect(decoded.ignoredBots == ["coderabbitai", "sonarqubecloud"])
}

@Test func popoverLayoutSurvivesARoundTripAndOldDataFallsBackToSingle() throws {
    var settings = AppSettings.defaults
    settings.popoverLayout = .split
    let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
    #expect(decoded.popoverLayout == .split)

    let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"org":"acme"}"#.utf8))
    #expect(old.popoverLayout == .single)
}
