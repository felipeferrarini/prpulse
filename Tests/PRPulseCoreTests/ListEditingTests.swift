import Testing
@testable import PRPulseCore

@Test func addTrimsAndAppends() {
    #expect(ListEditing.adding("  docs ", to: ["app"], kind: .repository) == ["app", "docs"])
}

@Test func addIgnoresEmptyAndDuplicatesCaseInsensitively() {
    #expect(ListEditing.adding("   ", to: ["app"], kind: .repository) == ["app"])
    #expect(ListEditing.adding("APP", to: ["app"], kind: .repository) == ["app"])
}

@Test func repositoryNameDropsTheOwnerPrefix() {
    #expect(ListEditing.adding("acme/docs", to: [], kind: .repository) == ["docs"])
}

@Test func botNameDropsAtSignAndBotSuffix() {
    #expect(ListEditing.adding("@dependabot[bot]", to: [], kind: .account) == ["dependabot"])
    #expect(ListEditing.adding("renovate[bot]", to: [], kind: .account) == ["renovate"])
}

@Test func addSplitsCommaSeparatedInput() {
    #expect(ListEditing.adding("a, b ,c", to: ["x"], kind: .repository) == ["x", "a", "b", "c"])
}

@Test func removeIsCaseInsensitive() {
    #expect(ListEditing.removing("DOCS", from: ["app", "docs"]) == ["app"])
}

@Test func refreshOptionsMatchTheSettingsPicker() {
    #expect(AppSettings.refreshOptions == [1, 2, 5, 10, 15, 30])
    #expect(AppSettings.refreshOptions.contains(AppSettings.defaults.refreshMinutes))
}
