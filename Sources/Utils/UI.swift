//
//  Color.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/16.
//

import SwiftUI

let auroraGreen = Color(hex: "#2EDDA8") // 绿色 - normal mode
let starlightYellow = Color(hex: "#ffd479") // 黄色 - command mode

extension Color {
    /// 使用16进制字符串初始化颜色
    /// - Parameter hex: 16进制颜色字符串，支持格式: "#RGB", "#RRGGBB", "#RRGGBBAA"
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RRGGBB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // RRGGBBAA (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255,
        )
    }

    /// 使用16进制整数初始化颜色
    /// - Parameters:
    ///   - hex: 16进制整数，例如 0xFF5733
    ///   - alpha: 透明度 (0.0 - 1.0)
    init(hex: Int, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha,
        )
    }
}

extension String {
    enum ANSIColor: String {
        case reset = "\u{001B}[0m"
        case green = "\u{001B}[38;2;78;172;103m" // RGB(78, 172, 103) - SwiftyBeaver debug 绿色
    }

    func colored(_ color: ANSIColor) -> String {
        "\(color.rawValue)\(self)\(ANSIColor.reset.rawValue)"
    }

    var green: String { colored(.green) }
}

extension Image {
    static func systemSymbol(_ name: String) -> Image {
        if #available(macOS 11.0, *) {
            Image(systemName: name)
        } else {
            Image(nsImage: NSImage(named: NSImage.Name(name)) ?? NSImage())
        }
    }
}
