import SwiftUI

@main
struct PRPulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    /// The app has no scene of its own: the popover and the windows are AppKit. A menu bar extra that is never
    /// inserted keeps the SwiftUI lifecycle (and the standard Edit menu shortcuts) without opening any window.
    var body: some Scene {
        MenuBarExtra("PRPulse", systemImage: "arrow.triangle.branch", isInserted: .constant(false)) { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var runtime: AppRuntime?
    private var popover: PopoverController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let runtime = AppRuntime()
        self.runtime = runtime
        popover = PopoverController(runtime: runtime)
    }
}
