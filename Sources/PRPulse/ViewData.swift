import Foundation
import PRPulseCore

struct ViewData {
    var state: LoadState = .idle
    var summary: Summary?
    var lastUpdated: Date?
    var isOffline = false
    var freshUntil: Date?
    var isSetupComplete = true
}
