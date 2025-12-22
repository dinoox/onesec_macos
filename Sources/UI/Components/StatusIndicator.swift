import Combine
import SwiftUI

struct StatusIndicator: View {
    let state: RecordState
    let volume: CGFloat
    let mode: RecordMode
    let minInnerRatio: CGFloat = 0.2 // 内圆最小为外圆的20%
    let maxInnerRatio: CGFloat = 0.7 // 内圆最大为外圆的70%

    private var overlay: OverlayController { OverlayController.shared }
    private var menuBuilder: MenuBuilder { .shared }

    @State private var isHovered: Bool = false
    @State private var tooltipPanelId: UUID?
    @State private var isTranslateMode: Bool = Config.shared.TEXT_PROCESS_MODE == .translate

    private var modeColor: Color {
        switch mode {
        case .normal, .free: auroraGreen
        case .command: starlightYellow
        }
    }

    var isFreeRecording: Bool {
        mode == .free && state == .recording
    }

    // 基准大小
    private let baseSize: CGFloat = 20

    private var outerSize: CGFloat {
        switch state {
        case .idle:
            baseSize
        case .recording, .processing:
            baseSize * 1.25
        default:
            baseSize
        }
    }

    private var freeRecordingInnerCircleSize: CGFloat {
        18.0
    }

    private var innerScale: CGFloat {
        minInnerRatio + (maxInnerRatio - minInnerRatio) * min(volume * 2.0, 1.0)
    }

    // 外圆背景颜色
    private var outerBackgroundColor: Color {
        if isHovered {
            return Color.black
        }

        switch state {
        case .idle:
            return Color.clear
        case .recording, .processing:
            return Color.black
        default:
            return Color.clear
        }
    }

    // 普通模式视图
    private var normalModeView: some View {
        ZStack {
            // 外圆背景
            Circle()
                .fill(outerBackgroundColor)
                .frame(width: outerSize, height: outerSize)
                .overlay(
                    Circle()
                        .strokeBorder(borderGrey, lineWidth: 1)
                )
                .animation(.quickSpringAnimation, value: isHovered)

            // 内圆
            Group {
                if state == .idle {
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
                } else if state == .recording {
                    // 录音圆
                    Circle()
                        .fill(modeColor)
                        .frame(width: outerSize, height: outerSize)
                        .scaleEffect(innerScale)
                } else if state == .processing {
                    Spinner(
                        color: modeColor,
                        size: outerSize / 2
                    )
                }
            }
            .animation(.quickSpringAnimation, value: innerScale)
        }
    }

    // 自由模式
    private var freeModeView: some View {
        HStack(spacing: 5) {
            // 关闭按钮
            Image.systemSymbol("xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white)
                .frame(width: freeRecordingInnerCircleSize, height: freeRecordingInnerCircleSize)
                .padding(0)
                .background(borderGrey)
                .clipShape(Circle())
                .onTapGesture { EventBus.shared.publish(.recordingCancelled) }

            // 音量指示圆
            Circle()
                .fill(modeColor)
                .frame(width: freeRecordingInnerCircleSize, height: freeRecordingInnerCircleSize)
                .scaleEffect(innerScale)
                .animation(.quickSpringAnimation, value: innerScale)

            // 确认按钮
            Image.systemSymbol("checkmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(outerBackgroundColor)
                .frame(width: freeRecordingInnerCircleSize, height: freeRecordingInnerCircleSize)
                .padding(0)
                .background(Color.white)
                .clipShape(Circle())
                .onTapGesture {
                    Task { @MainActor in
                        NSApp.deactivate()
                        EventBus.shared.publish(.recordingConfirmed)
                    }
                }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(outerBackgroundColor)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(borderGrey, lineWidth: 1)
        )
    }

    var body: some View {
        normalModeView
            .opacity(isFreeRecording ? 0 : 1)
            .scaleEffect(isFreeRecording ? 0.5 : 1, anchor: .center)
            .frame(width: outerSize, height: outerSize)
            .overlay(
                freeModeView
                    .opacity(isFreeRecording ? 1 : 0)
                    .scaleEffect(isFreeRecording ? 1 : 0.5, anchor: .bottom)
                    .fixedSize()
            )
            .animation(.quickSpringAnimation, value: isFreeRecording)
            .scaleEffect(isHovered ? 1.5 : 1.0, anchor: .bottom)
            .offset(y: state == .idle ? 0 : (isFreeRecording ? -2 : -4) - (outerSize - baseSize) / 2)
            .shadow(color: .overlaySecondaryBackground.opacity(0.2), radius: 6, x: 0, y: 0)
            .animation(.quickSpringAnimation, value: outerSize)
            .animation(.quickSpringAnimation, value: isHovered)
            .animation(.quickSpringAnimation, value: state)
            .compatibleHover { hovering in
                if isFreeRecording {
                    Task { @MainActor in
                        StatusPanelManager.shared.ignoresMouseEvents(ignore: false)
                    }
                    return
                }
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
            .onTapGesture {
                if isFreeRecording {
                    return
                }
                overlay.hideAllOverlays()
                menuBuilder.showMenu(in: StatusPanelManager.shared.getPanel().contentView!)
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
