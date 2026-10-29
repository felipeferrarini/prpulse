import PRPulseCore
import SwiftUI

@main
struct PRPulseApp: App {
    @StateObject private var runtime = AppRuntime()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(
                data: runtime.data,
                onRefresh: { runtime.refresh() },
                onSettings: { runtime.openSettings() }
            )
        } label: {
            Image(nsImage: StatusIconRenderer.image(for: runtime.iconState, phase: runtime.pulsePhase))
        }
        .menuBarExtraStyle(.window)
    }
}
