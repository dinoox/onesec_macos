//
//  Config.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/14.
//

import Combine

class Config: ObservableObject {
    static let shared = Config()
    
    @Published var UDS_CHANNEL: String = ""
    @Published var SERVER: String = ""
    @Published var AUTH_TOKEN: String = ""
    @Published var DEBUG_MODE: Bool = true
    @Published var NORMAL_KEY_CODES: [Int64] = [63, 49] // 默认 Fn
    @Published var COMMAND_KEY_CODES: [Int64] = [63, 55] // 默认 Fn+LCmd
    @Published var TEXT_PROCESS_MODE: TextProcessMode = .auto // 默认自动
    
    private init() {}

    func saveHotkeySetting(mode: RecordMode, hotkeyCombination: [String]) {
        let keyCodes = hotkeyCombination.compactMap { KeyMapper.stringToKeyCodeMap[$0] }
        if mode == .normal {
            NORMAL_KEY_CODES = keyCodes
        } else if mode == .command {
            COMMAND_KEY_CODES = keyCodes
        }

        log.info("Hotkey updated for mode: \(mode), keyCodes: \(keyCodes)")
    }
}

enum TextProcessMode: String, CaseIterable {
    case auto = "AUTO"
    case translate = "TRANSLATE"
    case format = "FORMAT"

    var displayName: String {
        switch self {
        case .auto:
            "自动风格"
        case .translate:
            "翻译风格"
        case .format:
            "整理风格"
        }
    }

    var description: String {
        switch self {
        case .auto:
            "智能判断, 一键省心"
        case .translate:
            "翻译文本, 一键省心"
        case .format:
            "结构重组, 深度优化"
        }
    }
}
