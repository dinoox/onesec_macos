//
//  keyStateTracker.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/15.
//

import CoreGraphics
import Foundation

/// 追踪按键状态，用于快捷键设置和按键监测
class KeyStateTracker {
    private var pressedKeys: [Int64] = []
    private var currentModifiers: CGEventFlags = []
    
    private let modifierMasks: [CGEventFlags] = [.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn]
    
    /// 处理键盘事件
    /// - Returns: 当松开键时返回完整的快捷键组合，否则返回 nil
    func handleKeyEvent(type: CGEventType, event: CGEvent) -> [Int64]? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        
        switch type {
        case .flagsChanged:
            return handleModifierChange(keyCode: keyCode, newModifiers: event.flags)
            
        case .keyDown:
            addKey(keyCode)
            
        case .keyUp:
            // 松开普通键时，如果有修饰键被按下，则完成快捷键设置
            removeKey(keyCode)
            return currentModifiers.isEmpty ? nil : pressedKeys
            
        default:
            break
        }
        
        return nil
    }
    
    private func handleModifierChange(keyCode: Int64, newModifiers: CGEventFlags) -> [Int64]? {
        let isPressed = modifierMasks.contains { newModifiers.contains($0) && !currentModifiers.contains($0) }
        let isReleased = modifierMasks.contains { !newModifiers.contains($0) && currentModifiers.contains($0) }
        
        if isPressed {
            addKey(keyCode)
        } else if isReleased {
            removeKey(keyCode)
            currentModifiers = newModifiers
            return pressedKeys // 松开修饰键时返回快捷键组合
        }
        
        currentModifiers = newModifiers
        return nil
    }
    
    private func addKey(_ keyCode: Int64) {
        log.info("⬇️ 按下: \(KeyMapper.keyCodeToString(keyCode))")
        if !pressedKeys.contains(keyCode) {
            pressedKeys.append(keyCode)
        }
    }
    
    private func removeKey(_ keyCode: Int64) {
        log.info("⬆️ 松开: \(KeyMapper.keyCodeToString(keyCode))")
        pressedKeys.removeAll { $0 == keyCode }
    }
    
    /// 清空所有按键状态
    func clear() {
        pressedKeys.removeAll()
        currentModifiers = []
    }
    
    /// 获取当前按下的所有键码
    func getCurrentPressedKeys() -> [Int64]? {
        pressedKeys.isEmpty ? nil : pressedKeys
    }
}
