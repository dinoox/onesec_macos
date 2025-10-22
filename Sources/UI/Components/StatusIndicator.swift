import SwiftUI

struct RecordingState {
    var volume: CGFloat = 0 // 音量值 (0-1)
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

    let minInnerRatio: CGFloat = 0.2 // 内圆最小为外圆的20%
    let maxInnerRatio: CGFloat = 0.7 // 内圆最大为外圆的70%

    private let overlay = OverlayController.shared
    @State private var isHovered: Bool = false
    @State private var tooltipPanelId: UUID?

    private var modeColor: Color {
        mode == .normal ? auroraGreen : starlightYellow
    }

    // 基准大小
    private let baseSize: CGFloat = 20

    // 外圆缩放比例
    private var outerScale: CGFloat {
        switch recordState {
        case .idle:
            1.0
        case .recording, .processing:
            1.25
        default:
            1.0
        }
    }

    private var innerSize: CGFloat {
        let ratio = minInnerRatio + (maxInnerRatio - minInnerRatio) * volume
        return baseSize * ratio
    }

    // 外圆背景颜色
    private var outerBackgroundColor: Color {
        if isHovered {
            return Color.black
        }

        switch recordState {
        case .idle:
            return Color.clear
        case .recording, .processing:
            return Color.black
        default:
            return Color.clear
        }
    }

    // 边框颜色
    private var borderColor: Color {
        switch recordState {
        case .idle:
            borderGrey
        case .recording:
            borderGrey
        default:
            Color.white.opacity(0.8)
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(
            NSMenuItem(
                title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q",
            ))

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
                .frame(width: baseSize, height: baseSize)

            // 外圆背景
            Circle()
                .fill(outerBackgroundColor)
                .frame(width: baseSize, height: baseSize)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)

            // 外圆
            Circle()
                .strokeBorder(borderColor, lineWidth: 1)
                .frame(width: baseSize, height: baseSize)

            // 内圆
            Group {
                if recordState == .idle {
                    Circle()
                        .fill(borderGrey)
                        .frame(width: innerSize, height: innerSize)
                } else if recordState == .recording {
                    Circle()
                        .fill(modeColor)
                        .frame(width: innerSize, height: innerSize)
                } else if recordState == .processing {
                    Spinner(
                        color: modeColor,
                        size: 10,
                    )
                }
            }
            .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: innerSize)
        }
        .frame(width: baseSize, height: baseSize)
        .contentShape(Circle())
        .scaleEffect(outerScale, anchor: .bottom)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: outerScale)
        .scaleEffect(isHovered ? 1.5 : 1.0, anchor: .bottom)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .offset(y: recordState == .idle ? 0 : -4)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: recordState)
        .onHover { hovering in
            isHovered = hovering

            if hovering {
                NSCursor.pointingHand.push()
                let uuid = overlay.showOverlay {
                    Text("按住 fn 开始语音输入 或  点击进行设置")
                        .font(.system(size: 12))
                        .foregroundColor(.overlayText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.overlayBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(borderGrey.opacity(0.8), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 2)
                }
                tooltipPanelId = uuid
            } else {
                NSCursor.pop()
                if let panelId = tooltipPanelId {
                    overlay.hideOverlay(uuid: panelId)
                    tooltipPanelId = nil
                }
            }
        }
    }
}
