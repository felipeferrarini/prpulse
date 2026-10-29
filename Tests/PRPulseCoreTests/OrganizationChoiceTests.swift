import Testing
@testable import PRPulseCore

@Test func keepsTheCurrentOrganizationWhenItIsAvailable() {
    #expect(OrganizationChoice.resolve(current: "acme", available: ["acme", "me"], defaultChoice: "me", autoPick: true) == .keep)
    #expect(OrganizationChoice.resolve(current: "acme", available: ["acme", "me"], defaultChoice: "me", autoPick: false) == .keep)
}

@Test func picksTheDefaultWhenNothingWasChosenYet() {
    #expect(OrganizationChoice.resolve(current: "", available: ["acme", "me"], defaultChoice: "acme", autoPick: false) == .pick("acme"))
}

@Test func picksTheDefaultWhenAutoPickIsAllowed() {
    #expect(OrganizationChoice.resolve(current: "gone", available: ["acme"], defaultChoice: "acme", autoPick: true) == .pick("acme"))
}

@Test func reportsMissingInsteadOfSilentlySwitchingWhenAutoPickIsOff() {
    #expect(OrganizationChoice.resolve(current: "gone", available: ["acme"], defaultChoice: "acme", autoPick: false) == .missing("gone"))
}
