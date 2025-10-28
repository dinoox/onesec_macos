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
            (.raw, 1),
            (.clean, 2),
            (.format, 3),
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
            menuItem.state = Config.TEXT_PROCESS_MODE == mode ? .on : .off
            textModeSubmenu.addItem(menuItem)

            // 描述文字
            let descItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            let descAttr = NSMutableAttributedString(string: mode.description)
            descItem.attributedTitle = descAttr
            descItem.isEnabled = false
            textModeSubmenu.addItem(descItem)

            // 添加分隔线（最后一项除外）
            if index < modes.count - 1 {
                textModeSubmenu.addItem(NSMenuItem.separator())
            }
        }

        textModeItem.submenu = textModeSubmenu
        menu.addItem(textModeItem)

        // 显示当前选择的风格
        let currentModeDescItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let currentModeAttr = NSMutableAttributedString(string: "\(Config.TEXT_PROCESS_MODE.displayName) \(Config.TEXT_PROCESS_MODE.description)")
        currentModeDescItem.attributedTitle = currentModeAttr
        currentModeDescItem.isEnabled = false
        menu.addItem(currentModeDescItem)

        menu.addItem(NSMenuItem.separator())
        return menu
    }

    @objc private func handleShortcutSettings() {
        onShortcutSettings()
    }

    @objc private func handleTextModeChange(_ sender: NSMenuItem) {
        let modes: [TextProcessMode] = [.auto, .raw, .clean, .format]
        guard sender.tag < modes.count else { return }

        let selectedMode = modes[sender.tag]
        Config.setTextProcessMode(selectedMode)

        log.info("切换文本处理模式为: \(selectedMode.displayName)")
    }

    func showMenu(in view: NSView) {
        let menu = buildMenu()
        let location = view.bounds.origin
        menu.popUp(positioning: nil, at: location, in: view)
    }
}
