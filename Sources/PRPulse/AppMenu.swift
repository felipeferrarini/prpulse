import AppKit

/// The menu bar of the app while its windows are open: Quit, the editing commands the text fields need, and Close.
@MainActor
enum AppMenu {
    private static var isInstalled = false

    static func installOnce() {
        guard !isInstalled else { return }
        isInstalled = true
        let menu = NSMenu()
        menu.addItem(submenu(appName, [
            item(tr("appmenu.quit", appName), #selector(NSApplication.terminate(_:)), "q"),
        ]))
        menu.addItem(submenu(tr("appmenu.edit"), [
            item(tr("appmenu.undo"), Selector(("undo:")), "z"),
            item(tr("appmenu.redo"), Selector(("redo:")), "Z"),
            .separator(),
            item(tr("appmenu.cut"), #selector(NSText.cut(_:)), "x"),
            item(tr("appmenu.copy"), #selector(NSText.copy(_:)), "c"),
            item(tr("appmenu.paste"), #selector(NSText.paste(_:)), "v"),
            item(tr("appmenu.selectAll"), #selector(NSText.selectAll(_:)), "a"),
        ]))
        menu.addItem(submenu(tr("appmenu.window"), [
            item(tr("appmenu.close"), #selector(NSWindow.performClose(_:)), "w"),
            item(tr("appmenu.minimize"), #selector(NSWindow.performMiniaturize(_:)), "m"),
        ]))
        NSApp.mainMenu = menu
    }

    private static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "PRPulse"
    }

    private static func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        NSMenuItem(title: title, action: action, keyEquivalent: key)
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let submenu = NSMenu(title: title)
        items.forEach(submenu.addItem)
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.submenu = submenu
        return holder
    }
}
