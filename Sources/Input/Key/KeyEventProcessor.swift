//
//  KeyEventProcessor.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/15.
//

import Carbon
import Cocoa
import Foundation

enum RecordMode: String {
    case normal
    case command
    case free
    case persona
}

struct KeyConfig {
    let keyCodes: [Int64] // 按键键码数组
    let description: String // 配置描述
    let mode: RecordMode

    init(keyCodes: [Int64], description: String, mode: RecordMode) {
        self.keyCodes = keyCodes.sorted()
        self.description = description
        self.mode = mode
    }
}

class KeyEventProcessor {
    var isHotkeySetting = false
    var hotkeySettingMode: RecordMode = .normal
    var isHotkeyDetecting = false

    private var keyStateTracker: KeyStateTracker = .init()

    func startHotkeySetting(mode: RecordMode) {
        log.info("Hotkey setting start: \(mode)")

        keyStateTracker.clear()
        isHotkeySetting = true
        hotkeySettingMode = mode
    }

    func endHotkeySetting() {
        guard isHotkeySetting else { return }

        log.info("Hotkey setting done")

        isHotkeySetting = false
    }

    func startHotkeyDetect() {
        log.info("Hotkey detect start")
        keyStateTracker.clear()
        isHotkeyDetecting = true
    }

    func endHotkeyDetect() {
        guard isHotkeyDetecting else { return }
        log.info("Hotkey detect done")
        isHotkeyDetecting = false
    }

    func handleHotkeyDetectEvent(type: CGEventType, event: CGEvent) {
        guard isHotkeyDetecting else { return }

        let (isCompleted, currentKeys) = keyStateTracker.handleKeyEvent(type: type, event: event)
        let hotkeyCombination = currentKeys.compactMap { KeyMapper.keyCodeMap[$0] }
        log.info("Hotkey detect updated: \(hotkeyCombination), isCompleted: \(isCompleted)")
        EventBus.shared.publish(.hotkeyDetectUpdated(hotkeyCombination: hotkeyCombination, isCompleted: isCompleted))
    }

    func handleHotkeySettingEvent(type: CGEventType, event: CGEvent) {
        guard isHotkeySetting else { return }

        let (completed, currentKeys) = keyStateTracker.handleKeyEvent(type: type, event: event)

        // 实时发送当前按键组合
        let hotkeyCombination = currentKeys.compactMap { KeyMapper.keyCodeMap[$0] }
        log.info("Hotkey setting updated: \(hotkeyCombination), completed: \(completed)")
        EventBus.shared.publish(.hotkeySettingUpdated(mode: hotkeySettingMode, hotkeyCombination: hotkeyCombination))

        if completed {
            let newKeyCodes = hotkeyCombination.compactMap { KeyMapper.stringToKeyCodeMap[$0] }.sorted()
            var otherKeyCodesList: [[Int64]] = []

            if hotkeySettingMode != .normal {
                otherKeyCodesList.append(Config.shared.USER_CONFIG.normalKeyCodes.sorted())
            }
            if hotkeySettingMode != .command {
                otherKeyCodesList.append(Config.shared.USER_CONFIG.commandKeyCodes.sorted())
            }
            if hotkeySettingMode != .free {
                otherKeyCodesList.append(Config.shared.USER_CONFIG.freeKeyCodes.sorted())
            }
            if hotkeySettingMode != .persona {
                otherKeyCodesList.append(Config.shared.USER_CONFIG.personaKeyCodes.sorted())
            }

            let isConflict = otherKeyCodesList.contains { $0 == newKeyCodes }

            if !isConflict {
                Config.shared.saveHotkeySetting(mode: hotkeySettingMode, hotkeyCombination: hotkeyCombination)
            }

            EventBus.shared.publish(.hotkeySettingResulted(mode: hotkeySettingMode, hotkeyCombination: hotkeyCombination, isConflict: isConflict))
        }
    }

    func handlekeyEvent(type: CGEventType, event: CGEvent) -> KeyMatchResult {
        keyStateTracker.handleKeyEventWithMatch(type: type, event: event)
    }
}
