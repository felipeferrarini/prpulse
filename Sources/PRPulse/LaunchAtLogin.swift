import ServiceManagement
import SwiftUI

enum LaunchAtLogin {
    static func apply(_ enabled: Bool) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let service = SMAppService.mainApp
        if enabled { try? service.register() } else { try? service.unregister() }
    }
}
