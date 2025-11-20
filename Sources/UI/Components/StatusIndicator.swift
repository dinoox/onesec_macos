import Combine
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
    @State private var isTranslateMode: Bool = Config.shared.TEXT_PROCESS_MODE == .translate

    private var modeColor: Color {
        mode == .normal ? auroraGreen : starlightYellow
    }

    // 基准大小
    private var baseSize: CGFloat {
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
        let ratio = minInnerRatio + (maxInnerRatio - minInnerRatio) * min(volume * 2.0, 1.0)
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
                .frame(width: baseSize, height: baseSize)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: baseSize)

            // 外圆
            RoundedRectangle(cornerRadius: baseSize / 2)
                .strokeBorder(borderGrey, lineWidth: 1)
                .frame(width: baseSize, height: baseSize)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: baseSize)

            // 内圆
            Group {
                if recordState == .idle {
                    if isTranslateMode {
                        Text("译")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(borderGrey)
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
                        size: baseSize / 2,
                    )
                }
            }
            .animation(.quickSpringAnimation, value: innerSize)
        }
        .frame(width: baseSize, height: baseSize)
        .scaleEffect(isHovered ? 1.5 : 1.0, anchor: .bottom)
        .offset(y: recordState == .idle ? 0 : -4)
        .shadow(color: .overlayBackground.opacity(0.2), radius: 6, x: 0, y: 0)
        .animation(.quickSpringAnimation, value: isHovered)
        .animation(.quickSpringAnimation, value: recordState)
        .animation(.quickSpringAnimation, value: baseSize)
        .onHover { hovering in
            guard ConnectionCenter.shared.audioRecorderState == .idle else { return }
            StatusPanelManager.shared.ignoresMouseEvents(ignore: !hovering)
            isHovered = hovering

            if hovering {
                let uuid = overlay.showOverlay { panelId in
                    Tooltip(panelID: panelId, content: "按住 fn 开始语音输入 或  点击进行设置", type: .plain, showBell: false)
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
        .onReceive(
            EventBus.shared.eventSubject
                .compactMap { event in
                    if case .recordingStarted = event {
                        return true
                    }
                    return nil
                }
                .receive(on: DispatchQueue.main)
        ) { _ in
            if isHovered {
                isHovered = false
                if let panelId = tooltipPanelId {
                    overlay.hideOverlay(uuid: panelId)
                    tooltipPanelId = nil
                }
            }
        }
    }
}
