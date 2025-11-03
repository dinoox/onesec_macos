import SwiftUI
import Combine

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
    let expandToCapsule: Bool = false // 控制是否在 recording/processing 时扩张为胶囊型

    private let overlay = OverlayController.shared
    @State private var isHovered: Bool = false
    @State private var tooltipPanelId: UUID?
    @State private var isTranslateMode: Bool = Config.shared.TEXT_PROCESS_MODE == .translate

    private var modeColor: Color {
        mode == .normal ? auroraGreen : starlightYellow
    }

    // 基准大小
    private let baseSize: CGFloat = 20

    // 是否应该显示胶囊形
    private var shouldShowCapsule: Bool {
        expandToCapsule && (recordState == .recording || recordState == .processing)
    }

    // 外圆宽度 (胶囊模式下横向扩展)
    private var outerWidth: CGFloat {
        shouldShowCapsule ? baseSize * 1.8 : baseSize
    }

    // 外圆缩放比例
    private var outerScale: CGFloat {
        switch recordState {
        case .idle:
            1.0
        case .recording, .processing:
            expandToCapsule ? 1.25 : 1.25
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
            modeColor.opacity(0.5)
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
            RoundedRectangle(cornerRadius: baseSize / 2)
                .fill(outerBackgroundColor)
                .frame(width: outerWidth, height: baseSize)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: outerWidth)

            // 外圆
            RoundedRectangle(cornerRadius: baseSize / 2)
                .strokeBorder(borderColor, lineWidth: 1.2)
                .frame(width: outerWidth, height: baseSize)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: outerWidth)

            // 内圆
            Group {
                if recordState == .idle {
                    if isTranslateMode {
                        Text("译")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(modeColor)
                    } else {
                        Circle()
                            .fill(borderGrey)
                            .frame(width: innerSize, height: innerSize)
                    }
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
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: innerSize)
        }
        .frame(width: baseSize, height: baseSize)
        .scaleEffect(outerScale, anchor: .bottom)
        .scaleEffect(isHovered ? 1.5 : 1.0, anchor: .bottom)
        .offset(y: recordState == .idle ? 0 : -4)
        .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 2)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: recordState)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: outerScale)
        .onHover { hovering in
            guard ConnectionCenter.shared.audioRecorderState == .idle else { return }
            StatusPanelManager.shared.ignoresMouseEvents(ignore: !hovering)
            isHovered = hovering

            if hovering {
                let uuid = overlay.showOverlay { _ in
                    Text("按住 fn 开始语音输入 或  点击进行设置")
                        .font(.system(size: 12))
                        .foregroundColor(.overlayText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.overlayBackground),
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(borderGrey.opacity(0.8), lineWidth: 1),
                        )
                        .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 2)
                }
                tooltipPanelId = uuid
            } else {
                if let panelId = tooltipPanelId {
                    overlay.hideOverlay(uuid: panelId)
                    tooltipPanelId = nil
                }
            }
        }
        .onReceive(Config.shared.$TEXT_PROCESS_MODE) { mode in
            isTranslateMode = mode == .translate
        }
    }
}
