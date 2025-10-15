//
//  KeyEventProcessor.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/15.
//

import Foundation

enum RecognitionMode {
    case normal
    case command

    var description: String {
        switch self {
        case .normal:
            return "普通识别模式"
        case .command:
            return "命令识别模式"
        }
    }
}

struct KeyConfig {
    let keyCodes: [Int64] // 按键组合的键码数组
    let description: String
    let mode: RecognitionMode

    init(keyCodes: [Int64], description: String, mode: RecognitionMode) {
        self.keyCodes = keyCodes.sorted()
        self.description = description
        self.mode = mode
    }

    /// 检查是否匹配指定的按键组合
    func matches(_ pressedKeys: [Int64]) -> Bool {
        let sortedPressedKeys = Set(pressedKeys.sorted())
        let sortedConfigKeys = Set(keyCodes.sorted())
        return sortedPressedKeys == sortedConfigKeys
    }
}


/// 双模式按键配置
struct DualModeKeyConfig {
    let normalModeConfig: KeyConfig // 普通模式配置
    let commandModeConfig: KeyConfig // 命令模式配置
    
    init(normalKeyCodes: [Int64], commandKeyCodes: [Int64]) {
        let keyMapper = KeyCodeMapper.shared
        
        // 生成普通模式描述
        let normalDescription = normalKeyCodes
            .compactMap { keyMapper.getCharacter(by: $0) }
            .joined(separator: "+")
        
        // 生成命令模式描述
        let commandDescription = commandKeyCodes
            .compactMap { keyMapper.getCharacter(by: $0) }
            .joined(separator: "+")
        
        self.normalModeConfig = KeyConfig(
            keyCodes: normalKeyCodes,
            description: "普通模式 (\(normalDescription))",
            mode: .normal
        )
        self.commandModeConfig = KeyConfig(
            keyCodes: commandKeyCodes,
            description: "命令模式 (\(commandDescription))",
            mode: .command
        )
    }
    
    /// 根据按键组合获取对应的配置
    func getConfig(for pressedKeys: [Int64]) -> KeyConfig? {
        // 优先检查命令模式，确保命令模式具有更高优先级
        if commandModeConfig.matches(pressedKeys) {
            return commandModeConfig
        } else if normalModeConfig.matches(pressedKeys) {
            return normalModeConfig
        }
        return nil
    }
    
    /// 检查是否匹配任何配置的按键组合
    func matchesAny(_ pressedKeys: [Int64]) -> Bool {
        return getConfig(for: pressedKeys) != nil
    }
}
