import AppKit

@MainActor
class MenuBuilder {
    private var settingsPanelId: UUID?
    private let overlay = OverlayController.shared

    @objc private func handleShortcutSettings() {
        if let panelId = settingsPanelId, overlay.isVisible(uuid: panelId) {
            overlay.hideOverlay(uuid: panelId)
            settingsPanelId = nil
        } else {
            let uuid = overlay.showOverlay { [weak self] _ in
                ShortcutSettingsCard(onClose: {
                    if let panelId = self?.settingsPanelId {
                        self?.overlay.hideOverlay(uuid: panelId)
                        self?.settingsPanelId = nil
                    }
                })
            }
            settingsPanelId = uuid
        }
    }

    @objc private func handleTextModeChange(_ sender: NSMenuItem) {
        let modes: [TextProcessMode] = [.auto, .format]
        guard sender.tag < modes.count else { return }
        Config.shared.TEXT_PROCESS_MODE = modes[sender.tag]
    }

    @objc private func handleTranslateModeToggle() {
        if Config.shared.TEXT_PROCESS_MODE == .translate {
            Config.shared.TEXT_PROCESS_MODE = .auto
        } else {
            Config.shared.TEXT_PROCESS_MODE = .translate
        }
    }

    func showMenu(in view: NSView) {
        guard let event = NSApp.currentEvent else { return }
        
        let menu = NSMenu()
        
        let shortcutItem = NSMenuItem(title: "快捷键设置", action: #selector(handleShortcutSettings), keyEquivalent: "")
        shortcutItem.target = self
        menu.addItem(shortcutItem)
        menu.addItem(NSMenuItem.separator())
        
        let textModeItem = NSMenuItem(title: "识别风格", action: nil, keyEquivalent: "")
        let textModeSubmenu = NSMenu()
        let modes: [(mode: TextProcessMode, tag: Int)] = [(.auto, 0), (.format, 1)]
        
        for (index, (mode, tag)) in modes.enumerated() {
            let menuItem = NSMenuItem(title: mode.displayName, action: #selector(handleTextModeChange(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.tag = tag
            menuItem.state = Config.shared.TEXT_PROCESS_MODE == mode ? .on : .off
            textModeSubmenu.addItem(menuItem)
            
            let descItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            descItem.attributedTitle = NSMutableAttributedString(string: mode.description)
            descItem.isEnabled = false
            textModeSubmenu.addItem(descItem)
            
            if index < modes.count - 1 {
                textModeSubmenu.addItem(NSMenuItem.separator())
            }
        }
        
        textModeItem.submenu = textModeSubmenu
        menu.addItem(textModeItem)
        
        let currentModeDescItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let currentModeText = Config.shared.TEXT_PROCESS_MODE == .translate ? "无识别风格" : "\(Config.shared.TEXT_PROCESS_MODE.displayName) \(Config.shared.TEXT_PROCESS_MODE.description)"
        currentModeDescItem.attributedTitle = NSMutableAttributedString(string: currentModeText)
        currentModeDescItem.isEnabled = false
        menu.addItem(currentModeDescItem)
        menu.addItem(NSMenuItem.separator())
        
        let translateItem = NSMenuItem(title: "翻译模式", action: #selector(handleTranslateModeToggle), keyEquivalent: "")
        translateItem.target = self
        translateItem.state = Config.shared.TEXT_PROCESS_MODE == .translate ? .on : .off
        menu.addItem(translateItem)
        menu.addItem(NSMenuItem.separator())
        
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }
}
