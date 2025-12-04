import AppKit
import Combine
import SwiftUI

struct StatusView: View {
    @State var recording = RecordingState()
    private var overlay: OverlayController { OverlayController.shared }

    var body: some View {
        // 状态指示器
        StatusIndicator(
            recordState: recording.state,
            volume: recording.volume,
            mode: recording.mode
        )
        .onTapGesture {
            overlay.hideAllOverlays()
            MenuBuilder.shared.showMenu(in: StatusPanelManager.shared.getPanel().contentView!)
        }
        .padding(.bottom, 4)
        .frame(width: 200, height: 80, alignment: .bottom)
        .onReceive(
            EventBus.shared.events
                .receive(on: DispatchQueue.main),
        ) { event in
            handleEvent(event)
        }
        .onReceive(
            ConnectionCenter.shared.$permissionsState
                .receive(on: DispatchQueue.main),
        ) { permissionsState in
            handlePermissionChange(permissionsState)
        }
    }
}

extension StatusView {
    private func handleEvent(_ event: AppEvent) {
        switch event {
        case let .volumeChanged(volume):
            recording.volume = CGFloat(volume)
        case let .recordingStarted(mode):
            recording.mode = mode
            recording.state = .recording
        case .recordingStopped:
            recording.state = .processing
            recording.volume = 0
        case let .modeUpgraded(from, to):
            log.info("Receive modeUpgraded: \(from) \(to)")
            if to == .command {
                recording.mode = to
            }
        case .userDataUpdated:
            if ConnectionCenter.shared.isAuthed,
               ConnectionCenter.shared.hasPermissions()
            {
                overlay.hideOverlays(.notificationSystem)
            }
        case let .notificationReceived(notificationType):
            log.info("Receive notification: \(notificationType)")

            var showTimerTip = false
            var autoCloseDuration = 5
            if notificationType != .recordingTimeoutWarning {
                log.info("Reset recording state to idle")
                recording.state = .idle
                recording.volume = 0
            } else {
                showTimerTip = true
                autoCloseDuration = 15
            }

            if case .serverUnavailable(duringRecording: false) = notificationType {
                return
            }

            showNotificationMessage(
                title: notificationType.title, content: notificationType.content,
                type: notificationType.type,
                autoHide: notificationType.shouldAutoHide,
                showTimerTip: showTimerTip,
                autoCloseDuration: autoCloseDuration,
            )
        case let .hotWordAddRequested(word):
            ContentCard<EmptyView>.show(title: "热词添加", content: "检测到热词 \"\(word)\", 是否添加到词库？", actionButtons: [
                ActionButton(title: "添加") {
                    Task { @MainActor in
                        do {
                            let response = try await HTTPClient.shared.post(
                                path: "/hotword/create",
                                body: ["hotword": word]
                            )

                            if response.success == true {
                                Tooltip.show(content: "添加成功 请在词库中查看")
                            }
                        } catch {}
                    }
                },
            ])
        case let .serverResultReceived(text, _, processMode, polishedText):
            recording.state = .idle
            if text.isEmpty {
                return
            }

            Task {
                let canPaste = await canPasteNow()
                defer {
                    handleAlert(canPaste: canPaste, processMode: processMode, text: text, polishedText: polishedText)
                }

                if processMode == .terminal && text.newlineCount >= 1 {
                    return
                }

                await AXPasteboardController.pasteTextToActiveApp(text)
            }
        case let .terminalLinuxChoice(_, _, _, commands):
            recording.state = .idle
            log.info("Receive terminalLinuxChoice: \(commands)")
            LinuxCommandCard.show(commands: commands)
        default:
            break
        }
    }

