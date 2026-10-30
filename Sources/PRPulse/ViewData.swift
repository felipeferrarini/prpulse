import Foundation
import PRPulseCore

struct ViewData {
    var state: LoadState = .idle
    var summary: Summary?
    var lastUpdated: Date?
    var isOffline = false
    var freshUntil: Date?
    var isSetupComplete = true
    var orgs: [String] = []

    /// The organizations as the header and the menu name them: both of two, a count for more.
    var orgLabel: String { OrganizationLabel.text(for: orgs) }
    var showsOwner: Bool { orgs.count > 1 }
}

enum OrganizationLabel {
    static func text(for orgs: [String]) -> String {
        switch orgs.count {
        case 0: ""
        case 1, 2: orgs.joined(separator: ", ")
        default: tr("popover.orgs.count", orgs.count)
        }
    }
}
