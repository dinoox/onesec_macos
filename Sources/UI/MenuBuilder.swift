import AppKit

@MainActor
final class MenuBuilder {
    static let shared = MenuBuilder()
    private var overlay: OverlayController { OverlayController.shared }

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
        let menu = NSMenu()

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

        menu.update()
        let location = NSPoint(x: view.bounds.midX - menu.size.width / 2, y: 40)
        menu.popUp(positioning: nil, at: location, in: view)
    }
}
