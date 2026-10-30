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
    #expect(defaults.orgs.isEmpty)
    #expect(defaults.popoverLayout == .single)
}

@Test func settingsRoundTripAndCorruptDataFallsBack() {
    let suite = freshDefaults()
    let store = SettingsStore(defaults: suite)
    #expect(store.settings == AppSettings.defaults)

    var changed = AppSettings.defaults
    changed.orgs = ["acme"]
    changed.ignoredRepos = ["acme/docs"]
    changed.refreshMinutes = 10
    store.settings = changed
    #expect(SettingsStore(defaults: suite).settings == changed)

    suite.set(Data("not json".utf8), forKey: SettingsStore.key)
    #expect(SettingsStore(defaults: suite).settings == AppSettings.defaults)
}

@Test func settingsDecodeKeepsDefaultsForMissingKeys() throws {
    let partial = Data(#"{"org":"acme"}"#.utf8)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: partial)

    #expect(decoded.orgs == ["acme"])
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

@Test func automaticUpdatesAreOnByDefaultAndCanBeTurnedOff() throws {
    #expect(AppSettings.defaults.automaticUpdates)

    let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"org":"acme"}"#.utf8))
    #expect(old.automaticUpdates)

    var settings = AppSettings.defaults
    settings.automaticUpdates = false
    let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
    #expect(!decoded.automaticUpdates)
}

@Test func globalShortcutIsOnByDefaultAndSurvivesARoundTrip() throws {
    #expect(AppSettings.defaults.globalShortcut)
    let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"org":"acme"}"#.utf8))
    #expect(old.globalShortcut)

    var settings = AppSettings.defaults
    settings.globalShortcut = false
    let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
    #expect(!decoded.globalShortcut)
}

@Test func settingsSavedWithOneOrganizationBecomeAListAndQualifyTheIgnoredRepositories() throws {
    let old = Data(#"{"org":"acme","ignoredRepos":["docs","infra"]}"#.utf8)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: old)

    #expect(decoded.orgs == ["acme"])
    #expect(decoded.ignoredRepos == ["acme/docs", "acme/infra"])

    let encoded = String(data: try JSONEncoder().encode(decoded), encoding: .utf8)!
    #expect(!encoded.contains("\"org\":"))
}

@Test func organizationsAndQualifiedRepositoriesSurviveARoundTrip() throws {
    var settings = AppSettings.defaults
    settings.orgs = ["acme", "orbit"]
    settings.ignoredRepos = ["acme/docs", "orbit/web"]
    let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))

    #expect(decoded == settings)
    #expect(decoded.ignoredRepositories(in: "ORBIT") == ["web"])
    #expect(decoded.ignoredRepositories(in: "acme") == ["docs"])
    #expect(decoded.ignoredRepositories(in: "other").isEmpty)
}

@Test func waitingReviewDaysDefaultToTwoAndSurvive() throws {
    #expect(AppSettings.defaults.waitingReviewDays == 2)
    let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"org":"acme"}"#.utf8))
    #expect(old.waitingReviewDays == 2)

    var settings = AppSettings.defaults
    settings.waitingReviewDays = 0
    let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
    #expect(decoded.waitingReviewDays == 0)
}
