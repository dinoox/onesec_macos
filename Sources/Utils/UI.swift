//
//  UI.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/16.
//

import AppKit
import SwiftUI

let auroraGreen = Color(hex: "#2EDDA8")
let starlightYellow = Color(hex: "#FFD479")
let primaryYellow = Color(red: 245 / 255, green: 193 / 255, blue: 87 / 255)
let borderGrey = Color(hex: "#888888B2")
let destructiveRed = Color(hex: "#FF383C")

let greenTextColor = Color(hex: "#5AB23EFF")
let yellowTextColor = Color(hex: "#F7BF1EFF")
let errorTextColor = Color(hex: "#D83036FF")

// MARK: - 自适应主题颜色 根据系统外观自动切换

extension Color {
    var nsColor: NSColor {
        if #available(macOS 11.0, *) {
            return NSColor(self)
        } else {
            return NSColor.black
        }
    }

    static func adaptive(light: Color, dark: Color) -> Color {
        let dynamicColor = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? dark.nsColor : light.nsColor
        }
        if #available(macOS 12.0, *) {
            return Color(nsColor: dynamicColor)
        } else if #available(macOS 11.0, *) {
            return Color(dynamicColor)
        } else {
            return dark
        }
    }

    static var overlayPrimary: Color {
        adaptive(light: auroraGreen, dark: primaryYellow)
    }

    static var overlaySecondaryPrimary: Color {
        adaptive(light: Color(hex: "#00af5f"), dark: yellowTextColor)
    }

    /// Overlay 背景色：亮色模式白色，暗色模式黑色
    static var overlayBackground: Color {
        adaptive(light: .white, dark: Color(red: 24 / 255, green: 24 / 255, blue: 24 / 255))
    }

    /// Overlay 次要背景色：比主背景稍浅
    static var overlaySecondaryBackground: Color {
        adaptive(light: Color(red: 243 / 255, green: 244 / 255, blue: 245 / 255), dark: Color(red: 32 / 255, green: 32 / 255, blue: 32 / 255))
    }

    static var overlayButtonBackground: Color {
        adaptive(light: Color(red: 255 / 255, green: 255 / 255, blue: 255 / 255), dark: Color(red: 28 / 255, green: 28 / 255, blue: 28 / 255))
    }

    static var overlayButtonHoverBackground: Color {
        adaptive(light: Color(red: 245 / 255, green: 245 / 255, blue: 245 / 255), dark: Color(red: 34 / 255, green: 34 / 255, blue: 34 / 255))
    }

    /// Overlay Code 背景色
    static var overlayCodeBackground: Color {
        adaptive(light: Color(red: 248 / 255, green: 248 / 255, blue: 248 / 255), dark: Color(red: 30 / 255, green: 30 / 255, blue: 30 / 255))
    }

    /// Overlay 主要文本：亮色模式黑色，暗色模式白色
    static var overlayText: Color {
        adaptive(light: .black, dark: .white)
    }

    /// Overlay 次要文本：带透明度
    static var overlaySecondaryText: Color {
        adaptive(light: Color(red: 112 / 255, green: 112 / 255, blue: 112 / 255), dark: Color(red: 160 / 255, green: 160 / 255, blue: 160 / 255))
    }

    /// Overlay 占位文本：更淡的颜色
    static var overlayPlaceholder: Color {
        adaptive(light: Color.black.opacity(0.5), dark: Color.white.opacity(0.5))
    }

    /// Overlay 边框：半透明边框
    static var overlayBorder: Color {
        adaptive(light: Color.black.opacity(0.15), dark: Color.white.opacity(0.2))
    }

    /// Overlay 禁用状态颜色
    static var overlayDisabled: Color {
        adaptive(light: Color(red: 168 / 255, green: 171 / 255, blue: 178 / 255), dark: Color.white.opacity(0.5))
    }

    // MARK: - 输入框相关颜色

    /// 输入框背景：非编辑状态
    static var inputBackground: Color {
        adaptive(light: Color.black.opacity(0.05), dark: Color.white.opacity(0.08))
    }

    /// 输入框边框
    static var inputBorder: Color {
        adaptive(light: Color.black.opacity(0.15), dark: Color.white.opacity(0.15))
    }

    /// 按键背景色
    static var keyBackground: Color {
        adaptive(
            light: Color(red: 240 / 255, green: 240 / 255, blue: 240 / 255),
            dark: Color(red: 38 / 255, green: 38 / 255, blue: 38 / 255)
        )
    }

    /// 按键文本颜色
    static var keyText: Color {
        adaptive(
            light: Color(red: 100 / 255, green: 100 / 255, blue: 100 / 255),
            dark: Color(red: 161 / 255, green: 161 / 255, blue: 161 / 255)
        )
    }

    /// 按钮背景色
    static var buttonBackground: Color {
        adaptive(light: Color.black.opacity(0.1), dark: Color.white.opacity(0.1))
    }

    /// 按钮文本颜色
    static var buttonText: Color {
        adaptive(light: Color.black.opacity(0.7), dark: Color.white.opacity(0.7))
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
        case green = "\u{001B}[38;5;35m" // SwiftyBeaver debug color
        case yellow = "\u{001B}[38;5;178m" // SwiftyBeaver warning color
        case red = "\u{001B}[38;5;197m" // SwiftyBeaver error color
    }

    func colored(_ color: ANSIColor) -> String {
        "\(color.rawValue)\(self)\(ANSIColor.reset.rawValue)"
    }

    var green: String { colored(.green) }
    var yellow: String { colored(.yellow) }
    var red: String { colored(.red) }
}

