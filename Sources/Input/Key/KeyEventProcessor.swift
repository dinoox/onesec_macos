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

    func handleHotkeySettingEvent(type: CGEventType, event: CGEvent) {
        guard isHotkeySetting else { return }

        let (completed, currentKeys) = keyStateTracker.handleKeyEvent(type: type, event: event)

        // 实时发送当前按键组合
        let hotkeyCombination = currentKeys.compactMap { KeyMapper.keyCodeMap[$0] }
        EventBus.shared.publish(.hotkeySettingUpdated(mode: hotkeySettingMode, hotkeyCombination: hotkeyCombination))

        // 如果完成了快捷键设置
        if completed {
            // 检测是否与另一个模式的快捷键冲突
            let newKeyCodes = hotkeyCombination.compactMap { KeyMapper.stringToKeyCodeMap[$0] }.sorted()
            let otherKeyCodes: [Int64]
            
            if hotkeySettingMode == .normal {
                otherKeyCodes = Config.shared.COMMAND_KEY_CODES.sorted()
            } else {
                otherKeyCodes = Config.shared.NORMAL_KEY_CODES.sorted()
            }
            
            let isConflict = newKeyCodes == otherKeyCodes
            
            // 只有不冲突时才保存
            if !isConflict {
                Config.shared.saveHotkeySetting(mode: hotkeySettingMode, hotkeyCombination: hotkeyCombination)
            }
            
            EventBus.shared.publish(.hotkeySettingResulted(mode: hotkeySettingMode, hotkeyCombination: hotkeyCombination, isConflict: isConflict))
            endHotkeySetting()
        }
    }

    func handlekeyEvent(type: CGEventType, event: CGEvent) -> KeyMatchResult {
        keyStateTracker.handleKeyEventWithMatch(type: type, event: event)
    }
}
