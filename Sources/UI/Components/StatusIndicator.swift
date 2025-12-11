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

    private var overlay: OverlayController { OverlayController.shared }
    @State private var isHovered: Bool = false
    @State private var tooltipPanelId: UUID?
    @State private var isTranslateMode: Bool = Config.shared.TEXT_PROCESS_MODE == .translate

    private var modeColor: Color {
        mode == .normal ? auroraGreen : starlightYellow
    }

    // 基准大小
    private let baseSize: CGFloat = 20

    private var outerSize: CGFloat {
        switch recordState {
        case .idle:
            baseSize
        case .recording, .processing:
            baseSize * 1.25
        default:
            baseSize
        }
    }

    private var innerScale: CGFloat {
        minInnerRatio + (maxInnerRatio - minInnerRatio) * min(volume * 2.0, 1.0)
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
                .frame(width: outerSize, height: outerSize)

            // 外圆背景
            Circle()
                .fill(outerBackgroundColor)
                .frame(width: outerSize, height: outerSize)
                .animation(.quickSpringAnimation, value: isHovered)

            // 外圆
            Circle()
                .strokeBorder(borderGrey, lineWidth: 1)
                .frame(width: outerSize, height: outerSize)

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
                            .frame(width: outerSize, height: outerSize)
                            .scaleEffect(innerScale)
                    }
                } else if recordState == .recording {
                    // 录音圆
                    Circle()
                        .fill(modeColor)
                        .frame(width: outerSize, height: outerSize)
                        .scaleEffect(innerScale)
                } else if recordState == .processing {
                    Spinner(
                        color: modeColor,
                        size: outerSize / 2
                    )
                }
            }
            .animation(.quickSpringAnimation, value: innerScale)
        }
        .frame(width: outerSize, height: outerSize)
        .scaleEffect(isHovered ? 1.5 : 1.0, anchor: .bottom)
        .offset(y: recordState == .idle ? 0 : -4 - (outerSize - baseSize) / 2)
        .shadow(color: .overlaySecondaryBackground.opacity(0.2), radius: 6, x: 0, y: 0)
        .animation(.quickSpringAnimation, value: outerSize)
        .animation(.quickSpringAnimation, value: isHovered)
        .animation(.quickSpringAnimation, value: recordState)
        .compatibleHover { hovering in
            guard ConnectionCenter.shared.audioRecorderState == .idle else { return }
            isHovered = hovering

            // Suitable for macOS 10.15
            Task { @MainActor in
                StatusPanelManager.shared.ignoresMouseEvents(ignore: !hovering)
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
