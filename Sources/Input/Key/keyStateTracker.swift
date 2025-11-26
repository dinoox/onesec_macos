//
//  keyStateTracker.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/15.
//

import Combine
import CoreGraphics
import Foundation

enum KeyMatchResult {
    case startMatch(RecordMode) // 从不匹配变为匹配
    case endMatch // 从匹配变为不匹配
    case stillMatching // 持续匹配
    case notMatching // 持续不匹配
    case modeUpgrade(from: RecordMode, to: RecordMode) // 模式转换
    case throttled(RecordMode) // 防抖限制
}

/// 追踪按键状态
/// 用于快捷键设置与按键监测
class KeyStateTracker {
    private var pressedKeys: Set<Int64> = []
    private var currentModifiers: CGEventFlags = []
    private let modifierMasks: [CGEventFlags] = [.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn]
    private var cancellables = Set<AnyCancellable>()

    /// 当前是否为匹配状态
    private var isCurrentlyMatched: Bool = false

    /// 追踪当前激活的模式
    private var currentActiveMode: RecordMode?

    /// 上次 startMatch 的时间戳 (防抖)
    private var lastStartMatchTime: TimeInterval = 0

    private var keyConfigs: [KeyConfig] = [
        KeyConfig(keyCodes: Config.shared.USER_CONFIG.normalKeyCodes, description: "normal", mode: .normal),
        KeyConfig(keyCodes: Config.shared.USER_CONFIG.commandKeyCodes, description: "command", mode: .command),
    ]

    init() {
        EventBus.shared.events
            .filter {
                if case .hotkeySettingResulted = $0 { return true }
                if case .hotkeySettingEnded = $0 { return true }
                if case .userDataUpdated(.config) = $0 { return true }
                return false
            }
            .sink { [weak self] _ in
                self?.reloadKeyConfigs()
            }
            .store(in: &cancellables)
    }

    /// 处理键盘事件（用于快捷键设置模式）
    /// - Returns: 返回元组 (是否完成快捷键设置, 当前按下的按键组合)
    func handleKeyEvent(type: CGEventType, event: CGEvent) -> (completed: Bool, currentKeys: [Int64]) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        switch type {
        case .flagsChanged:
            let completedKeys = handleModifierChange(keyCode: keyCode, newModifiers: event.flags)
            if let completedKeys {
                // 修饰键松开，完成设置
                return (true, completedKeys)
            }
            // 修饰键按下，返回当前按键组合
            return (false, Array(pressedKeys))

        case .keyDown:
            addKey(keyCode)
            // 按键按下，返回当前按键组合
            return (false, Array(pressedKeys))

        case .keyUp:
            // 松开普通键时，如果有修饰键被按下，则完成快捷键设置
            let keysBeforeRemove = Array(pressedKeys)
            removeKey(keyCode)
            if currentModifiers.isEmpty {
                // 无修饰键，返回当前按键组合
                return (false, Array(pressedKeys))
            } else {
                // 有修饰键，完成设置
                return (true, keysBeforeRemove)
            }

        default:
            break
        }

        return (false, Array(pressedKeys))
    }

    /// 处理键盘事件并检查匹配状态（用于录音控制模式）
    /// - Returns: 返回按键匹配结果
    func handleKeyEventWithMatch(type: CGEventType, event: CGEvent) -> KeyMatchResult {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        switch type {
        case .flagsChanged:
            _ = handleModifierChange(keyCode: keyCode, newModifiers: event.flags)

        case .keyDown:
            addKey(keyCode)

        case .keyUp:
            removeKey(keyCode)

        default:
            break
        }

        return checkMatchStatus()
    }

    private func handleModifierChange(keyCode: Int64, newModifiers: CGEventFlags) -> [Int64]? {
        let isPressed = modifierMasks.contains { newModifiers.contains($0) && !currentModifiers.contains($0) }
        let isReleased = modifierMasks.contains { !newModifiers.contains($0) && currentModifiers.contains($0) }

        if isPressed {
            addKey(keyCode)
        } else if isReleased {
            let keysBeforeRemove = Array(pressedKeys)
            removeKey(keyCode)
            currentModifiers = newModifiers
            return keysBeforeRemove // 返回松开前的完整快捷键组合
        }

        currentModifiers = newModifiers
        return nil
    }

    private func addKey(_ keyCode: Int64) {
        pressedKeys.insert(keyCode)
    }

    private func removeKey(_ keyCode: Int64) {
        pressedKeys.remove(keyCode)
    }

    private func checkMatchStatus() -> KeyMatchResult {
        // 没有按键按下
        if pressedKeys.isEmpty {
            if isCurrentlyMatched {
                isCurrentlyMatched = false
                currentActiveMode = nil
                return .endMatch
            }
            return .notMatching
        }

        // 检查是否匹配任何配置（配置的按键是当前按键的子集）
        // 如果有多个匹配，选择按键数量最多的配置（最具体的匹配）
        let matchedConfig = keyConfigs
            .filter { config in
                Set(config.keyCodes).isSubset(of: pressedKeys)
            }
            .max(by: { $0.keyCodes.count < $1.keyCodes.count })

        let isNowMatched = matchedConfig != nil
        let newMode = matchedConfig?.mode

        if isNowMatched, !isCurrentlyMatched {
            // 从不匹配变为匹配 -> 检查防抖
            let currentTime = Date().timeIntervalSince1970
            if currentTime - lastStartMatchTime < 1.0 {
                log.info("🤡 防抖限制: \(newMode == .normal ? "普通模式" : "命令模式")")
                return .throttled(newMode!)
            }

            log.info("🎯 按键命中\(newMode == .normal ? "普通模式" : "命令模式")")

            isCurrentlyMatched = true
            currentActiveMode = newMode
            lastStartMatchTime = currentTime
            return .startMatch(newMode!)

        } else if !isNowMatched, isCurrentlyMatched {
            // 从匹配变为不匹配 -> 停止录音
            log.info("❌ 按键组合不再匹配: \(currentActiveMode!.rawValue)")

            isCurrentlyMatched = false
            currentActiveMode = nil
            return .endMatch

        } else if isNowMatched, isCurrentlyMatched {
            // 持续匹配状态，但需要检查是否有模式转换
            if let currentMode = currentActiveMode, let newMode, currentMode != newMode {
                // 模式转换发生
                log.info("🔄 模式转换: \(currentMode.rawValue) → \(newMode.rawValue)")

                currentActiveMode = newMode
                return .modeUpgrade(from: currentMode, to: newMode)
            }
            return .stillMatching

        } else {
            return .notMatching
        }
    }

    func clear() {
        pressedKeys.removeAll()
        currentModifiers = []
        isCurrentlyMatched = false
        currentActiveMode = nil
        lastStartMatchTime = 0
    }

    func reloadKeyConfigs() {
        keyConfigs = [
            KeyConfig(keyCodes: Config.shared.USER_CONFIG.normalKeyCodes, description: "normal", mode: .normal),
            KeyConfig(keyCodes: Config.shared.USER_CONFIG.commandKeyCodes, description: "command", mode: .command),
        ]
        log.info("✅ KeyStateTracker reload key configs")
    }
}