    private func canPasteNow() async -> Bool {
        // 1.
        // 首先根据白名单使用零宽字符复制测试方法
        if isAppShouldTestWithZeroWidthChar() {
            log.info("Use zero width char paste test")
            return await AXPasteboardController.whasTextInputFocus()
        }

        // 2.
        // 当前应用有焦点元素, 说明支持 AX
        // 如果是可编辑的元素则直接粘贴, 否则弹窗
        let element = AXElementAccessor.getFocusedElement()
        let isEditable = element.map { AXElementAccessor.isEditableElement($0) } ?? false

        if element != nil, !isAppWithoutAXSupport() {
            log.info("Use AX paste test")
            return isEditable
        }

        // 3.
        // 对于 AX 黑名单应用
        // 使用粘贴探针检测是否可以粘贴
        log.info("Fallback to paste probe")
        return await AXPasteProbe.isPasteAllowed()
    }

    private func handleAlert(canPaste: Bool, processMode: TextProcessMode, text: String, polishedText: String) {
        let cardWidth: CGFloat = getTextCardWidth(text: text)

        if canPaste {
            if processMode == .translate {
                guard Config.shared.USER_CONFIG.translation.showComparison else { return }
                ContentCard<EmptyView>.show(title: "输入原文", content: polishedText, onTap: nil, actionButtons: nil, cardWidth: cardWidth, spacingX: 8, spacingY: 14, panelType: .translate(.above))
            } else if processMode == .terminal, text.newlineCount >= 1 {
                LinuxCommandCard.show(commands: [LinuxCommand(distro: "", command: text, displayName: "")])
            }
        } else {
            if processMode == .translate {
                guard Config.shared.USER_CONFIG.translation.showComparison else { return }
                MultiContentCard.show(title: "识别结果", items: [
                    ContentItem(title: "原文", content: polishedText),
                    ContentItem(title: "译文", content: text),
                ], cardWidth: cardWidth, panelType: .translate(.bottom))
                return
            }
            if recording.mode == .command {
                if ConnectionCenter.shared.currentRecordingAppContext.focusContext.selectedText.isEmpty {
                    ContentCard<EmptyView>.show(title: "处理结果", content: text, cardWidth: cardWidth, panelType: .command)
                } else {
                    ContentCard<EmptyView>.showAboveSelection(title: "处理结果", content: text, cardWidth: cardWidth, spacingX: 8, spacingY: 14, panelType: .command)
                }
            } else {
                ContentCard<EmptyView>.show(title: "识别结果", content: text, cardWidth: cardWidth, panelType: .notification)
            }
        }
    }

    func showNotificationMessage(
        title: String, content: String,
        type: NotificationType = .warning,
        autoHide: Bool = true, onTap: (() -> Void)? = nil,
        showTimerTip: Bool = false, autoCloseDuration: Int = 5,
    ) {
        overlay.showOverlay(
            content: { panelId in
                NotificationCard(
                    title: title,
                    content: content,
                    panelId: panelId,
                    type: type,
                    autoHide: autoHide,
                    showTimerTip: showTimerTip,
                    autoCloseDuration: autoCloseDuration,
                    onTap: onTap
                )
            },
            panelType: .notificationSystem
        )
    }

    private func handlePermissionChange(_ permissionsState: [PermissionType: PermissionStatus]) {
        guard !permissionsState.isEmpty else { return }

        if !ConnectionCenter.shared.hasPermissions() {
            showPermissionAlert()
            SoundService.shared.playSound(.notification)
        } else {
            overlay.hideOverlays(.notificationSystem)
        }
    }

    private func showPermissionAlert() {
        let permissionState = ConnectionCenter.shared.permissionsState
        var missingPermissions: [String] = []

        if permissionState[.microphone] != .granted {
            missingPermissions.append("麦克风")
        }
        if permissionState[.accessibility] != .granted {
            missingPermissions.append("辅助功能")
        }

        guard !missingPermissions.isEmpty else { return }

        showNotificationMessage(
            title: "权限缺失",
            content: "需要\(missingPermissions.joined(separator: "、"))权限，点击前往设置",
            autoHide: false,
            onTap: {
                if permissionState[.accessibility] != .granted {
                    PermissionService.shared.request(.accessibility) { _ in }
                } else if permissionState[.microphone] != .granted {
                    PermissionService.shared.request(.microphone) { _ in }
                }
            },
        )
    }
}
