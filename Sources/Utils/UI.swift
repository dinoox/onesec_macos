//
//  Color.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/16.
//

import SwiftUI

let auroraGreen = Color(hex: "#2EDDA8")
let starlightYellow = Color(hex: "#ffd479")

// MARK: - 自适应主题颜色 根据系统外观自动切换

extension Color {
    static func adaptive(light: NSColor, dark: NSColor) -> Color {
        let dynamicColor = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? dark : light
        }
        if #available(macOS 12.0, *) {
            return Color(nsColor: dynamicColor)
        } else if #available(macOS 11.0, *) {
            return Color(dynamicColor)
        } else {
            return Color(dark)
        }
    }

    /// Overlay 背景色：亮色模式白色，暗色模式黑色
    static var overlayBackground: Color {
        adaptive(light: .white, dark: NSColor(red: 10/255, green: 10/255, blue: 10/255, alpha: 1.0))
    }

    /// Overlay 主要文本：亮色模式黑色，暗色模式白色
    static var overlayText: Color {
        adaptive(light: .black, dark: .white)
    }

    /// Overlay 次要文本：带透明度
    static var overlaySecondaryText: Color {
        adaptive(light: NSColor.black.withAlphaComponent(0.7), dark: NSColor.white.withAlphaComponent(0.85))
    }

    /// Overlay 占位文本：更淡的颜色
    static var overlayPlaceholder: Color {
        adaptive(light: NSColor.black.withAlphaComponent(0.5), dark: NSColor.white.withAlphaComponent(0.5))
    }

    /// Overlay 边框：半透明边框
    static var overlayBorder: Color {
        adaptive(light: NSColor.black.withAlphaComponent(0.15), dark: NSColor.white.withAlphaComponent(0.15))
    }

    // MARK: - 输入框相关颜色

    /// 输入框背景：非编辑状态
    static var inputBackground: Color {
        adaptive(light: NSColor.black.withAlphaComponent(0.05), dark: NSColor.white.withAlphaComponent(0.08))
    }

    /// 输入框边框
    static var inputBorder: Color {
        adaptive(light: NSColor.black.withAlphaComponent(0.15), dark: NSColor.white.withAlphaComponent(0.15))
    }

    /// 按键背景色
    static var keyBackground: Color {
        adaptive(
            light: NSColor(red: 240/255, green: 240/255, blue: 240/255, alpha: 1.0),
            dark: NSColor(red: 38/255, green: 38/255, blue: 38/255, alpha: 1.0),
        )
    }

    /// 按键文本颜色
    static var keyText: Color {
        adaptive(
            light: NSColor(red: 100/255, green: 100/255, blue: 100/255, alpha: 1.0),
            dark: NSColor(red: 161/255, green: 161/255, blue: 161/255, alpha: 1.0),
        )
    }

    /// 按钮背景色
    static var buttonBackground: Color {
        adaptive(light: NSColor.black.withAlphaComponent(0.1), dark: NSColor.white.withAlphaComponent(0.1))
    }

    /// 按钮文本颜色
    static var buttonText: Color {
        adaptive(light: NSColor.black.withAlphaComponent(0.7), dark: NSColor.white.withAlphaComponent(0.7))
    }
}

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
            (r, g, b, a) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r)/255,
            green: Double(g)/255,
            blue: Double(b)/255,
            opacity: Double(a)/255,
        )
    }

    /// 使用16进制整数初始化颜色
    /// - Parameters:
    ///   - hex: 16进制整数，例如 0xFF5733
    ///   - alpha: 透明度 (0.0 - 1.0)
    init(hex: Int, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF)/255,
            green: Double((hex >> 8) & 0xFF)/255,
            blue: Double(hex & 0xFF)/255,
            opacity: alpha,
        )
    }
}

extension String {
    enum ANSIColor: String {
        case reset = "\u{001B}[0m"
        case green = "\u{001B}[38;2;78;172;103m" // SwiftyBeaver debug color
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
