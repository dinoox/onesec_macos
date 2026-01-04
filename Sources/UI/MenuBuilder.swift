import AppKit
import CoreAudio

@MainActor
final class MenuBuilder {
    static let shared = MenuBuilder()
    private var overlay: OverlayController { OverlayController.shared }
    private var audioDeviceManager: AudioDeviceManager = .shared
    private var axObserver: AXSelectionObserver { AXSelectionObserver.shared }

    @objc private func handlePersonaSelect(_ sender: NSMenuItem) {
        let personaId = sender.tag
        PersonaScheduler.shared.setPersona(personaId: personaId == 0 ? nil : personaId)
    }

    @objc private func handleAudioDeviceChange(_ sender: NSMenuItem) {
        audioDeviceManager.selectedDeviceID = AudioDeviceID(sender.tag)
    }

    func showMenu(in view: NSView) {
        let menu = NSMenu()

        let currentPersona = Config.shared.CURRENT_PERSONA

        // 音频设备选择
        let audioItem = NSMenuItem(title: "麦克风", action: nil, keyEquivalent: "")
        let audioSubmenu = NSMenu()

        audioDeviceManager.refreshDevices()
        let devices = audioDeviceManager.inputDevices

        for device in devices {
            let item = NSMenuItem(title: device.name, action: #selector(handleAudioDeviceChange(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(device.id)
            item.state = device.isDefault ? .on : .off
            audioSubmenu.addItem(item)
        }

        audioItem.submenu = audioSubmenu
        menu.addItem(audioItem)
        menu.addItem(NSMenuItem.separator())

        // 人设模式选择
        let personaItem = NSMenuItem(title: "人设模式", action: nil, keyEquivalent: "")
        let personaSubmenu = NSMenu()

        // 当前模式描述
        let personas = PersonaScheduler.shared.personas

        // 人设列表
        for persona in personas {
            let item = NSMenuItem(title: persona.name, action: #selector(handlePersonaSelect(_:)), keyEquivalent: "")
            item.target = self
            item.tag = persona.id
            let isSelected = currentPersona?.id == persona.id || (currentPersona == nil && persona.id == 1)
            item.state = isSelected ? .on : .off
            personaSubmenu.addItem(item)
        }

        personaItem.submenu = personaSubmenu
        menu.addItem(personaItem)

        menu.update()
        let location = NSPoint(x: view.bounds.midX - menu.size.width / 2, y: 40)
        menu.popUp(positioning: nil, at: location, in: view)
    }
}
