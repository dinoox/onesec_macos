import AppKit

@MainActor
class MenuBuilder {
    private let onShortcutSettings: () -> Void
    
    init(onShortcutSettings: @escaping () -> Void) {
        self.onShortcutSettings = onShortcutSettings
    }
    
    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        
        let shortcutItem = NSMenuItem(
            title: "快捷键设置",
            action: #selector(handleShortcutSettings),
            keyEquivalent: "")
        shortcutItem.target = self
        menu.addItem(shortcutItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(
                title: "退出",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"))
        
        return menu
    }
    
    @objc private func handleShortcutSettings() {
        onShortcutSettings()
    }
    
    func showMenu(in view: NSView) {
        let menu = buildMenu()
        let location = view.bounds.origin
        menu.popUp(positioning: nil, at: location, in: view)
    }
}

