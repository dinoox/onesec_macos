import AppKit
import CoreAudio

@MainActor
final class MenuBuilder {
    static let shared = MenuBuilder()
    private var overlay: OverlayController { OverlayController.shared }

    @objc private func handleTranslateModeToggle() {
        if Config.shared.TEXT_PROCESS_MODE == .translate {
            Config.shared.TEXT_PROCESS_MODE = .auto
        } else {
            Config.shared.TEXT_PROCESS_MODE = .translate
        }
    }

    @objc private func handleAudioDeviceChange(_ sender: NSMenuItem) {
        let deviceID = AudioDeviceID(sender.tag)
        if deviceID == 0 {
            AudioDeviceManager.shared.selectedDeviceID = nil
        } else {
            AudioDeviceManager.shared.selectedDeviceID = deviceID
        }
    }

    func showMenu(in view: NSView) {
        let menu = NSMenu()

        // 音频设备选择
        let audioItem = NSMenuItem(title: "音频输入", action: nil, keyEquivalent: "")
        let audioSubmenu = NSMenu()

        AudioDeviceManager.shared.refreshDevices()
        let devices = AudioDeviceManager.shared.inputDevices
        let selectedID = AudioDeviceManager.shared.selectedDeviceID

        // 系统默认选项
        let defaultItem = NSMenuItem(title: "系统默认", action: #selector(handleAudioDeviceChange(_:)), keyEquivalent: "")
        defaultItem.target = self
        defaultItem.tag = 0
        defaultItem.state = selectedID == nil ? .on : .off
        audioSubmenu.addItem(defaultItem)
        audioSubmenu.addItem(NSMenuItem.separator())

        for device in devices {
            let title = device.isDefault ? "\(device.name) (默认)" : device.name
            let item = NSMenuItem(title: title, action: #selector(handleAudioDeviceChange(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(device.id)
            item.state = selectedID == device.id ? .on : .off
            audioSubmenu.addItem(item)
        }

        audioItem.submenu = audioSubmenu
        menu.addItem(audioItem)
        menu.addItem(NSMenuItem.separator())

        let translateItem = NSMenuItem(title: "翻译模式", action: #selector(handleTranslateModeToggle), keyEquivalent: "")
        translateItem.target = self
        translateItem.state = Config.shared.TEXT_PROCESS_MODE == .translate ? .on : .off
        menu.addItem(translateItem)

        menu.update()
        let location = NSPoint(x: view.bounds.midX - menu.size.width / 2, y: 40)
        menu.popUp(positioning: nil, at: location, in: view)
    }
}
