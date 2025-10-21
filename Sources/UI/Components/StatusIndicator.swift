import SwiftUI

struct RecordingState {
    var volume: CGFloat = 0  // 音量值 (0-1)
    var state: RecordState = .idle
    var mode: RecordMode = .normal

    var modeColor: Color {
        mode == .normal ? auroraGreen : starlightYellow
    }
}

struct StatusIndicator: View {
    let recordState: RecordState
    let volume: CGFloat
    let mode: RecordMode

    let minInnerRatio: CGFloat = 0.2  // 内圆最小为外圆的20%
    let maxInnerRatio: CGFloat = 0.7  // 内圆最大为外圆的70%

    private var modeColor: Color {
        mode == .normal ? auroraGreen : starlightYellow
    }

    // 外圆大小
    private var outerSize: CGFloat {
        switch recordState {
        case .idle:
            20
        case .recording, .processing:
            25
        default:
            20
        }
    }

    private var innerSize: CGFloat {
        let ratio = minInnerRatio + (maxInnerRatio - minInnerRatio) * volume
        return outerSize * ratio
    }

    // 外圆背景颜色
    private var outerBackgroundColor: Color {
        switch recordState {
        case .idle:
            Color.clear
        case .recording, .processing:
            Color.black
        default:
            Color.clear
        }
    }

    // 边框颜色
    private var borderColor: Color {
        switch recordState {
        case .idle:
            Color(hex: "#888888B2")
        case .recording:
            Color(hex: "#888888B2")
        default:
            Color.white.opacity(0.8)
        }
    }

    private func showMenu() {
        log.info("showMenu")
        let menu = NSMenu()
        menu.addItem(
            NSMenuItem(
                title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        if let button = NSApp.windows.first?.contentView {
            let location = button.bounds.origin
            menu.popUp(positioning: nil, at: location, in: button)
        }
    }

    var body: some View {
        ZStack {
            // 点击响应层
            Circle()
                .fill(Color.white.opacity(0.001))
                .frame(width: outerSize, height: outerSize).onHover { isHovering in
                    if isHovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }

            // 外圆背景
            Circle()
                .fill(outerBackgroundColor)
                .frame(width: outerSize, height: outerSize)

            // 外圆
            Circle()
                .strokeBorder(borderColor, lineWidth: 1)
                .frame(width: outerSize, height: outerSize)

            // 内圆
            Group {
                if recordState == .idle {
                    Circle()
                        .fill(Color(hex: "#888888B2"))
                        .frame(width: innerSize, height: innerSize)
                } else if recordState == .recording {
                    Circle()
                        .fill(modeColor)
                        .frame(width: innerSize, height: innerSize)
                } else if recordState == .processing {
                    Spinner(
                        color: modeColor,
                        size: 13,
                    )
                }
            }
            .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: innerSize)
        }
        .frame(width: outerSize, height: outerSize)
        .contentShape(Circle())
        .offset(y: recordState == .idle ? 0 : -4)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: recordState)
    }
}