struct SymbolImage: View {
    let name: String

    private static let textSymbols: [String: String] = [
        "xmark": "✕",
        "checkmark": "✓",
        "doc.on.doc": "⧉",
        "bell.fill": "🔔",
        "sparkles": "✨",
        "mic": "🎤",
    ]

    private var nsImage: NSImage? {
        guard let url = Bundle.resourceBundle.url(forResource: name, withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }

    var body: some View {
        if let symbol = Self.textSymbols[name] {
            Text(symbol).font(.system(size: 12))
        } else {
            Text(name).font(.system(size: 12))
        }
    }

    func font(_: Font) -> some View { self }
}

extension Image {
    @ViewBuilder
    static func systemSymbol(_ name: String) -> some View {
        if #available(macOS 11.0, *) {
            Image(systemName: name)
        } else {
            SymbolImage(name: name)
        }
    }
}

extension View {
    @ViewBuilder
    func symbolReplaceEffect<V: Equatable>(value: V) -> some View {
        if #available(macOS 14.0, *) {
            self.contentTransition(.symbolEffect(.replace))
        } else {
            animation(.easeInOut(duration: 0.2), value: value)
        }
    }

    @ViewBuilder
    func symbolAppearEffect(isActive: Bool) -> some View {
        if #available(macOS 14.0, *) {
            self.symbolEffect(.appear.byLayer.wholeSymbol, options: .nonRepeating, isActive: !isActive)
        } else {
            opacity(isActive ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.2), value: isActive)
        }
    }

    @ViewBuilder
    func symbolWiggleEffect(isActive: Bool) -> some View {
        if #available(macOS 15.0, *) {
            self.symbolEffect(.wiggle.wholeSymbol, options: .nonRepeating, isActive: isActive)
        } else {
            self
        }
    }
}

// Font

func getTextWidth(text: String, font: NSFont = NSFont.systemFont(ofSize: 13.5)) -> CGFloat {
    let size = (text as NSString).size(withAttributes: [.font: font])
    return size.width
}

func getTextCardWidth(text: String) -> CGFloat {
    let textWidth = getTextWidth(text: text)
    return {
        switch textWidth {
        case ..<100: return 230
        case ..<200: return 260
        case ..<500: return 300
        case ..<1000: return 330
        default: return 360
        }
    }()
}
