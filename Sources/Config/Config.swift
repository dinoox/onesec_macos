//
//  Config.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/14.
//

// MARK: - 文本处理模式

enum TextProcessMode: String, CaseIterable {
    case auto = "AUTO" // 自动模式
    case raw = "RAW" // 原样输出
    case clean = "CLEAN" // 清理模式
    case format = "FORMAT" // 整理模式

    var displayName: String {
        switch self {
        case .auto:
            "自动模式"
        case .raw:
            "原样输出"
        case .clean:
            "清理模式"
        case .format:
            "整理模式"
        }
    }

    var description: String {
        switch self {
        case .auto:
            "自动选择最佳处理方式"
        case .raw:
            "直接返回 ASR 识别结果，不做任何处理"
        case .clean:
            "清理口语化表达，去除停顿词、重复词"
        case .format:
            "整理文本结构，重组句子，更适合阅读"
        }
    }
}

actor Config {
    static var UDS_CHANNEL: String = ""
    static var SERVER: String = ""
    static var AUTH_TOKEN: String = ""
    static var DEBUG_MODE: Bool = true
    static var NORMAL_KEY_CODES: [Int64] = [63, 49] // 默认 Fn
    static var COMMAND_KEY_CODES: [Int64] = [63, 55] // 默认 Fn+LCmd
    static var TEXT_PROCESS_MODE: TextProcessMode = .auto // 默认自动模式

    static func saveHotkeySetting(mode: RecordMode, hotkeyCombination: [String]) {
        let keyCodes = hotkeyCombination.compactMap { KeyMapper.stringToKeyCodeMap[$0] }
        if mode == .normal {
            NORMAL_KEY_CODES = keyCodes
        } else if mode == .command {
            COMMAND_KEY_CODES = keyCodes
        }

        log.info("Hotkey updated for mode: \(mode), keyCodes: \(keyCodes)")
    }

    static func setTextProcessMode(_ mode: TextProcessMode) {
        TEXT_PROCESS_MODE = mode
        log.info("Text process mode updated to: \(mode.rawValue)")
    }
}
