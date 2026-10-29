import Testing
@testable import PRPulseCore

@Test func keepsTheCurrentOrganizationWhenItIsAvailable() {
    #expect(OrganizationChoice.resolve(current: "acme", available: ["acme", "me"], isSetup: true) == .keep)
    #expect(OrganizationChoice.resolve(current: "acme", available: ["acme", "me"], isSetup: false) == .keep)
}

@Test func asksForAChoiceWhenNothingWasChosenAndThereAreSeveralOptions() {
    #expect(OrganizationChoice.resolve(current: "", available: ["acme", "me"], isSetup: true) == .choose)
    #expect(OrganizationChoice.resolve(current: "", available: ["acme", "me"], isSetup: false) == .choose)
}

@Test func picksTheOnlyOptionWhenThereIsJustOne() {
    #expect(OrganizationChoice.resolve(current: "", available: ["me"], isSetup: true) == .pick("me"))
}

@Test func asksForAChoiceInsteadOfSilentlySwitchingDuringSetup() {
    #expect(OrganizationChoice.resolve(current: "gone", available: ["acme", "me"], isSetup: true) == .choose)
}

@Test func reportsMissingInsteadOfSilentlySwitchingInSettings() {
    #expect(OrganizationChoice.resolve(current: "gone", available: ["acme", "me"], isSetup: false) == .missing("gone"))
}

@Test func nothingAvailableMeansNothingToChoose() {
    #expect(OrganizationChoice.resolve(current: "", available: [], isSetup: true) == .choose)
}
