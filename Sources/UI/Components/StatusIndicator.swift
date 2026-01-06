import Combine
import SwiftUI

enum IndicatorNetworkStatus {
    case normal
    case unavailable
    case restored
}

struct StatusIndicator: View {
    let state: RecordState
    let volume: CGFloat
    let mode: RecordMode
    let minInnerRatio: CGFloat = 0.2 // 内圆最小为外圆的20%
    let maxInnerRatio: CGFloat = 0.7 // 内圆最大为外圆的70%

    private var overlay: OverlayController { OverlayController.shared }
    private var menuBuilder: MenuBuilder { .shared }
    private var axObserver: AXSelectionObserver { .shared }
    @ObservedObject private var config = Config.shared

    @State private var isHovered: Bool = false
    @State private var tooltipPanelId: UUID?

    @State private var networkStatus: IndicatorNetworkStatus = ConnectionCenter.shared.indicatorNetworkStatus
    @State private var rippleId: UUID = .init()
    @State private var fadeOpacity: Double = 1.0
    @State private var fadeTimer: AnyCancellable?

    private var modeColor: Color {
        switch mode {
        case .normal, .free, .persona: auroraGreen
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

    private func startFadeTimer() {
        fadeOpacity = 1.0
        fadeTimer?.cancel()
        let duration: Double = 100
        let interval = 0.1
        let step = interval / duration
        fadeTimer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                fadeOpacity -= step
                if fadeOpacity <= 0 {
                    fadeOpacity = 0
                    fadeTimer?.cancel()
                    fadeTimer = nil
                    StatusPanelManager.shared.hidePanel()
                    fadeOpacity = 1.0
                }
            }
    }

    private func cancelFadeTimer() {
        fadeTimer?.cancel()
        fadeTimer = nil
        fadeOpacity = 1.0
    }

    // 网络状态边框颜色
    private var networkBorderColor: Color {
        if networkStatus == .normal { return borderGrey }
        return networkStatus == .unavailable ? destructiveRed : greenTextColor
    }

    // 普通模式视图
    private var normalModeView: some View {
        ZStack {
            // 网络状态波纹效果
            if networkStatus != .normal {
                RippleEffect(
                    color: networkStatus == .unavailable ? destructiveRed : greenTextColor,
                    rippleId: rippleId
                )
                .frame(width: outerSize, height: outerSize)
            }

            // 外圆背景
            Circle()
                .fill(outerBackgroundColor)
                .frame(width: outerSize, height: outerSize)
                .overlay(
                    Circle()
                        .strokeBorder(networkBorderColor, lineWidth: 1)
                )
                .animation(.quickSpringAnimation, value: isHovered)
                .animation(.spring, value: networkStatus)

            // 内圆
            Group {
                // 空闲
                if state == .idle {
                    ZStack {
                        if let persona = config.CURRENT_PERSONA,
                           persona.id != 1,
                           let svgString = persona.iconSvg,
                           let svgData = svgString.data(using: .utf8),
                           let nsImage = NSImage(data: svgData)
                        {
                            Image(nsImage: nsImage)
                                .resizable()
                                .renderingMode(.template)
                                .foregroundColor(networkBorderColor)
                                .frame(width: 12, height: 12)
                                .id("persona-\(persona.id)")
                                .transition(.scale.combined(with: .opacity))
                        } else {
                            Circle()
                                .fill(networkBorderColor)
                                .frame(width: outerSize, height: outerSize)
                                .scaleEffect(innerScale)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.quickSpringAnimation, value: config.CURRENT_PERSONA?.id)
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
            .compatibleHover(useBackground: true) { hovering in
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
                        if Config.shared.USER_CONFIG.setting.hideStatusPanel {
                            StatusPanelManager.shared.showPanel()
                        }
                        let uuid = overlay.showOverlay(content: { panelId in
                            Tooltip(panelID: panelId, content: "按住 fn 开始语音输入 或  点击进行设置", type: .plain, showBell: false)
                        }, panelType: .notification)
                        tooltipPanelId = uuid
                    } else {
                        if let panelId = tooltipPanelId {
                            overlay.hideOverlay(uuid: panelId)
                            tooltipPanelId = nil
                        }
                        if Config.shared.USER_CONFIG.setting.hideStatusPanel {
                            StatusPanelManager.shared.hidePanel()
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
            .opacity(fadeOpacity)
            .onReceive(
                EventBus.shared.eventSubject
                    .receive(on: DispatchQueue.main)
            ) { event in
                handleEvent(event)
            }
    }

    private func flushNetworkStatus(_ status: IndicatorNetworkStatus) {
        networkStatus = status
        ConnectionCenter.shared.indicatorNetworkStatus = status
        if status != .normal {
            rippleId = UUID()
        }
    }

    private func handleEvent(_ event: AppEvent) {
        if case .recordingStarted = event {
            if isHovered {
                isHovered = false
                if let panelId = tooltipPanelId {
                    overlay.hideOverlay(uuid: panelId)
                    tooltipPanelId = nil
                }
            }
            flushNetworkStatus(.normal)
            return
        }

        if case .notificationReceived(.networkUnavailable) = event {
            if Config.shared.USER_CONFIG.setting.hideStatusPanel {
                StatusPanelManager.shared.showPanel()
                startFadeTimer()
            }
            flushNetworkStatus(.unavailable)
        } else if case .notificationReceived(.wssRestored) = event, networkStatus != .normal {
            handleNetworkRestored()
        } else if case .notificationReceived(.networkRestored) = event, ConnectionCenter.shared.canRecord() {
            handleNetworkRestored()
        } else if case let .recordingStopped(isRecordingStarted, shouldSetResponseTimer) = event {
            if !shouldSetResponseTimer, !ConnectionCenter.shared.canResumeAfterNetworkError(), isRecordingStarted, !ConnectionCenter.shared.canRecord() {
                flushNetworkStatus(.unavailable)
            }
        } else if case let .notificationReceived(notificationType) = event {
            let shouldShowAction: Bool = {
                if case let .error(_, _, errorCode) = notificationType {
                    return errorCode != "ASR_LIMIT_EXCEEDED"
                }
                return notificationType == .serverTimeout
            }()
            if shouldShowAction, !ConnectionCenter.shared.canRecord() {
                flushNetworkStatus(.unavailable)
            }
        }
    }

    private func handleNetworkRestored() {
        if networkStatus == .normal {
            return
        }

        cancelFadeTimer()
        flushNetworkStatus(.restored)

        Task { @MainActor in
            try? await sleep(3000)
            flushNetworkStatus(.normal)
            log.info("indicator network restored")
            guard !ConnectionCenter.shared.isInRecordingSession(),
                  !OverlayController.shared.hasStatusPanelTrigger(),
                  Config.shared.USER_CONFIG.setting.hideStatusPanel else { return }
            StatusPanelManager.shared.hidePanel()
        }
    }
}
