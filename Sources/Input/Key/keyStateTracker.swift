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
    case endMatch(RecordMode) // 从匹配变为不匹配
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

    /// 自由模式：是否正在录音（toggle 状态）
    private var isFreeRecording: Bool = false
    /// 自由模式：上一次检测时 free 按键是否匹配
    private var wasFreeKeyMatched: Bool = false

    private var keyConfigs: [KeyConfig] = [
        KeyConfig(keyCodes: Config.shared.USER_CONFIG.normalKeyCodes, description: "normal", mode: .normal),
        KeyConfig(keyCodes: Config.shared.USER_CONFIG.commandKeyCodes, description: "command", mode: .command),
        KeyConfig(keyCodes: Config.shared.USER_CONFIG.freeKeyCodes, description: "free", mode: .free),
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

        EventBus.shared.events
            .filter {
                if case .recordingCancelled = $0 { return true }
                if case .recordingConfirmed = $0 { return true }
                return false
            }
            .sink { [weak self] event in
                self?.isFreeRecording = false
                self?.isCurrentlyMatched = false
                self?.currentActiveMode = nil

                if case .recordingCancelled = event, Config.shared.USER_CONFIG.setting.hideStatusPanel {
                    Task { @MainActor in
                        StatusPanelManager.shared.hidePanel()
                    }
                }
            }
            .store(in: &cancellables)
    }

    /// 处理键盘事件（用于快捷键设置模式）
    /// - Returns: 返回元组 (是否完成快捷键设置, 当前按下的按键组合)
    func handleKeyEvent(type: CGEventType, event: CGEvent) -> (completed: Bool, currentKeys: [Int64]) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        switch type {
        case .flagsChanged:
            let result = handleModifierChange(keyCode: keyCode, newModifiers: event.flags)
            if let completedKeys = result.keys {
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

        var isKeyDown = false
        switch type {
        case .flagsChanged:
            let result = handleModifierChange(keyCode: keyCode, newModifiers: event.flags)
            isKeyDown = result.isPressed

        case .keyDown:
            addKey(keyCode)

        case .keyUp:
            removeKey(keyCode)
            // return isFreeRecording || isCurrentlyMatched ? .stillMatching : .notMatching

        default:
            break
        }

        return checkMatchStatus(isKeyDown: type == .keyDown ? true : isKeyDown)
    }

    private func handleModifierChange(keyCode: Int64, newModifiers: CGEventFlags) -> (keys: [Int64]?, isPressed: Bool) {
        let isPressed = modifierMasks.contains { newModifiers.contains($0) && !currentModifiers.contains($0) }
        let isReleased = modifierMasks.contains { !newModifiers.contains($0) && currentModifiers.contains($0) }

        if isPressed {
            addKey(keyCode)
            currentModifiers = newModifiers
            return (nil, true) // 按下状态
        } else if isReleased {
            let keysBeforeRemove = Array(pressedKeys)
            removeKey(keyCode)
            currentModifiers = newModifiers
            return (keysBeforeRemove, false) // 松开状态，返回松开前的完整快捷键组合
        }

        currentModifiers = newModifiers
        return (nil, false) // 无变化
    }

    private func addKey(_ keyCode: Int64) {
        pressedKeys.insert(keyCode)
    }

    private func removeKey(_ keyCode: Int64) {
        pressedKeys.remove(keyCode)
    }

    // private func

    private func checkMatchStatus(isKeyDown: Bool) -> KeyMatchResult {
        // 统一查找所有匹配的配置
        let matchedConfigs = keyConfigs
            .filter { Set($0.keyCodes).isSubset(of: pressedKeys) }

        let normalConfig = matchedConfigs.first { $0.mode == .normal }
        let isNormalKeyMatched = normalConfig != nil

        if isFreeRecording && isNormalKeyMatched && isKeyDown {
            log.debug("自由模式下普通模式匹配, 停止录音".yellow)
            isFreeRecording = false
            isCurrentlyMatched = false
            currentActiveMode = nil
            return .endMatch(currentActiveMode ?? .normal)
        }

        let freeConfig = matchedConfigs.first { $0.mode == .free }
        let isFreeKeyMatched = freeConfig != nil

        // 自由模式：检测按键按下（从不匹配变为匹配）来 toggle 状态
        // 命令模式下不允许切换到自由模式
        if !wasFreeKeyMatched, isFreeKeyMatched, currentActiveMode != .command {
            wasFreeKeyMatched = true
            // 模式升级
            if currentActiveMode == .normal {
                log.info("🔄 模式升级: normal → free")
                currentActiveMode = .free
                isFreeRecording = true
                return .modeUpgrade(from: .normal, to: .free)
            }

            isFreeRecording.toggle()
            if isFreeRecording {
                log.info("🎯 自由模式开始录音")
                isCurrentlyMatched = true
                currentActiveMode = .free
                return .startMatch(.free)
            } else {
                log.info("❌ 自由模式停止录音")
                isCurrentlyMatched = false
                currentActiveMode = nil
                return .endMatch(currentActiveMode ?? .normal)
            }
        }
        wasFreeKeyMatched = isFreeKeyMatched

        // 如果正在自由录音，忽略其他按键状态
        if isFreeRecording {
            return .stillMatching
        }

        // 没有按键按下
        if pressedKeys.isEmpty {
            if isCurrentlyMatched {
                isCurrentlyMatched = false
                currentActiveMode = nil
                return .endMatch(currentActiveMode ?? .normal)
            }
            return .notMatching
        }

        // 从已匹配的配置中找 normal/command 模式的最精确匹配
        let matchedConfig = matchedConfigs
            .filter { $0.mode != .free }
            .max(by: { $0.keyCodes.count < $1.keyCodes.count })

        let isNowMatched = matchedConfig != nil
        let newMode = matchedConfig?.mode

        if isNowMatched, !isCurrentlyMatched {
            // 从不匹配变为匹配 -> 检查防抖
            let currentTime = Date().timeIntervalSince1970
            let timeSinceLastStart = currentTime - lastStartMatchTime

            // 双击检测：normal 模式 0.5 秒内再次触发 -> 升级到 free 模式
            if newMode == .normal, timeSinceLastStart < 0.5, lastStartMatchTime > 0 {
                log.info("🎯 双击普通模式，升级到自由模式")
                isFreeRecording = true
                isCurrentlyMatched = true
                currentActiveMode = .free
                lastStartMatchTime = currentTime
                return .modeUpgrade(from: .normal, to: .free)
            }

            if timeSinceLastStart < 1.0 {
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
            let mode = currentActiveMode!
            currentActiveMode = nil
            return .endMatch(mode)

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
        isFreeRecording = false
        wasFreeKeyMatched = false
    }

    func reloadKeyConfigs() {
        keyConfigs = [
            KeyConfig(keyCodes: Config.shared.USER_CONFIG.normalKeyCodes, description: "normal", mode: .normal),
            KeyConfig(keyCodes: Config.shared.USER_CONFIG.commandKeyCodes, description: "command", mode: .command),
            KeyConfig(keyCodes: Config.shared.USER_CONFIG.freeKeyCodes, description: "free", mode: .free),
        ]
        log.info("✅ KeyStateTracker reload key configs")
    }
}
