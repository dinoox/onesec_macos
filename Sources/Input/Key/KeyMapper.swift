//
//  KeyMapper.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/16.
//

import Foundation

class KeyMapper {
    static let keyCodeMap: [Int64: String] = [
        // 字母键
        0: "A",
        1: "S",
        2: "D",
        3: "F",
        4: "H",
        5: "G",
        6: "Z",
        7: "X",
        8: "C",
        9: "V",
        11: "B",
        12: "Q",
        13: "W",
        14: "E",
        15: "R",
        16: "Y",
        17: "T",
        31: "O",
        32: "U",
        34: "I",
        35: "P",
        37: "L",
        38: "J",
        40: "K",
        45: "N",
        46: "M",
        
        // 功能键
        49: "Space",
        36: "Return",
        48: "Tab",
        51: "Delete",
        53: "Escape",
        
        // 修饰键（左侧）
        55: "Left Command ⌘",
        56: "Left Shift ⇧",
        58: "Left Option ⌥",
        59: "Left Control ⌃",
        
        // 修饰键（右侧）
        54: "Right Command ⌘",
        60: "Right Shift ⇧",
        61: "Right Option ⌥",
        62: "Right Control ⌃",
        
        // Fn 键
        63: "Fn"
    ]
    
    /// 反向映射：从字符串到键码
    static let stringToKeyCodeMap: [String: Int64] = {
        var map: [String: Int64] = [:]
        for (code, name) in keyCodeMap {
            // 保存原始名称
            map[name] = code
            // 同时保存大写版本
            map[name.uppercased()] = code
            // 为修饰键添加简化版本
            if name.contains("Left Command") {
                map["Left Cmd"] = code
                map["LCmd"] = code
            } else if name.contains("Right Command") {
                map["Right Cmd"] = code
                map["RCmd"] = code
            } else if name.contains("Left Shift") {
                map["LShift"] = code
            } else if name.contains("Right Shift") {
                map["RShift"] = code
            } else if name.contains("Left Option") {
                map["LOpt"] = code
                map["Left Alt"] = code
            } else if name.contains("Right Option") {
                map["ROpt"] = code
                map["Right Alt"] = code
            } else if name.contains("Left Control") {
                map["LCtrl"] = code
            } else if name.contains("Right Control") {
                map["RCtrl"] = code
            }
        }
        return map
    }()
    
    /// 将字符串组合转换为键码数组
    /// - Parameter keyString: 按键组合字符串，如 "Fn+Space" 或 "Fn"
    /// - Returns: 对应的键码数组，如果有无效按键则返回 nil
    static func parseKeyString(_ keyString: String) -> [Int64]? {
        // 去首尾空格
        let trimmed = keyString.trimmingCharacters(in: .whitespaces)
        
        // 按 + 分割
        let keys = trimmed.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        
        let keyCodes = keys.compactMap { stringToKeyCodeMap[$0] }
        guard keyCodes.count == keys.count else { return nil }
        
        return keyCodes
    }
    
    static func keyCodeToString(_ keyCode: Int64) -> String {
        keyCodeMap[keyCode] ?? "Key(\(keyCode))"
    }
    
    static func keyCodesToString(_ keyCodes: some Collection<Int64>) -> String {
        keyCodes
            .compactMap { keyCodeMap[$0] }
            .joined(separator: "+")
    }
}
