import AppKit

@MainActor
class MenuBuilder {
    private let onShortcutSettings: () -> Void

    init(onShortcutSettings: @escaping () -> Void) {
        self.onShortcutSettings = onShortcutSettings
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // 快捷键设置
        let shortcutItem = NSMenuItem(
            title: "快捷键设置",
            action: #selector(handleShortcutSettings),
            keyEquivalent: "",
        )
        shortcutItem.target = self
        menu.addItem(shortcutItem)

        menu.addItem(NSMenuItem.separator())

        // 文本处理模式
        let textModeItem = NSMenuItem(title: "识别风格", action: nil, keyEquivalent: "")
        let textModeSubmenu = NSMenu()

        // 创建带描述的菜单项
        let modes: [(mode: TextProcessMode, tag: Int)] = [
            (.auto, 0),
            (.format, 1),
        ]

        for (index, (mode, tag)) in modes.enumerated() {
            // 模式标题
            let menuItem = NSMenuItem(
                title: mode.displayName,
                action: #selector(handleTextModeChange(_:)),
                keyEquivalent: "",
            )
            menuItem.target = self
            menuItem.tag = tag
            menuItem.state = Config.shared.TEXT_PROCESS_MODE == mode ? .on : .off
            textModeSubmenu.addItem(menuItem)

            // 描述文字
            let descItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            let descAttr = NSMutableAttributedString(string: mode.description)
            descItem.attributedTitle = descAttr
            descItem.isEnabled = false
            textModeSubmenu.addItem(descItem)

            // 添加分隔线
            if index < modes.count - 1 {
                textModeSubmenu.addItem(NSMenuItem.separator())
            }
        }

        textModeItem.submenu = textModeSubmenu
        menu.addItem(textModeItem)

        // 风格切换
        let currentModeDescItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let currentModeText = Config.shared.TEXT_PROCESS_MODE == .translate ? "无识别风格" : "\(Config.shared.TEXT_PROCESS_MODE.displayName) \(Config.shared.TEXT_PROCESS_MODE.description)"
        let currentModeAttr = NSMutableAttributedString(string: currentModeText)
        currentModeDescItem.attributedTitle = currentModeAttr
        currentModeDescItem.isEnabled = false
        menu.addItem(currentModeDescItem)

        menu.addItem(NSMenuItem.separator())

        // 翻译模式
        let translateItem = NSMenuItem(
            title: "翻译模式",
            action: #selector(handleTranslateModeToggle),
            keyEquivalent: "",
        )
        translateItem.target = self
        translateItem.state = Config.shared.TEXT_PROCESS_MODE == .translate ? .on : .off
        menu.addItem(translateItem)

        menu.addItem(NSMenuItem.separator())
        return menu
    }

    @objc private func handleShortcutSettings() {
        onShortcutSettings()
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
        // 使用当前事件来显示菜单，这样菜单会自动出现在点击位置附近
        // 这是 macOS 推荐的方式，会自动处理菜单定位和显示动画
        if let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(buildMenu(), with: event, for: view)
        }
    }
}
