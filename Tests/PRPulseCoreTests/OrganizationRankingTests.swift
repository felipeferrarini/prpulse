import Foundation
import Testing
@testable import PRPulseCore

private func activity(_ login: String, _ count: Int, _ day: Int? = nil) -> OrganizationActivity {
    OrganizationActivity(login: login, recentPullRequests: count, lastActivity: day.map { Date(timeIntervalSince1970: Double($0) * 86_400) })
}

@Test func moreActiveOrganizationComesFirst() {
    let order = OrganizationRanking.order([activity("quiet", 2, 50), activity("busy", 40, 10)])

    #expect(order == ["busy", "quiet"])
}

@Test func tieIsBrokenByTheMostRecentActivity() {
    let order = OrganizationRanking.order([activity("older", 5, 10), activity("newer", 5, 30)])

    #expect(order == ["newer", "older"])
}

@Test func organizationsWithoutActivityFallBackToTheirName() {
    let order = OrganizationRanking.order([activity("zeta", 0), activity("Alpha", 0), activity("beta", 0)])

    #expect(order == ["Alpha", "beta", "zeta"])
}

@Test func organizationWithoutLastActivityComesAfterOneWithIt() {
    let order = OrganizationRanking.order([activity("never", 0), activity("seen", 0, 5)])

    #expect(order == ["seen", "never"])
}
