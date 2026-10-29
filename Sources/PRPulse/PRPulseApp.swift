import SwiftUI

@main
struct PRPulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
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
